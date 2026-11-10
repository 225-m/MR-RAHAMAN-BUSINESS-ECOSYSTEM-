-- MR RAHAMAN Business Ecosystem
-- FIRST PROJECT FOUNDER + MAIN ADMIN + PLATFORM OWNER BOOTSTRAP V1
-- DRAFT ONLY. DO NOT APPLY TO PRODUCTION.
-- Apply only after reviewed platform_owner_management_v1.sql has created
-- public.platform_audit_logs, and customer_access_v1.sql is ready for staging.
-- This is a new reconciled draft; the older V2 draft remains unchanged.

begin;

create table if not exists private.platform_founder_designations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  project_key text not null unique
    check (project_key = 'mr-rahaman-business-ecosystem'),
  user_id uuid not null unique
    references auth.users(id) on delete restrict,
  designation_key text not null
    check (designation_key = 'project_founder'),
  administrative_title text not null
    check (administrative_title = 'Main Admin'),
  designated_at timestamptz not null default pg_catalog.clock_timestamp(),
  designated_by uuid null
    references auth.users(id) on delete set null,
  bootstrap_version integer not null check (bootstrap_version = 1)
);

alter table private.platform_founder_designations enable row level security;
revoke all on table private.platform_founder_designations
  from public, anon, authenticated, service_role;

create or replace function private.reject_founder_designation_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  raise exception 'Project Founder designation is append-only; UPDATE and DELETE are prohibited'
    using errcode = '55000';
end;
$function$;

revoke all on function private.reject_founder_designation_mutation_v1()
  from public, anon, authenticated, service_role;

drop trigger if exists platform_founder_designations_append_only
  on private.platform_founder_designations;
create trigger platform_founder_designations_append_only
before update or delete on private.platform_founder_designations
for each row execute function private.reject_founder_designation_mutation_v1();

