-- Disposable local Supabase integration test only. Never run against Production.
\set ON_ERROR_STOP on

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
) values (
  '00000000-0000-4000-8000-000000000225',
  'authenticated', 'authenticated', 'founder-fixture@example.test',
  '', pg_catalog.now(), '{"provider":"email","providers":["email"]}'::jsonb,
  '{"full_name":"CI Founder Fixture"}'::jsonb
);

create or replace function public.test_reject_founder_audit_insert()
returns trigger language plpgsql as $$
begin
  raise exception 'intentional CI audit failure' using errcode = 'P0001';
end;
$$;

-- Negative: platform audit failure must roll back all bootstrap writes.
create trigger ci_fail_platform_audit
before insert on public.platform_audit_logs
for each row execute function public.test_reject_founder_audit_insert();

select pg_catalog.set_config('request.jwt.claim.role','service_role',false);
do $$
begin
  perform public.bootstrap_first_project_founder_main_admin_v1(
    '00000000-0000-4000-8000-000000000225'
  );
  raise exception 'Expected platform audit failure';
exception when sqlstate 'P0001' then
  if sqlerrm <> 'intentional CI audit failure' then raise; end if;
end;
$$;
drop trigger ci_fail_platform_audit on public.platform_audit_logs;

do $$
begin
  if exists (select 1 from private.platform_founder_designations)
     or exists (select 1 from public.organizations)
     or exists (select 1 from public.organization_members)
     or exists (select 1 from public.platform_admin_roles where role_key='platform_owner') then
    raise exception 'Platform audit failure left partial bootstrap data';
  end if;
end;
$$;

-- Negative: module audit failure must also roll back all bootstrap writes.
create trigger ci_fail_module_audit
before insert on public.module_audit_logs
for each row execute function public.test_reject_founder_audit_insert();

do $$
begin
  perform public.bootstrap_first_project_founder_main_admin_v1(
    '00000000-0000-4000-8000-000000000225'
  );
  raise exception 'Expected module audit failure';
exception when sqlstate 'P0001' then
  if sqlerrm <> 'intentional CI audit failure' then raise; end if;
end;
$$;
drop trigger ci_fail_module_audit on public.module_audit_logs;
drop function public.test_reject_founder_audit_insert();

do $$
begin
  if exists (select 1 from private.platform_founder_designations)
     or exists (select 1 from public.organizations)
     or exists (select 1 from public.organization_members)
     or exists (select 1 from public.platform_admin_roles where role_key='platform_owner') then
    raise exception 'Module audit failure left partial bootstrap data';
  end if;
end;
$$;

-- Positive: allowlisted, verified test identity bootstraps atomically.
select public.bootstrap_first_project_founder_main_admin_v1(
  '00000000-0000-4000-8000-000000000225'
);

select pg_catalog.set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000225',false);
select pg_catalog.set_config('request.jwt.claim.role','authenticated',false);
set role authenticated;
do $$
declare
  v_context jsonb;
begin
  if (select count(*) from private.platform_founder_designations
      where user_id='00000000-0000-4000-8000-000000000225') <> 1 then
    raise exception 'Expected exactly one Founder designation';
  end if;
  if (select count(*) from public.platform_admin_roles
      where user_id='00000000-0000-4000-8000-000000000225'
        and role_key='platform_owner' and revoked_at is null) <> 1 then
    raise exception 'Expected exactly one active Platform Owner';
  end if;
  if (select count(*) from public.organization_members
      where user_id='00000000-0000-4000-8000-000000000225'
        and member_status='active') <> 1 then
    raise exception 'Expected exactly one active organization membership';
  end if;
  if (select count(*) from public.role_permissions rp
      join public.app_roles r on r.id=rp.role_id
      where r.role_key='owner') <> 41 then
    raise exception 'Expected exactly 41 Owner permissions';
  end if;
  if (select count(*) from public.organization_modules om
      join public.platform_modules pm on pm.id=om.module_id
      where om.status='active' and pm.is_core=true) <> 6 then
    raise exception 'Expected exactly six active core modules';
  end if;
  if (select count(*) from public.platform_audit_logs
      where action='platform_owner.granted') <> 1 then
    raise exception 'Expected platform owner grant audit event';
  end if;
  if (select count(*) from public.module_audit_logs
      where action='INITIAL_PROJECT_FOUNDER_MAIN_ADMIN_BOOTSTRAP_COMPLETED') <> 1 then
    raise exception 'Expected module bootstrap audit event';
  end if;
  v_context := public.current_access_context_v1();
  if v_context->>'is_project_founder' <> 'true'
     or v_context->>'is_platform_owner' <> 'true'
     or v_context->>'platform_title' <> 'Project Founder · Main Admin' then
    raise exception 'Founder access context is incorrect: %', v_context;
  end if;
end;
$$;
reset role;
select pg_catalog.set_config('request.jwt.claim.role','service_role',false);

-- Negative: replay must be rejected and create no duplicate records.
do $$
begin
  perform public.bootstrap_first_project_founder_main_admin_v1(
    '00000000-0000-4000-8000-000000000225'
  );
  raise exception 'Expected bootstrap replay rejection';
exception when sqlstate '55000' then
  if sqlerrm not like 'First-founder bootstrap is closed%' then raise; end if;
end;
$$;

-- Negative: authenticated users cannot call the service-role-only bootstrap RPC.
set role authenticated;
do $$
begin
  perform public.bootstrap_first_project_founder_main_admin_v1(
    '00000000-0000-4000-8000-000000000225'
  );
  raise exception 'Expected direct RPC permission denial';
exception when insufficient_privilege then
  null;
end;
$$;
reset role;

-- Negative: the sole active Platform Owner cannot revoke their own final grant.
select pg_catalog.set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000225',false);
select pg_catalog.set_config('request.jwt.claim.role','authenticated',false);
set role authenticated;
do $$
begin
  perform public.platform_owner_revoke_v1(
    '00000000-0000-4000-8000-000000000225','CI last owner guard'
  );
  raise exception 'Expected last active Owner protection';
exception when sqlstate '55000' then
  if sqlerrm not like 'Cannot revoke the last active Platform Owner%' then raise; end if;
end;
$$;

do $$
begin
  if (select count(*) from public.platform_admin_roles
      where role_key='platform_owner' and revoked_at is null) <> 1 then
    raise exception 'Last active Owner was unexpectedly revoked';
  end if;
end;
$$;

reset role;
