-- MR RAHAMAN Business Ecosystem
-- FOUNDER BOOTSTRAP V1 PRE-EXECUTION ROLLBACK — DRAFT ONLY.
-- Run only in disposable/staging environment before any successful bootstrap.
-- Never use this rollback after the Founder designation or live business data exists.

begin;

do $guard$
begin
  if pg_catalog.to_regclass('private.platform_founder_designations') is not null
     and exists (select 1 from private.platform_founder_designations) then
    raise exception 'Rollback refused: a Founder designation already exists; preserve historical identity and audit trail';
  end if;

  if exists (
    select 1 from public.platform_admin_roles
    where role_key = 'platform_owner'
      and revoked_at is null
      and (expires_at is null or expires_at > pg_catalog.statement_timestamp())
  ) then
    raise exception 'Rollback refused: an active Platform Owner exists';
  end if;

  if exists (
    select 1 from public.organizations
    where organization_key = 'mr-rahaman-business-ecosystem'
  ) then
    raise exception 'Rollback refused: the project organization exists; do not remove live organization data';
  end if;
end;
$guard$;

-- Restore the customer-aware base context before removing the Founder table.
create or replace function private.current_access_context_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_is_platform_owner boolean := false;
  v_is_customer boolean := false;
  v_customer_profile jsonb := null;
  v_organizations jsonb := '[]'::jsonb;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select exists (
    select 1
    from public.platform_admin_roles par
    where par.user_id = v_user_id
      and par.role_key = 'platform_owner'
      and par.revoked_at is null
      and (par.expires_at is null or par.expires_at > pg_catalog.statement_timestamp())
  ) into v_is_platform_owner;

  select exists (
    select 1 from public.customer_profiles cp where cp.user_id = v_user_id
  ) into v_is_customer;

  select pg_catalog.jsonb_build_object(
    'display_name', cp.display_name,
    'avatar_path', cp.avatar_path,
    'created_at', cp.created_at
  )
  into v_customer_profile
  from public.customer_profiles cp
  where cp.user_id = v_user_id;

  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'organization_id', membership.organization_id,
        'organization_name', membership.organization_name,
        'role_key', membership.role_key,
        'permissions', membership.permissions
      )
      order by membership.organization_name
    ),
    '[]'::jsonb
  )
  into v_organizations
  from (
    select
      m.organization_id,
      o.name as organization_name,
      r.role_key,
      coalesce((
        select pg_catalog.jsonb_agg(p.permission_key order by p.permission_key)
        from public.role_permissions rp
        join public.permissions p on p.id = rp.permission_id
        where rp.organization_id = m.organization_id
          and rp.role_id = r.id
      ), '[]'::jsonb) as permissions
    from public.organization_members m
    join public.organizations o
      on o.id = m.organization_id and o.status = 'active'
    join public.app_roles r
      on r.id = m.role_id
     and r.organization_id = m.organization_id
     and r.is_active = true
    where m.user_id = v_user_id
      and m.member_status = 'active'
  ) membership;

  return pg_catalog.jsonb_build_object(
    'user_id', v_user_id,
    'is_customer', v_is_customer,
    'customer_profile', v_customer_profile,
    'is_platform_owner', v_is_platform_owner,
    'organizations', v_organizations
  );
end;
$function$;

grant usage on schema private to authenticated;
revoke all on function private.current_access_context_v1()
  from public, anon, authenticated;
grant execute on function private.current_access_context_v1()
  to authenticated;

create or replace function public.current_access_context_v1()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
  select private.current_access_context_v1();
$function$;

revoke all on function public.current_access_context_v1()
  from public, anon, authenticated, service_role;
grant execute on function public.current_access_context_v1()
  to authenticated;

revoke all on function public.bootstrap_first_project_founder_main_admin_v1(uuid)
  from public, anon, authenticated, service_role;
drop function if exists public.bootstrap_first_project_founder_main_admin_v1(uuid);

drop table if exists private.platform_founder_designations;
drop function if exists private.reject_founder_designation_mutation_v1();

commit;

-- Manual follow-up:
-- 1. Disable/remove the owner-bootstrap Edge Function in the same environment.
-- 2. Remove OWNER_BOOTSTRAP_ALLOWED_USER_ID and other one-time bootstrap secrets.
-- 3. Re-run the customer-only access-context test suite.
-- 4. Do not drop platform_audit_logs or platform_owner management functions here;
--    those are separate platform security infrastructure.
-- 5. If a Founder bootstrap ever succeeded, this script must refuse to run.
