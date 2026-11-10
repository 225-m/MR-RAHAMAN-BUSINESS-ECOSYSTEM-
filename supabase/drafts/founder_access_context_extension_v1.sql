-- MR RAHAMAN Business Ecosystem
-- FOUNDER FIELDS FOR DATABASE-BACKED ACCESS CONTEXT — DRAFT ONLY.
-- Apply after customer_access_v1.sql and first_project_founder_main_admin_bootstrap_v1.sql.
-- Preserves the existing current_access_context_v1 response contract and adds
-- is_project_founder + platform_title. No client-supplied identity is trusted.

begin;

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
  v_is_project_founder boolean := false;
  v_is_customer boolean := false;
  v_platform_title text := null;
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
    select 1
    from private.platform_founder_designations fd
    where fd.user_id = v_user_id
      and fd.project_key = 'mr-rahaman-business-ecosystem'
  ) into v_is_project_founder;

  v_platform_title := case
    when v_is_project_founder then 'Project Founder · Main Admin'
    when v_is_platform_owner then 'Platform Owner'
    else null
  end;

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
    'is_project_founder', v_is_project_founder,
    'platform_title', v_platform_title,
    'organizations', v_organizations
  );
end;
$function$;

revoke all on function private.current_access_context_v1()
  from public, anon, authenticated;
grant usage on schema private to authenticated;
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

commit;

-- Staging assertions:
-- * Anonymous and unauthenticated calls are denied.
-- * Only auth.uid() is used to find Founder, Owner, Customer and memberships.
-- * The designated Founder receives is_project_founder=true and
--   platform_title='Project Founder · Main Admin'.
-- * A platform_owner without the Founder designation receives
--   is_platform_owner=true but is_project_founder=false.
-- * A Founder designation without a current active platform_owner does not
--   independently grant dashboard authorization.
-- * Customer-only users receive is_customer=true and no organization access.
-- * Suspended memberships, inactive organizations and inactive roles are excluded.
-- * No client can read private.platform_founder_designations directly.
