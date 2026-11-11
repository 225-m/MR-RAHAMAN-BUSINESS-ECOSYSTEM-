-- MR RAHAMAN Business Ecosystem
-- Draft only: database-backed identity/authorization context for the web preview.
-- Do NOT apply to Production until tested in an isolated staging project.

create or replace function public.current_access_context_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_user_id uuid := auth.uid();
  v_is_platform_owner boolean := false;
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
      and (par.expires_at is null or par.expires_at > now())
  ) into v_is_platform_owner;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
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
        select jsonb_agg(p.permission_key order by p.permission_key)
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

  return jsonb_build_object(
    'user_id', v_user_id,
    'is_platform_owner', v_is_platform_owner,
    'organizations', v_organizations
  );
end;
$function$;

revoke all on function public.current_access_context_v1() from public, anon;
grant execute on function public.current_access_context_v1() to authenticated;

-- Staging checks:
-- 1. anon and unauthenticated calls fail.
-- 2. authenticated user receives only their own active platform role/memberships.
-- 3. revoked/expired platform_owner is false.
-- 4. suspended membership, inactive organization, or inactive role is omitted.
-- 5. permissions are derived from role_permissions; no user_metadata is trusted.
-- 6. role changes are reflected on next RPC call / token-independent DB read.
-- 7. no service_role key is present in browser code.
--
-- Rollback before deployment:
-- revoke all on function public.current_access_context_v1() from public, anon, authenticated;
-- drop function if exists public.current_access_context_v1();
