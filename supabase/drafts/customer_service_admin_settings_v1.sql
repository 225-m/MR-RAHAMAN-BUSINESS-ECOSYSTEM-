-- MR RAHAMAN Business Ecosystem
-- CUSTOMER SERVICE ADMIN SETTINGS V1 — DRAFT ONLY; NOT APPLIED TO PRODUCTION.
-- Uses platform-scoped permissions, separate from the 41 organization permissions.
-- All optional verification/payment features start OFF and readiness='prepared'.

begin;

create table if not exists private.platform_permissions (
  permission_key text primary key,
  description text not null,
  created_at timestamptz not null default pg_catalog.now()
);

create table if not exists private.platform_role_permissions (
  role_key text not null
    check (role_key in ('platform_admin','security_admin','support_admin')),
  permission_key text not null
    references private.platform_permissions(permission_key) on delete restrict,
  granted_at timestamptz not null default pg_catalog.now(),
  primary key (role_key, permission_key)
);

insert into private.platform_permissions(permission_key, description)
values
  ('customer_verification.settings.manage',
   'Manage customer contact verification and future KYC feature availability'),
  ('customer_payment.settings.manage',
   'Manage customer payment provider and card-payment feature availability')
on conflict (permission_key) do nothing;

-- Only the trusted platform_admin role receives these settings permissions.
-- Platform Owner is implicitly authorized by private.has_platform_permission().
insert into private.platform_role_permissions(role_key, permission_key)
values
  ('platform_admin','customer_verification.settings.manage'),
  ('platform_admin','customer_payment.settings.manage')
on conflict (role_key, permission_key) do nothing;

create table if not exists private.customer_service_feature_settings (
  feature_key text primary key,
  feature_group text not null
    check (feature_group in ('customer_verification','customer_payment')),
  is_enabled boolean not null default false,
  readiness_status text not null default 'prepared'
    check (readiness_status in
      ('prepared','requires_setup','testing','ready_to_enable','suspended')),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default pg_catalog.now(),
  check (
    feature_key like 'customer_verification.%'
    and feature_group = 'customer_verification'
    or feature_key like 'customer_payment.%'
    and feature_group = 'customer_payment'
  ),
  check (readiness_status <> 'suspended' or is_enabled = false)
);

create table if not exists private.customer_service_feature_audit (
  id bigint generated always as identity primary key,
  actor_user_id uuid references auth.users(id) on delete set null,
  feature_key text not null,
  old_enabled boolean not null,
  new_enabled boolean not null,
  reason text not null,
  changed_at timestamptz not null default pg_catalog.now()
);

alter table private.platform_permissions enable row level security;
alter table private.platform_role_permissions enable row level security;
alter table private.customer_service_feature_settings enable row level security;
alter table private.customer_service_feature_audit enable row level security;

grant usage on schema private to authenticated;

revoke all on table private.platform_permissions,
  private.platform_role_permissions,
  private.customer_service_feature_settings,
  private.customer_service_feature_audit
from public, anon, authenticated, service_role;

-- Feature inventory: no customer data, documents, biometrics, card data,
-- provider credentials, or provider resources are created by this migration.
insert into private.customer_service_feature_settings
  (feature_key, feature_group, is_enabled, readiness_status)
values
  ('customer_verification.master','customer_verification',false,'prepared'),
  ('customer_verification.phone_otp','customer_verification',false,'prepared'),
  ('customer_verification.nid','customer_verification',false,'prepared'),
  ('customer_verification.passport','customer_verification',false,'prepared'),
  ('customer_verification.biometric','customer_verification',false,'prepared'),
  ('customer_verification.ai_review','customer_verification',false,'prepared'),
  ('customer_payment.card_payments','customer_payment',false,'prepared')
on conflict (feature_key) do nothing;

create or replace function private.reject_customer_service_audit_mutation()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  raise exception 'Customer service feature audit is append-only'
    using errcode = '42501';
end;
$function$;

revoke all on function private.reject_customer_service_audit_mutation()
  from public, anon, authenticated, service_role;

drop trigger if exists customer_service_feature_audit_no_mutation
  on private.customer_service_feature_audit;
create trigger customer_service_feature_audit_no_mutation
before update or delete on private.customer_service_feature_audit
for each row execute function private.reject_customer_service_audit_mutation();

create or replace function private.has_platform_permission(p_permission_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select auth.uid() is not null and exists (
    select 1
    from public.platform_admin_roles r
    where r.user_id = auth.uid()
      and r.revoked_at is null
      and (r.expires_at is null or r.expires_at > pg_catalog.now())
      and (
        r.role_key = 'platform_owner'
        or exists (
          select 1
          from private.platform_role_permissions rp
          where rp.role_key = r.role_key
            and rp.permission_key = p_permission_key
        )
      )
  );
$function$;

create or replace function private.customer_service_feature_settings_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_can_verification boolean;
  v_can_payment boolean;
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  v_can_verification := private.has_platform_permission(
    'customer_verification.settings.manage'
  );
  v_can_payment := private.has_platform_permission(
    'customer_payment.settings.manage'
  );

  if not (v_can_verification or v_can_payment) then
    raise exception 'Platform settings permission required' using errcode = '42501';
  end if;

  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'feature_key', s.feature_key,
        'feature_group', s.feature_group,
        'is_enabled', s.is_enabled,
        'readiness_status', s.readiness_status,
        'updated_at', s.updated_at
      ) order by s.feature_key
    ),
    '[]'::jsonb
  )
  into v_result
  from private.customer_service_feature_settings s
  where (s.feature_group = 'customer_verification' and v_can_verification)
     or (s.feature_group = 'customer_payment' and v_can_payment);

  return pg_catalog.jsonb_build_object(
    'features', v_result,
    'can_manage_verification', v_can_verification,
    'can_manage_payment', v_can_payment
  );
