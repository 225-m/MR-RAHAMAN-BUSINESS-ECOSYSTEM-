-- MR RAHAMAN Business Ecosystem
-- MODULE LIFECYCLE V1 FAIL-CLOSED ROLLBACK — DRAFT ONLY.
-- Emergency rollback for a defective V1 client/RPC after legacy cutover.
-- This stops new module writes without reopening the legacy approval bypass.

begin;

revoke all on function public.module_request_change_v1(uuid,text,text,text)
  from public, anon, authenticated, service_role;
revoke all on function public.module_approval_decide_v1(uuid,uuid,text,text)
  from public, anon, authenticated, service_role;
revoke all on function public.module_apply_approved_change_v1(uuid,uuid)
  from public, anon, authenticated, service_role;

do $assert$
begin
  if pg_catalog.has_function_privilege('anon','public.module_request_change_v1(uuid,text,text,text)','EXECUTE')
     or pg_catalog.has_function_privilege('authenticated','public.module_request_change_v1(uuid,text,text,text)','EXECUTE')
     or pg_catalog.has_function_privilege('service_role','public.module_request_change_v1(uuid,text,text,text)','EXECUTE')
     or pg_catalog.has_function_privilege('anon','public.module_approval_decide_v1(uuid,uuid,text,text)','EXECUTE')
     or pg_catalog.has_function_privilege('authenticated','public.module_approval_decide_v1(uuid,uuid,text,text)','EXECUTE')
     or pg_catalog.has_function_privilege('service_role','public.module_approval_decide_v1(uuid,uuid,text,text)','EXECUTE')
     or pg_catalog.has_function_privilege('anon','public.module_apply_approved_change_v1(uuid,uuid)','EXECUTE')
     or pg_catalog.has_function_privilege('authenticated','public.module_apply_approved_change_v1(uuid,uuid)','EXECUTE')
     or pg_catalog.has_function_privilege('service_role','public.module_apply_approved_change_v1(uuid,uuid)','EXECUTE') then
    raise exception 'V1 write RPC remains executable after fail-closed rollback';
  end if;

  if pg_catalog.has_function_privilege('anon','public.branch_module_set_enabled(uuid,boolean,text)','EXECUTE')
     or pg_catalog.has_function_privilege('authenticated','public.branch_module_set_enabled(uuid,boolean,text)','EXECUTE')
     or pg_catalog.has_function_privilege('service_role','public.branch_module_set_enabled(uuid,boolean,text)','EXECUTE')
     or pg_catalog.has_function_privilege('anon','private.branch_module_set_enabled(uuid,boolean,text)','EXECUTE')
     or pg_catalog.has_function_privilege('authenticated','private.branch_module_set_enabled(uuid,boolean,text)','EXECUTE')
     or pg_catalog.has_function_privilege('service_role','private.branch_module_set_enabled(uuid,boolean,text)','EXECUTE') then
    raise exception 'Legacy module lifecycle bypass was re-enabled; rollback must remain fail-closed';
  end if;
end;
$assert$;

commit;

-- Do not re-enable the old branch_module_set_enabled RPCs.
-- To resume module lifecycle, deploy a corrected V1 client and re-grant only the
-- three V1 public RPCs after re-running the isolated authorization suite.
