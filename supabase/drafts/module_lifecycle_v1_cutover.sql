-- MR RAHAMAN Business Ecosystem
-- MODULE LIFECYCLE V1 CUTOVER — DRAFT ONLY; execute only after all clients use V1 RPCs.
-- This transaction revokes the old approval-bypass RPCs only after asserting that
-- the access-context function and all three V1 public wrappers are present and gated.
-- Do not apply to Production until the release checklist and client coverage pass.

begin;

-- Fail before changing grants if the new client authorization surface is not ready.
do $preflight$
begin
  if pg_catalog.to_regprocedure('public.current_access_context_v1()') is null then
    raise exception 'current_access_context_v1 is missing; cutover is not safe';
  end if;

  if pg_catalog.to_regprocedure('public.module_request_change_v1(uuid,text,text,text)') is null
     or pg_catalog.to_regprocedure('public.module_approval_decide_v1(uuid,uuid,text,text)') is null
     or pg_catalog.to_regprocedure('public.module_apply_approved_change_v1(uuid,uuid)') is null then
    raise exception 'One or more Module Lifecycle V1 public RPCs are missing';
  end if;

  if not pg_catalog.has_function_privilege('authenticated','public.current_access_context_v1()','EXECUTE')
     or pg_catalog.has_function_privilege('anon','public.current_access_context_v1()','EXECUTE')
     or pg_catalog.has_function_privilege('service_role','public.current_access_context_v1()','EXECUTE') then
    raise exception 'current_access_context_v1 execute grants are not least-privilege';
  end if;

  if not pg_catalog.has_function_privilege('authenticated','public.module_request_change_v1(uuid,text,text,text)','EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated','public.module_approval_decide_v1(uuid,uuid,text,text)','EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated','public.module_apply_approved_change_v1(uuid,uuid)','EXECUTE')
     or pg_catalog.has_function_privilege('anon','public.module_request_change_v1(uuid,text,text,text)','EXECUTE')
     or pg_catalog.has_function_privilege('anon','public.module_approval_decide_v1(uuid,uuid,text,text)','EXECUTE')
     or pg_catalog.has_function_privilege('anon','public.module_apply_approved_change_v1(uuid,uuid)','EXECUTE')
     or pg_catalog.has_function_privilege('service_role','public.module_request_change_v1(uuid,text,text,text)','EXECUTE')
     or pg_catalog.has_function_privilege('service_role','public.module_approval_decide_v1(uuid,uuid,text,text)','EXECUTE')
     or pg_catalog.has_function_privilege('service_role','public.module_apply_approved_change_v1(uuid,uuid)','EXECUTE') then
    raise exception 'Module Lifecycle V1 public RPC execute grants are not least-privilege';
  end if;

  if pg_catalog.has_function_privilege('authenticated','private.module_request_change_v1(uuid,text,text,text)','EXECUTE')
     or pg_catalog.has_function_privilege('authenticated','private.module_approval_decide_v1(uuid,uuid,text,text)','EXECUTE')
     or pg_catalog.has_function_privilege('authenticated','private.module_apply_approved_change_v1(uuid,uuid)','EXECUTE') then
    raise exception 'Authenticated can execute private Module Lifecycle implementations';
  end if;

  if pg_catalog.to_regclass('public.platform_audit_logs') is null
     or pg_catalog.to_regprocedure('public.platform_owner_grant_v1(uuid,text)') is null
     or pg_catalog.to_regprocedure('public.platform_owner_revoke_v1(uuid,text)') is null
     or pg_catalog.to_regprocedure('public.platform_owner_audit_list_v1(integer)') is null then
    raise exception 'Audited Platform Owner management surface is missing';
  end if;

  if not pg_catalog.has_function_privilege('authenticated','public.platform_owner_grant_v1(uuid,text)','EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated','public.platform_owner_revoke_v1(uuid,text)','EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated','public.platform_owner_audit_list_v1(integer)','EXECUTE')
     or pg_catalog.has_function_privilege('anon','public.platform_owner_grant_v1(uuid,text)','EXECUTE')
     or pg_catalog.has_function_privilege('anon','public.platform_owner_revoke_v1(uuid,text)','EXECUTE')
     or pg_catalog.has_function_privilege('anon','public.platform_owner_audit_list_v1(integer)','EXECUTE')
     or pg_catalog.has_function_privilege('service_role','public.platform_owner_grant_v1(uuid,text)','EXECUTE')
     or pg_catalog.has_function_privilege('service_role','public.platform_owner_revoke_v1(uuid,text)','EXECUTE')
     or pg_catalog.has_function_privilege('service_role','public.platform_owner_audit_list_v1(integer)','EXECUTE') then
    raise exception 'Platform Owner management RPC grants are not least-privilege';
  end if;

  if pg_catalog.has_table_privilege('authenticated','public.platform_admin_roles','SELECT')
     or pg_catalog.has_table_privilege('authenticated','public.platform_admin_roles','INSERT')
     or pg_catalog.has_table_privilege('authenticated','public.platform_admin_roles','UPDATE')
     or pg_catalog.has_table_privilege('authenticated','public.platform_admin_roles','DELETE')
     or pg_catalog.has_table_privilege('service_role','public.platform_admin_roles','INSERT')
     or pg_catalog.has_table_privilege('service_role','public.platform_admin_roles','UPDATE')
     or pg_catalog.has_table_privilege('service_role','public.platform_admin_roles','DELETE')
     or pg_catalog.has_table_privilege('authenticated','public.platform_audit_logs','SELECT')
     or pg_catalog.has_table_privilege('authenticated','public.platform_audit_logs','INSERT')
     or pg_catalog.has_table_privilege('authenticated','public.platform_audit_logs','UPDATE')
     or pg_catalog.has_table_privilege('authenticated','public.platform_audit_logs','DELETE')
     or pg_catalog.has_table_privilege('service_role','public.platform_audit_logs','SELECT')
     or pg_catalog.has_table_privilege('service_role','public.platform_audit_logs','INSERT')
     or pg_catalog.has_table_privilege('service_role','public.platform_audit_logs','UPDATE')
     or pg_catalog.has_table_privilege('service_role','public.platform_audit_logs','DELETE') then
    raise exception 'Direct Platform Owner assignment/audit table access is granted';
  end if;

  if (select count(*) from pg_catalog.pg_trigger t
      where t.tgrelid in (
        'public.platform_admin_roles'::regclass,
        'public.app_roles'::regclass,
        'public.organization_members'::regclass,
        'public.role_permissions'::regclass
      )
      and t.tgname in (
        'platform_admin_roles_last_owner_guard',
        'app_roles_last_owner_guard',
        'organization_members_last_owner_guard',
        'organization_members_owner_permission_floor',
        'role_permissions_owner_floor_guard'
      )
      and t.tgenabled in ('O','A')
      and not t.tgisinternal) <> 5 then
    raise exception 'Last Active Owner and Owner permission-floor triggers are incomplete or disabled';
  end if;

  if not (select c.relrowsecurity from pg_catalog.pg_class c
          where c.oid = 'public.platform_audit_logs'::regclass)
     or not (select c.relrowsecurity from pg_catalog.pg_class c
             where c.oid = 'public.platform_admin_roles'::regclass) then
    raise exception 'Platform Owner assignment/audit table RLS is not enabled';
  end if;
