#!/usr/bin/env bash
# Concurrency race test against the disposable local Supabase database only.
# Never point LOCAL_DB_URL at a hosted or Production database.
set -euo pipefail

: "${LOCAL_DB_URL:?LOCAL_DB_URL is required}"
if [[ "$LOCAL_DB_URL" != postgresql://postgres:postgres@127.0.0.1:54322/* && "$LOCAL_DB_URL" != postgresql://postgres:postgres@localhost:54322/* ]]; then
  echo "Refusing to run concurrency fixture outside the disposable local Supabase database" >&2
  exit 1
fi

USER_ID="00000000-0000-4000-8000-000000000227"
TMP_DIR="$(mktemp -d)"
PID_ONE=""
PID_TWO=""
cleanup() {
  [[ -n "$PID_ONE" ]] && kill "$PID_ONE" 2>/dev/null || true
  [[ -n "$PID_TWO" ]] && kill "$PID_TWO" 2>/dev/null || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

psql "$LOCAL_DB_URL" -v ON_ERROR_STOP=1 <<SQL
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
) values (
  '$USER_ID', 'authenticated', 'authenticated',
  'concurrent-founder-fixture@example.test', '',
  pg_catalog.now(),
  '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb
);

create or replace function public.ci_delay_founder_org_insert()
returns trigger language plpgsql as \$\$
begin
  perform pg_catalog.pg_sleep(2);
  return new;
end;
\$\$;

create trigger ci_delay_founder_org_insert
before insert on public.organizations
for each row execute function public.ci_delay_founder_org_insert();
SQL

# Start the first transaction, then race a second caller while the first is
# deliberately paused inside the organization insert. The RPC advisory lock
# must serialize both calls: exactly one succeeds and the other sees closed state.
psql "$LOCAL_DB_URL" -v ON_ERROR_STOP=1 \
  -c "select pg_catalog.set_config('request.jwt.claim.role','service_role',false)" \
  -c "select public.bootstrap_first_project_founder_main_admin_v1('$USER_ID')" \
  >"$TMP_DIR/one.log" 2>&1 &
PID_ONE=$!
sleep 0.35

psql "$LOCAL_DB_URL" -v ON_ERROR_STOP=1 \
  -c "select pg_catalog.set_config('request.jwt.claim.role','service_role',false)" \
  -c "select public.bootstrap_first_project_founder_main_admin_v1('$USER_ID')" \
  >"$TMP_DIR/two.log" 2>&1 &
PID_TWO=$!

set +e
wait "$PID_ONE"; STATUS_ONE=$?
wait "$PID_TWO"; STATUS_TWO=$?
set -e
PID_ONE=""
PID_TWO=""

SUCCESS_COUNT=0
[[ "$STATUS_ONE" -eq 0 ]] && SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
[[ "$STATUS_TWO" -eq 0 ]] && SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
if [[ "$SUCCESS_COUNT" -ne 1 ]]; then
  cat "$TMP_DIR/one.log" "$TMP_DIR/two.log" >&2
  echo "Expected exactly one concurrent bootstrap call to succeed; got $SUCCESS_COUNT" >&2
  exit 1
fi

if [[ "$STATUS_ONE" -ne 0 ]] && ! grep -q "First-founder bootstrap is closed" "$TMP_DIR/one.log"; then
  cat "$TMP_DIR/one.log" >&2
  echo "First request failed for an unexpected reason" >&2
  exit 1
fi
if [[ "$STATUS_TWO" -ne 0 ]] && ! grep -q "First-founder bootstrap is closed" "$TMP_DIR/two.log"; then
  cat "$TMP_DIR/two.log" >&2
  echo "Second request failed for an unexpected reason" >&2
  exit 1
fi

COUNTS="$(psql "$LOCAL_DB_URL" -v ON_ERROR_STOP=1 -At -F '|' -c "
select
  (select count(*) from private.platform_founder_designations),
  (select count(*) from public.organizations),
  (select count(*) from public.organization_members where member_status='active'),
  (select count(*) from public.platform_admin_roles where role_key='platform_owner' and revoked_at is null),
  (select count(*) from public.platform_audit_logs where action='platform_owner.granted'),
  (select count(*) from public.module_audit_logs where action='INITIAL_PROJECT_FOUNDER_MAIN_ADMIN_BOOTSTRAP_COMPLETED');
")"
if [[ "$COUNTS" != "1|1|1|1|1|1" ]]; then
  echo "Concurrent bootstrap left unexpected row counts: $COUNTS" >&2
  cat "$TMP_DIR/one.log" "$TMP_DIR/two.log" >&2
  exit 1
fi

echo "Concurrent first-owner bootstrap race test passed: exactly one caller succeeded; audit and identity rows are singular."
