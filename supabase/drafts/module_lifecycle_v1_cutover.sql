-- MR RAHAMAN Business Ecosystem
-- MODULE LIFECYCLE V1 CUTOVER — DRAFT ONLY; execute only after all clients use V1 RPCs.
-- This file is intentionally separate to avoid breaking the current Branch Preview
-- before its UI has been migrated and tested in staging.

begin;

revoke all on function public.branch_module_set_enabled(uuid, boolean, text)
  from public, anon, authenticated, service_role;
revoke all on function private.branch_module_set_enabled(uuid, boolean, text)
  from public, anon, authenticated, service_role;

-- Assert the legacy bypass is no longer callable by client/server API roles.
do $assert$
begin
  if pg_catalog.has_function_privilege('authenticated',
       'public.branch_module_set_enabled(uuid,boolean,text)', 'EXECUTE')
     or pg_catalog.has_function_privilege('authenticated',
       'private.branch_module_set_enabled(uuid,boolean,text)', 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role',
       'public.branch_module_set_enabled(uuid,boolean,text)', 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role',
       'private.branch_module_set_enabled(uuid,boolean,text)', 'EXECUTE') then
    raise exception 'Legacy module lifecycle bypass still executable';
  end if;
end;
$assert$;

commit;