end;
$preflight$;

-- Remove the old direct enable/disable path after V1 preflight passes.
revoke all on function public.branch_module_set_enabled(uuid, boolean, text)
  from public, anon, authenticated, service_role;
revoke all on function private.branch_module_set_enabled(uuid, boolean, text)
  from public, anon, authenticated, service_role;

-- Assert both the new API and the removal of every legacy API entry point.
do $assert$
begin
  if pg_catalog.has_table_privilege('authenticated','public.organization_modules','INSERT')
     or pg_catalog.has_table_privilege('authenticated','public.organization_modules','UPDATE')
     or pg_catalog.has_table_privilege('authenticated','public.organization_modules','DELETE')
     or pg_catalog.has_table_privilege('authenticated','public.module_change_requests','INSERT')
     or pg_catalog.has_table_privilege('authenticated','public.module_change_requests','UPDATE')
     or pg_catalog.has_table_privilege('authenticated','public.module_change_requests','DELETE')
     or pg_catalog.has_table_privilege('authenticated','public.approval_requests','INSERT')
     or pg_catalog.has_table_privilege('authenticated','public.approval_requests','UPDATE')
     or pg_catalog.has_table_privilege('authenticated','public.approval_requests','DELETE') then
    raise exception 'Authenticated direct lifecycle table mutation is granted';
  end if;

  if pg_catalog.has_function_privilege('anon',
       'public.branch_module_set_enabled(uuid,boolean,text)', 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated',
       'public.branch_module_set_enabled(uuid,boolean,text)', 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role',
       'public.branch_module_set_enabled(uuid,boolean,text)', 'EXECUTE')
     or pg_catalog.has_function_privilege('anon',
       'private.branch_module_set_enabled(uuid,boolean,text)', 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated',
       'private.branch_module_set_enabled(uuid,boolean,text)', 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role',
       'private.branch_module_set_enabled(uuid,boolean,text)', 'EXECUTE') then
    raise exception 'Legacy module lifecycle bypass still executable';
  end if;

  if not pg_catalog.has_function_privilege('authenticated',
       'public.module_request_change_v1(uuid,text,text,text)', 'EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated',
       'public.module_approval_decide_v1(uuid,uuid,text,text)', 'EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated',
       'public.module_apply_approved_change_v1(uuid,uuid)', 'EXECUTE') then
    raise exception 'V1 Module Lifecycle RPCs are not executable by authenticated clients';
  end if;
end;
$assert$;

commit;

-- Rollback policy:
-- Do NOT re-grant the legacy RPCs; that re-opens the approval bypass.
-- If V1 is defective after cutover, use module_lifecycle_v1_fail_closed_rollback.sql
-- to revoke the V1 write RPCs while leaving legacy writes disabled.
