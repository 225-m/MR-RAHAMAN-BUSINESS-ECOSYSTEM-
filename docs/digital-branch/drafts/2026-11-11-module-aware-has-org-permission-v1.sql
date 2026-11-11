-- DRAFT ONLY — NOT APPLIED.
-- Candidate authorization hardening for the module-disabled permission gap.
-- This changes a shared authorization helper used by RLS/RPC checks.
-- Review every caller and test in an isolated project before any migration.

begin;

create or replace function private.has_org_permission(
  p_organization_id uuid,
  p_permission_key text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.organization_members m
    join public.organizations o
      on o.id = m.organization_id
    join public.app_roles r
      on r.id = m.role_id
     and r.organization_id = m.organization_id
     and r.is_active = true
    join public.role_permissions rp
      on rp.role_id = r.id
     and rp.organization_id = r.organization_id
    join public.permissions p
      on p.id = rp.permission_id
     and p.permission_key = p_permission_key
    -- Fail closed: a permission is usable only when its mapped module
    -- exists, is active in the platform registry, and is active for this org.
    -- A NULL/unmapped module_key intentionally grants no authorization.
    join public.platform_modules pm
      on pm.module_key = p.module_key
     and pm.is_active = true
    join public.organization_modules om
      on om.module_id = pm.id
     and om.organization_id = m.organization_id
     and om.status = 'active'
    where m.organization_id = p_organization_id
      and m.user_id = (select auth.uid())
      and m.member_status = 'active'
      and o.status = 'active'
  );
$function$;

-- CREATE OR REPLACE preserves the existing function owner and ACL.
-- Verify both explicitly in the isolated environment before accepting this patch.

commit;