create or replace function public.bootstrap_first_project_founder_main_admin_v1(
  p_expected_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := p_expected_user_id;
  v_org_id uuid;
  v_role_id uuid;
  v_platform_role_id uuid;
  v_founder_id uuid;
  v_permission_count integer;
  v_core_module_count integer;
  v_total_core_module_count integer;
  v_email_confirmed boolean;
begin
  if p_expected_user_id is null then
    raise exception 'An allowlisted expected user ID is required'
      using errcode = '22023';
  end if;

  if coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise exception 'service_role required'
      using errcode = '42501';
  end if;

  if pg_catalog.to_regclass('public.platform_audit_logs') is null then
    raise exception 'platform_owner_management_v1 must be installed first'
      using errcode = '55000';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('mr-rahaman:first-project-founder-main-admin:v1')
  );

  select (u.email_confirmed_at is not null)
    into v_email_confirmed
  from auth.users u
  where u.id = v_user_id;

  if coalesce(v_email_confirmed, false) is not true then
    raise exception 'Allowlisted Auth account missing or email unverified'
      using errcode = '42501';
  end if;

  if exists (select 1 from private.platform_founder_designations)
     or exists (select 1 from public.organizations)
     or exists (select 1 from public.organization_members)
     or exists (
       select 1 from public.platform_admin_roles
       where revoked_at is null
     ) then
    raise exception 'First-founder bootstrap is closed; existing platform identity data detected'
      using errcode = '55000';
  end if;

  select count(*) into v_permission_count
  from public.permissions;

  if v_permission_count <> 41 then
    raise exception 'Permission catalogue changed: expected 41, found %',
      v_permission_count using errcode = '55000';
  end if;

  if (select count(*) from public.permissions where permission_key in (
      'dashboard.read','branch.read','branch.manage','audit.read','role.manage','module.manage'
    )) <> 6 then
    raise exception 'Required permission catalogue is incomplete'
      using errcode = '55000';
  end if;

  select count(*) into v_total_core_module_count
  from public.platform_modules
  where is_core = true;

  if v_total_core_module_count <> 6 then
    raise exception 'Core module catalogue changed: expected 6, found %',
      v_total_core_module_count using errcode = '55000';
  end if;

  insert into public.organizations
    (organization_key, name, legal_name, status, timezone, currency_code, created_by)
  values
    ('mr-rahaman-business-ecosystem', 'MR RAHAMAN Business Ecosystem',
     'MR RAHAMAN Business Ecosystem', 'active', 'Asia/Dhaka', 'BDT', v_user_id)
  returning id into v_org_id;

  insert into public.app_roles
    (organization_id, role_key, role_name, description, is_system, is_active)
  values
    (v_org_id, 'owner', 'Owner',
     'Initial organization Owner created by the one-time Founder bootstrap.',
     true, true)
  returning id into v_role_id;

  insert into public.role_permissions (organization_id, role_id, permission_id)
  select v_org_id, v_role_id, p.id
  from public.permissions p;

  get diagnostics v_permission_count = row_count;
  if v_permission_count <> 41 then
    raise exception 'Owner permission assignment incomplete: %',
      v_permission_count using errcode = '55000';
  end if;

  insert into public.organization_members
    (organization_id, user_id, role_id, member_status, invited_by, joined_at)
  values
    (v_org_id, v_user_id, v_role_id, 'active', null, pg_catalog.clock_timestamp());

  insert into public.organization_modules
    (organization_id, module_id, status, installed_version, configuration, enabled_at, enabled_by)
  select
    v_org_id, pm.id, 'active', pm.current_version, '{}'::jsonb,
    pg_catalog.clock_timestamp(), v_user_id
  from public.platform_modules pm
  where pm.is_core = true
    and pm.module_key in (
      'organization_management',
      'identity_access',
      'branch_management',
      'module_registry',
      'approval_governance',
      'audit_security'
    );

  get diagnostics v_core_module_count = row_count;
  if v_core_module_count <> 6 then
    raise exception 'Core module set incomplete: enabled % of 6',
      v_core_module_count using errcode = '55000';
  end if;

  insert into public.platform_admin_roles
    (user_id, role_key, granted_by, expires_at, revoked_at)
  values
    (v_user_id, 'platform_owner', null, null, null)
  returning id into v_platform_role_id;

  insert into private.platform_founder_designations
    (project_key, user_id, designation_key, administrative_title, designated_by, bootstrap_version)
  values
    ('mr-rahaman-business-ecosystem', v_user_id, 'project_founder',
     'Main Admin', null, 1)
  returning id into v_founder_id;

  insert into public.platform_audit_logs
    (actor_user_id, target_user_id, action, role_key, reason, old_values, new_values)
  values
    (v_user_id, v_user_id, 'platform_owner.granted', 'platform_owner',
     'Initial Project Founder and Main Admin designation through the allowlisted one-time bootstrap.',
     null,
     pg_catalog.jsonb_build_object(
       'platform_admin_role_id', v_platform_role_id,
       'founder_designation_id', v_founder_id,
       'project_key', 'mr-rahaman-business-ecosystem',
       'designation', 'Project Founder',
       'administrative_title', 'Main Admin',
       'bootstrap_version', 1,
       'actor_type', 'one_time_server_bootstrap'
     ));

  insert into public.module_audit_logs
    (organization_id, actor_user_id, action, resource_type, resource_id, old_values, new_values)
  values
    (v_org_id, v_user_id, 'INITIAL_PROJECT_FOUNDER_MAIN_ADMIN_BOOTSTRAP_COMPLETED',
     'project_founder_platform_owner_organization_owner', v_founder_id, null,
     pg_catalog.jsonb_build_object(
       'organization_id', v_org_id,
       'owner_user_id', v_user_id,
       'platform_role', 'platform_owner',
       'organization_role', 'owner',
       'founder_designation', 'Project Founder',
       'administrative_title', 'Main Admin',
       'permission_count', v_permission_count,
       'core_module_count', v_core_module_count,
       'bootstrap_version', 1
     ));

  return pg_catalog.jsonb_build_object(
    'success', true,
    'is_project_founder', true,
    'administrative_title', 'Main Admin',
    'platform_role', 'platform_owner',
    'organization_id', v_org_id,
    'organization_role_id', v_role_id,
    'permissions_granted', v_permission_count,
    'core_modules_enabled', v_core_module_count,
    'founder_designation_id', v_founder_id,
    'branch_created', false
  );
end;
$function$;

revoke all on function public.bootstrap_first_project_founder_main_admin_v1(uuid)
  from public, anon, authenticated;
grant execute on function public.bootstrap_first_project_founder_main_admin_v1(uuid)
  to service_role;

commit;

-- Pre-deployment checks (isolated staging only):
-- 1. Apply platform_owner_management_v1.sql and customer_access_v1.sql first.
-- 2. Configure OWNER_BOOTSTRAP_ALLOWED_USER_ID to the independently verified Auth UUID.
-- 3. Configure exact allowed web origin(s) in the Edge Function environment.
-- 4. Keep SUPABASE_SERVICE_ROLE_KEY server-side only.
-- 5. Run the matching Edge Function with verify_jwt=true.
-- 6. Test allowlisted verified identity, wrong identity, unverified identity,
--    authenticated direct RPC denial, duplicate/replay, concurrent calls, and rollback.
-- 7. Confirm one Founder designation, one active platform_owner, one active organization
--    Owner membership, exactly 41 permission rows, exactly six core modules, and both
--    platform/module audit events.
-- 8. Confirm current_access_context_v1 returns is_project_founder=true,
--    platform_title='Project Founder · Main Admin', and is_platform_owner=true.
--
-- Rollback before first execution only:
-- revoke all on function public.bootstrap_first_project_founder_main_admin_v1(uuid)
--   from public, anon, authenticated, service_role;
-- drop function if exists public.bootstrap_first_project_founder_main_admin_v1(uuid);
-- Do not drop the Founder table after a successful bootstrap; it is the durable
-- historical designation. Any correction must be a separately reviewed, audited
-- exceptional operation and must never be an ordinary Owner/Admin UI action.
