-- Rollback integration test; run only after customer_access_v1.integration.sql.
\set ON_ERROR_STOP on

select count(*) as before_rollback_profiles from public.customer_profiles;

do $$
begin
  if (select count(*) from public.customer_profiles) <> 2 then
    raise exception 'Expected two profiles before rollback';
  end if;
end $$;

select 'PASS: rollback preserved Customer rows, retained the table and RLS, removed Customer RPC/triggers, and revoked client grants' as result
where
  to_regclass('public.customer_profiles') is not null
  and to_regprocedure('public.current_access_context_v1()') is null
  and to_regprocedure('private.current_access_context_v1()') is null
  and to_regprocedure('private.create_customer_profile_for_auth_user()') is null
  and to_regprocedure('private.set_customer_profile_updated_at()') is null
  and (select relrowsecurity from pg_class where oid='public.customer_profiles'::regclass)
  and (select count(*) from public.customer_profiles) = 2
  and not has_table_privilege('anon','public.customer_profiles','select')
  and not has_table_privilege('authenticated','public.customer_profiles','select')
  and not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname like 'customer_avatars_%')
  and exists (select 1 from storage.buckets where id='customer-avatars' and public=false);

do $$
begin
  if to_regclass('public.customer_profiles') is null then
    raise exception 'Rollback dropped customer_profiles';
  end if;
  if (select count(*) from public.customer_profiles) <> 2 then
    raise exception 'Rollback deleted customer data';
  end if;
  if not (select relrowsecurity from pg_class where oid='public.customer_profiles'::regclass) then
    raise exception 'Rollback disabled RLS';
  end if;
  if has_table_privilege('anon','public.customer_profiles','select')
     or has_table_privilege('authenticated','public.customer_profiles','select') then
    raise exception 'Rollback left client table grants';
  end if;
  if exists (select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname like 'customer_avatars_%') then
    raise exception 'Rollback left Customer avatar Storage policies';
  end if;
  if not exists (select 1 from storage.buckets where id='customer-avatars' and public=false) then
    raise exception 'Rollback removed or exposed private avatar bucket';
  end if;
  if to_regprocedure('public.current_access_context_v1()') is not null
     or to_regprocedure('private.current_access_context_v1()') is not null then
    raise exception 'Rollback left Customer access RPC functions';
  end if;
end $$;

select 'PASS: rollback retained customer profiles and private avatar files while disabling Customer RPC and Storage access' as result;