end;
$function$;

create or replace function private.set_customer_service_feature_v1(
  p_feature_key text,
  p_enabled boolean,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_feature private.customer_service_feature_settings%rowtype;
  v_permission_key text;
  v_master_enabled boolean;
  v_changed integer := 0;
begin
  if v_actor is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_feature_key is null or p_enabled is null then
    raise exception 'Feature key and enabled state are required' using errcode = '22023';
  end if;
  if pg_catalog.length(pg_catalog.btrim(coalesce(p_reason,''))) < 10 then
    raise exception 'A reason of at least 10 characters is required' using errcode = '22023';
  end if;

  select case
    when feature_group = 'customer_verification'
      then 'customer_verification.settings.manage'
    when feature_group = 'customer_payment'
      then 'customer_payment.settings.manage'
    else null
  end
  into v_permission_key
  from private.customer_service_feature_settings
  where feature_key = p_feature_key;

  if v_permission_key is null then
    raise exception 'Unknown customer service feature' using errcode = '22023';
  end if;
  if not private.has_platform_permission(v_permission_key) then
    raise exception 'Dedicated platform settings permission required' using errcode = '42501';
  end if;

  select * into v_feature
  from private.customer_service_feature_settings
  where feature_key = p_feature_key
  for update;

  if p_enabled and v_feature.readiness_status <> 'ready_to_enable' then
    raise exception 'Feature is not ready to enable: %', v_feature.readiness_status
      using errcode = '55000';
  end if;

  if p_enabled
     and v_feature.feature_group = 'customer_verification'
     and p_feature_key <> 'customer_verification.master' then
    select is_enabled into v_master_enabled
    from private.customer_service_feature_settings
    where feature_key = 'customer_verification.master';
    if coalesce(v_master_enabled,false) is not true then
      raise exception 'Customer verification master switch must be enabled first'
        using errcode = '55000';
    end if;
  end if;

  if p_enabled is false and p_feature_key = 'customer_verification.master' then
    -- Emergency/master-off is immediate and atomically disables all child
    -- verification capabilities. Payment-card settings are independent.
    with changed_children as (
      update private.customer_service_feature_settings
         set is_enabled = false,
             updated_by = v_actor,
             updated_at = pg_catalog.now()
       where feature_group = 'customer_verification'
         and feature_key <> 'customer_verification.master'
         and is_enabled = true
       returning feature_key
    )
    insert into private.customer_service_feature_audit
      (actor_user_id, feature_key, old_enabled, new_enabled, reason)
    select v_actor, c.feature_key, true, false, pg_catalog.btrim(p_reason)
    from changed_children c;
    get diagnostics v_changed = row_count;
  end if;

  if v_feature.is_enabled is distinct from p_enabled then
    update private.customer_service_feature_settings
       set is_enabled = p_enabled,
           updated_by = v_actor,
           updated_at = pg_catalog.now()
     where feature_key = p_feature_key;

    insert into private.customer_service_feature_audit
      (actor_user_id, feature_key, old_enabled, new_enabled, reason)
    values
      (v_actor, p_feature_key, v_feature.is_enabled, p_enabled,
       pg_catalog.btrim(p_reason));
  end if;

  return pg_catalog.jsonb_build_object(
    'success', true,
    'feature_key', p_feature_key,
    'is_enabled', p_enabled,
    'verification_children_disabled', v_changed
  );
end;
$function$;

revoke all on function private.has_platform_permission(text)
  from public, anon, authenticated, service_role;
revoke all on function private.customer_service_feature_settings_v1()
  from public, anon, authenticated, service_role;
revoke all on function private.set_customer_service_feature_v1(text,boolean,text)
  from public, anon, authenticated, service_role;

-- Internal authorization helper is not directly callable by clients.
grant execute on function private.customer_service_feature_settings_v1() to authenticated;
grant execute on function private.set_customer_service_feature_v1(text,boolean,text) to authenticated;

create or replace function public.customer_service_feature_settings_v1()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
  select private.customer_service_feature_settings_v1();
$function$;

create or replace function public.set_customer_service_feature_v1(
  p_feature_key text,
  p_enabled boolean,
  p_reason text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
  select private.set_customer_service_feature_v1(
    p_feature_key, p_enabled, p_reason
  );
$function$;

revoke all on function public.customer_service_feature_settings_v1()
  from public, anon, authenticated;
revoke all on function public.set_customer_service_feature_v1(text,boolean,text)
  from public, anon, authenticated;
grant execute on function public.customer_service_feature_settings_v1()
  to authenticated;
grant execute on function public.set_customer_service_feature_v1(text,boolean,text)
  to authenticated;

commit;

-- REQUIRED TESTS (disposable PostgreSQL only):
-- * All seven feature rows are created OFF with readiness_status='prepared'.
-- * No authenticated client can directly read/write private settings or audit.
-- * Customer, support_admin, security_admin, expired/revoked admin and anon are denied.
-- * Active platform_admin can view settings and toggle only after readiness is approved.
-- * Active platform_owner can manage settings; role must be active and unexpired.
-- * Child verification features cannot be enabled before master.
-- * Disabling master disables all verification children and appends audit rows.
-- * Card payment flag is independent of verification master.
-- * Audit records cannot be updated/deleted.
-- * Email Auth confirmation baseline is not controlled by these feature flags.
-- * No customer documents, biometric samples, card numbers or provider secrets are stored.
