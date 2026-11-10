-- MR RAHAMAN Business Ecosystem — First Platform Owner + Organization Owner Bootstrap v2
-- DRAFT ONLY. Do not apply to Production.
-- Target: pojhrvmuamdejlutxpng. One-time allowlisted, verified Auth account.
-- The allowlisted subject is configured only in the Edge Function environment, not in source.
-- This draft replaces v1 conceptually; v1 remains unsafe and must not be used.

create or replace function public.bootstrap_first_platform_owner_v2(
  p_expected_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_user_id uuid := p_expected_user_id;
  v_org_id uuid;
  v_role_id uuid;
  v_platform_role_id uuid;
  v_permission_count integer;
  v_core_module_count integer;
  v_email_confirmed boolean;
begin
  if p_expected_user_id is null then
    raise exception 'An allowlisted expected user ID is required' using errcode = '22023';
  end if;

  if pg_catalog.to_regclass('public.platform_audit_logs') is null then
    raise exception 'platform_audit_logs must be installed before first-owner bootstrap'
      using errcode = '55000';
  end if;

  if coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise exception 'service_role required' using errcode = '42501';
  end if;

  if p_expected_user_id is distinct from v_user_id then
    raise exception 'Unexpected bootstrap subject' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtext('mr-rahaman:first-platform-owner-bootstrap:v2'));

  select (u.email_confirmed_at is not null)
    into v_email_confirmed
  from auth.users u
  where u.id = v_user_id;

  if coalesce(v_email_confirmed, false) is not true then
    raise exception 'Allowlisted Auth account missing or email unverified'
      using errcode = '42501';
  end if;

  if exists (select 1 from public.organizations)
     or exists (select 1 from public.organization_members)
     or exists (
       select 1 from public.platform_admin_roles
       where role_key = 'platform_owner'
         and revoked_at is null
     ) then
    raise exception 'First-owner bootstrap is closed; existing platform data detected'
      using errcode = '55000';
  end if;

  select count(*) into v_permission_count
  from public.permissions;

  if v_permission_count <> 41 then
    raise exception 'Permission catalogue changed: expected 41, found %',
      v_permission_count using errcode = '55000';
  end if;

  if not exists (select 1 from public.permissions where permission_key = 'dashboard.read')
     or not exists (select 1 from public.permissions where permission_key = 'branch.read')
     or not exists (select 1 from public.permissions where permission_key = 'branch.manage')
     or not exists (select 1 from public.permissions where permission_key = 'audit.read')
     or not exists (select 1 from public.permissions where permission_key = 'role.manage')
     or not exists (select 1 from public.permissions where permission_key = 'module.manage') then
    raise exception 'Required permissions are missing' using errcode = '55000';
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
     'Initial organization Owner created by the one-time Platform Owner bootstrap.',
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
    (v_org_id, v_user_id, v_role_id, 'active', v_user_id, now());

  insert into public.organization_modules
    (organization_id, module_id, status, installed_version, configuration, enabled_at, enabled_by)
  select
    v_org_id, pm.id, 'active', pm.current_version, '{}'::jsonb, now(), v_user_id
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
    (v_user_id, 'platform_owner', v_user_id, null, null)
  returning id into v_platform_role_id;

  insert into public.platform_audit_logs
    (actor_user_id, target_user_id, action, role_key, reason, old_values, new_values)
  values
    (v_user_id, v_user_id, 'platform_owner.granted', 'platform_owner',
     'Initial Platform Owner created by the verified one-time bootstrap.',
     null, jsonb_build_object('platform_admin_role_id', v_platform_role_id, 'bootstrap_version', 2));

  insert into public.module_audit_logs
    (organization_id, actor_user_id, action, resource_type, resource_id, old_values, new_values)
  values
    (v_org_id, v_user_id, 'INITIAL_PLATFORM_OWNER_BOOTSTRAP_COMPLETED',
     'platform_owner_and_organization_owner', v_role_id, null,
     jsonb_build_object(
       'organization_id', v_org_id,
       'owner_user_id', v_user_id,
       'platform_role', 'platform_owner',
       'organization_role', 'owner',
       'permission_count', v_permission_count,
       'core_module_count', v_core_module_count,
       'bootstrap_version', 2
     ));

  return jsonb_build_object(
    'success', true,
    'organization_id', v_org_id,
    'organization_role_id', v_role_id,
    'platform_role', 'platform_owner',
    'permissions_granted', v_permission_count,
    'core_modules_enabled', v_core_module_count,
    'branch_created', false
  );
end;
$function$;

revoke all on function public.bootstrap_first_platform_owner_v2(uuid)
  from public, anon, authenticated;
grant execute on function public.bootstrap_first_platform_owner_v2(uuid)
  to service_role;

-- Pre-deployment staging tests required:
-- A. service_role only; anon/authenticated direct RPC denied.
-- B. allowlisted Auth user must exist and email_confirmed_at must be set.
-- C. second/concurrent invocation must fail without duplicate records.
-- D. wrong UUID, unverified user, pre-existing org/member/active owner all fail atomically.
-- E. exactly 41 permissions and exactly six is_core modules must exist.
-- F. platform_admin_roles row has platform_owner, expires_at NULL, revoked_at NULL.
-- G. organization Owner gets all 41 current permissions; six actual core modules enabled.
-- H. module and platform audit rows written in the same transaction; no branch/sample data created.
-- I. confirm RPC current_access_context_v1 reports platform_owner and organization access.
--
-- Rollback before first execution:
-- revoke all on function public.bootstrap_first_platform_owner_v2(uuid)
--   from public, anon, authenticated, service_role;
-- drop function if exists public.bootstrap_first_platform_owner_v2(uuid);
-- After successful execution, never delete role/org/audit rows blindly; use a reviewed
-- compensating transaction preserving audit history and a valid Owner.
