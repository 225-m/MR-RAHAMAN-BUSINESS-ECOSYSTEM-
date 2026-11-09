-- Platform Owner single-slot handover and audit V1 integration tests — disposable DB only.
\set ON_ERROR_STOP on

insert into auth.users(id,email_confirmed_at) values
 ('10000000-0000-0000-0000-000000000001',now()),
 ('10000000-0000-0000-0000-000000000002',now()),
 ('10000000-0000-0000-0000-000000000003',null);

-- Simulate the one-time service_role bootstrap creating the first Platform Owner.
insert into public.platform_admin_roles(id,user_id,role_key,granted_by)
values('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','platform_owner','10000000-0000-0000-0000-000000000001');

-- T01: current Owner atomically hands the single Owner slot to another verified user.
set role authenticated;
set request.jwt.claim.sub = '10000000-0000-0000-0000-000000000001';
select public.platform_owner_grant_v1('10000000-0000-0000-0000-000000000002','Transfer single Platform Owner slot');
reset role;
reset request.jwt.claim.sub;

-- T02: unverified Auth user cannot receive the Owner slot.
set role authenticated;
set request.jwt.claim.sub = '10000000-0000-0000-0000-000000000002';
do $test$
declare v_blocked boolean := false;
begin
  begin
    perform public.platform_owner_grant_v1('10000000-0000-0000-0000-000000000003','Unverified transfer target');
  exception when sqlstate '22023' then v_blocked := true;
  end;
  if not v_blocked then raise exception 'T02 FAILED: unverified target was granted Platform Owner'; end if;
end;
$test$;
reset role;
reset request.jwt.claim.sub;

-- T03: new Owner cannot revoke the final active Owner slot.
set role authenticated;
set request.jwt.claim.sub = '10000000-0000-0000-0000-000000000002';
do $test$
declare v_blocked boolean := false;
begin
  begin
    perform public.platform_owner_revoke_v1('10000000-0000-0000-0000-000000000002','Attempt final Owner revoke');
  exception when sqlstate '55000' then v_blocked := true;
  end;
  if not v_blocked then raise exception 'T03 FAILED: final active Owner revoke was not blocked'; end if;
end;
$test$;
reset role;
reset request.jwt.claim.sub;

-- T04: new Owner can read the paired handover audit events; former Owner cannot.
set role authenticated;
set request.jwt.claim.sub = '10000000-0000-0000-0000-000000000002';
do $test$
declare v_count integer;
begin
  select count(*) into v_count from public.platform_owner_audit_list_v1(50);
  if v_count <> 2 then raise exception 'T04 FAILED: expected paired grant/revoke events, found %', v_count; end if;
end;
$test$;
reset role;
reset request.jwt.claim.sub;

set role authenticated;
set request.jwt.claim.sub = '10000000-0000-0000-0000-000000000001';
do $test$
declare v_blocked boolean := false;
begin
  begin
    perform public.platform_owner_audit_list_v1(50);
  exception when sqlstate '42501' then v_blocked := true;
  end;
  if not v_blocked then raise exception 'T04 FAILED: former Owner can read platform audit logs'; end if;
end;
$test$;
reset role;
reset request.jwt.claim.sub;

-- T05: API roles cannot directly access Owner assignment/audit tables or privileged RPCs.
do $test$
begin
  if has_table_privilege('authenticated','public.platform_audit_logs','SELECT')
     or has_table_privilege('authenticated','public.platform_audit_logs','INSERT')
     or has_table_privilege('authenticated','public.platform_audit_logs','UPDATE')
     or has_table_privilege('authenticated','public.platform_audit_logs','DELETE')
     or has_table_privilege('authenticated','public.platform_admin_roles','SELECT')
     or has_table_privilege('authenticated','public.platform_admin_roles','INSERT')
     or has_table_privilege('authenticated','public.platform_admin_roles','UPDATE')
     or has_table_privilege('authenticated','public.platform_admin_roles','DELETE')
     or has_table_privilege('service_role','public.platform_admin_roles','INSERT')
     or has_table_privilege('service_role','public.platform_admin_roles','UPDATE')
     or has_table_privilege('service_role','public.platform_admin_roles','DELETE') then
    raise exception 'T05 FAILED: API role has direct Owner assignment/audit table access';
  end if;
  if has_function_privilege('anon','public.platform_owner_grant_v1(uuid,text)','EXECUTE')
     or has_function_privilege('service_role','public.platform_owner_grant_v1(uuid,text)','EXECUTE')
     or has_function_privilege('anon','public.platform_owner_revoke_v1(uuid,text)','EXECUTE')
     or has_function_privilege('service_role','public.platform_owner_revoke_v1(uuid,text)','EXECUTE') then
    raise exception 'T05 FAILED: anon/service_role can execute Owner management RPCs';
  end if;
end;
$test$;

-- T06: audit records are immutable.
do $test$
declare v_blocked boolean := false;
begin
  begin
    update public.platform_audit_logs set reason='tampered'
    where action='platform_owner.granted';
  exception when sqlstate '55000' then v_blocked := true;
  end;
  if not v_blocked then raise exception 'T06 FAILED: platform audit record was mutable'; end if;
end;
$test$;

do $test$
begin
  if (select count(*) from public.platform_audit_logs) <> 2 then
    raise exception 'Expected exactly two paired handover audit events';
  end if;
  if (select count(*) from public.platform_admin_roles where role_key='platform_owner' and revoked_at is null and (expires_at is null or expires_at>now())) <> 1 then
    raise exception 'Expected exactly one active Platform Owner after handover';
  end if;
  if exists(select 1 from public.platform_admin_roles where user_id='10000000-0000-0000-0000-000000000001' and role_key='platform_owner' and revoked_at is null) then
    raise exception 'Former Platform Owner still has active access';
  end if;
end;
$test$;

select 'PASS: single-slot Platform Owner handover requires verified Auth user' as result;
select 'PASS: final Platform Owner cannot be revoked or locked out' as result;
select 'PASS: handover writes paired immutable grant/revoke audit events' as result;
select 'PASS: former Owner loses access and direct API table access is denied' as result;
