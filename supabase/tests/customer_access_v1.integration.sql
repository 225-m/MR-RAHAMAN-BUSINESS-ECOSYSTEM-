-- Integration test for customer_access_v1.sql; run only in disposable PostgreSQL.
\set ON_ERROR_STOP on

-- A is backfilled by migration; B is created after migration and uses the Auth trigger.
insert into auth.users (id,email,email_confirmed_at,raw_user_meta_data)
values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','customer-b@example.test',now(),'{"full_name":"Customer B"}');

do $$
begin
  if (select count(*) from public.customer_profiles) <> 2 then
    raise exception 'Expected exactly two customer profiles after backfill + signup trigger';
  end if;
end $$;

set role anon;
do $$
begin
  begin
    perform public.current_access_context_v1();
    raise exception 'anon unexpectedly executed customer access context RPC';
  exception when insufficient_privilege then
    null;
  end;
end $$;
reset role;

set role authenticated;
set request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

do $$
declare
  v_context jsonb;
  v_count integer;
  v_rows integer;
begin
  select count(*) into v_count from public.customer_profiles;
  if v_count <> 1 then raise exception 'Customer A can see % profiles; expected 1', v_count; end if;

  update public.customer_profiles
     set display_name = 'Customer A Updated'
   where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  get diagnostics v_rows = row_count;
  if v_rows <> 1 then raise exception 'Customer A could not update own profile'; end if;

  update public.customer_profiles
     set display_name = 'Unauthorized Change'
   where user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  get diagnostics v_rows = row_count;
  if v_rows <> 0 then raise exception 'Customer A modified Customer B profile'; end if;

  v_context := public.current_access_context_v1();
  if v_context ->> 'is_customer' <> 'true' then raise exception 'Customer context flag missing'; end if;
  if v_context ->> 'is_platform_owner' <> 'false' then raise exception 'Customer incorrectly became Platform Owner'; end if;
  if jsonb_array_length(v_context -> 'organizations') <> 0 then raise exception 'Customer unexpectedly has organization membership'; end if;
end $$;

do $$
begin
  begin
    update public.customer_profiles
       set updated_at = now()
     where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    raise exception 'Customer unexpectedly changed updated_at column';
  exception when insufficient_privilege then
    null;
  end;
  begin
    insert into public.customer_profiles(user_id,display_name)
    values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','Injected');
    raise exception 'Customer unexpectedly inserted profile directly';
  exception when insufficient_privilege then
    null;
  end;
  begin
    delete from public.customer_profiles
     where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    raise exception 'Customer unexpectedly deleted profile';
  exception when insufficient_privilege then
    null;
  end;
end $$;

reset role;
select 'PASS: customer profile backfill, signup trigger, own-row RLS, restricted column grants, anon denial, and customer access context' as result;
