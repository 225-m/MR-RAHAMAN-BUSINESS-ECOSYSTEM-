-- MR RAHAMAN Business Ecosystem
-- Module Lifecycle V1 integration test harness — staging only.
-- Run with psql against a disposable Supabase project after provisioning fixtures:
-- psql "$STAGING_DB_URL" -v org_id='<uuid>' -v requester_id='<uuid>' \
--   -v approver_id='<uuid>' -v apply_id='<uuid>' -v unauthorized_id='<uuid>' \
--   -v module_key='<non-core-key>' -v request_type='disable' \
--   -f supabase/tests/module_lifecycle_v1.sql
--
-- Fixture requirements:
-- * Four active members in one active organization.
-- * Requester: module.request + approval.approve (self-approval still forbidden).
-- * Approver: approval.approve, different from requester.
-- * Apply actor: module.manage + module.read.
-- * Unauthorized actor: no approval.approve.
-- * Disable test: target is active, non-core, with no active mandatory dependents.
--   Enable test: target is disabled and all mandatory dependencies are active.
-- * No unresolved request exists for the target module.
-- The test transaction is rolled back. Never run against Production.

begin;
set local role authenticated;

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claims',
  pg_catalog.jsonb_build_object('role','authenticated','sub', :'requester_id')::text, true);
select set_config('request.jwt.claim.sub', :'requester_id', true);
select set_config('test.org_id', :'org_id', true);
select set_config('test.requester_id', :'requester_id', true);
select set_config('test.approver_id', :'approver_id', true);
select set_config('test.apply_id', :'apply_id', true);
select set_config('test.approval_id', '', true);
select set_config('test.change_id', '', true);

-- T01: create exactly one request and capture both identifiers.
select
  (r.result->>'module_change_request_id')::uuid as change_id,
  (r.result->>'approval_request_id')::uuid as approval_id
from (
  select public.module_request_change_v1(
    :'org_id'::uuid, :'module_key', :'request_type',
    'Automated Module Lifecycle V1 integration test'
  ) as result
) r
\gset

-- T02: requester cannot approve own request, even with approval.approve.
select set_config('test.approval_id', :'approval_id', true);
select set_config('test.change_id', :'change_id', true);

do $test$
begin
  begin
    perform public.module_approval_decide_v1(
      current_setting('test.org_id')::uuid, current_setting('test.approval_id')::uuid, 'approved', 'self approval attempt'
    );
    raise exception 'T02 FAILED: requester self-approved';
  exception when sqlstate '42501' then
    null;
  end;
end;
$test$;

-- T03: user without approval.approve cannot decide.
select set_config('request.jwt.claims',
  pg_catalog.jsonb_build_object('role','authenticated','sub', :'unauthorized_id')::text, true);
select set_config('request.jwt.claim.sub', :'unauthorized_id', true);

do $test$
begin
  begin
    perform public.module_approval_decide_v1(
      current_setting('test.org_id')::uuid, current_setting('test.approval_id')::uuid, 'approved', 'unauthorized attempt'
    );
    raise exception 'T03 FAILED: unauthorized user approved';
  exception when sqlstate '42501' then
    null;
  end;
end;
$test$;

-- T04: Apply is rejected while the request is still pending.
select set_config('request.jwt.claims',
  pg_catalog.jsonb_build_object('role','authenticated','sub', :'apply_id')::text, true);
select set_config('request.jwt.claim.sub', :'apply_id', true);

do $test$
begin
  begin
    perform public.module_apply_approved_change_v1(
      current_setting('test.org_id')::uuid, current_setting('test.change_id')::uuid
    );
    raise exception 'T04 FAILED: pending request was applied';
  exception when sqlstate '55000' then
    null;
  end;
end;
$test$;

-- T05: a different authorized member approves.
select set_config('request.jwt.claims',
  pg_catalog.jsonb_build_object('role','authenticated','sub', :'approver_id')::text, true);
select set_config('request.jwt.claim.sub', :'approver_id', true);

select public.module_approval_decide_v1(
  :'org_id'::uuid, :'approval_id'::uuid, 'approved', 'independent approval'
);

-- T06: separately authorized apply actor executes the approved change.
select set_config('request.jwt.claims',
  pg_catalog.jsonb_build_object('role','authenticated','sub', :'apply_id')::text, true);
select set_config('request.jwt.claim.sub', :'apply_id', true);

select public.module_apply_approved_change_v1(
  :'org_id'::uuid, :'change_id'::uuid
);

-- T07: a second application is rejected (idempotency / no replay).
do $test$
begin
  begin
    perform public.module_apply_approved_change_v1(
      current_setting('test.org_id')::uuid, current_setting('test.change_id')::uuid
    );
    raise exception 'T07 FAILED: completed request applied twice';
  exception when sqlstate '55000' then
    null;
  end;
end;
$test$;

-- T08: confirm completed request and audit chain are present as the DB test owner.
reset role;
do $test$
declare
  v_status text;
  v_action_count integer;
  v_audit_count integer;
begin
  select status into v_status
  from public.module_change_requests
  where id = current_setting('test.change_id')::uuid and organization_id = current_setting('test.org_id')::uuid;

  if v_status <> 'completed' then
    raise exception 'T08 FAILED: expected completed status, got %', v_status;
  end if;

  select count(*) into v_action_count
  from public.approval_actions
  where approval_request_id = current_setting('test.approval_id')::uuid
    and organization_id = current_setting('test.org_id')::uuid
    and decision = 'approved'
    and actor_user_id = current_setting('test.approver_id')::uuid;

  if v_action_count <> 1 then
    raise exception 'T08 FAILED: independent approval action missing or duplicated';
  end if;

  select count(*) into v_audit_count
  from public.module_audit_logs
  where approval_request_id = current_setting('test.approval_id')::uuid
    and organization_id = current_setting('test.org_id')::uuid
    and action in ('MODULE_CHANGE_REQUESTED','MODULE_CHANGE_APPROVED',
                   'MODULE_ENABLED_AFTER_APPROVAL','MODULE_DISABLED_AFTER_APPROVAL');

  if v_audit_count <> 3 then
    raise exception 'T08 FAILED: expected request, approval and apply audit events; found %', v_audit_count;
  end if;
end;
$test$;

rollback;
