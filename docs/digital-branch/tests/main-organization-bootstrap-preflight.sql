-- READ-ONLY preflight. Safe to run against Production; performs SELECTs only.
do $$
declare
  v_permission_count integer;
  v_module_count integer;
begin
  select count(*) into v_permission_count from public.permissions;
  if v_permission_count <> 41 then
    raise exception 'Expected 41 permissions; found %', v_permission_count;
  end if;

  select count(*) into v_module_count from public.platform_modules;
  if v_module_count <> 16 then
    raise exception 'Expected 16 platform modules; found %', v_module_count;
  end if;

  if exists (select 1 from public.organizations) then
    raise exception 'Organization already exists: bootstrap must not run';
  end if;

  if not exists (select 1 from public.platform_modules where module_key='branch_management' and is_active)
     or not exists (select 1 from public.platform_modules where module_key='organization_management' and is_active) then
    raise exception 'Required core modules are missing or inactive';
  end if;

  if exists (
    select 1 from public.platform_modules m
    join public.module_dependencies d on d.module_id=m.id and d.is_mandatory
    join public.platform_modules dep on dep.id=d.depends_on_module_id
    where m.is_core and m.is_active and not (dep.is_core and dep.is_active)
  ) then
    raise exception 'A mandatory core-module dependency is not active';
  end if;
end $$;

select
  (select count(*) from public.permissions) as permission_count,
  (select count(*) from public.platform_modules) as module_count,
  (select count(*) from public.organizations) as organization_count,
  (select count(*) from public.organization_modules) as organization_module_rows,
  (select count(*) from public.module_audit_logs) as audit_rows;
