-- Platform Owner grant/revoke audit V1 integration tests — disposable DB only.
\set ON_ERROR_STOP on

insert into auth.users(id,email_confirmed_at) values
 ('10000000-0000-0000-0000-000000000001',now()),
 ('10000000-0000-0000-0000-000000000002',now()),
 ('10000000-0000-0000-0000-000000000003',now()),
 ('10000000-0000-0000-0000-000000000004',null);

-- Simulate the one-time service_role bootstrap creating the first Platform Owner.
insert into public.platform_admin_roles(id,user_id,role_key,granted_by)
values('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','platform_owner','10000000-0000-0000-0000-000000000001');

-- T01: active Platform Owner can grant a second verified Platform Owner.
set role authenticated;
set request.jwt.claim.sub = '10000000-0000-0000-0000-000000000001';
select public.platform_owner_grant_v1('10000000-0000-0000-0000-000000000002','Add second trusted Platform Owner');
reset role;
reset request.jwt.claim.sub;

-- T02: an unverified Auth user cannot be granted Platform Owner.
set role authenticated;
set request.jwt.claim.sub = '10000000-0000-0000-0000-000000000001';
do $test$
declare v_blocked boolean := false;
begin
  begin
    perform public.platform_owner_grant_v1('10000000-0000-0000-0000-000000000004','Unverified target should fail');
  exception when sqlstate '22023' then v_blocked := true;
  end;
  if not v_blocked then raise exception 'T02 FAILED: unverified target was granted Platform Owner'; end if;
end;
$test$;
reset role;
reset request.jwt.claim.sub;

-- T03: a second active Owner can revoke the first Owner; the action is audited.
set role authenticated;
set request.jwt.claim.sub = '10000000-0000-0000-0000-000000000002';
select public.platform_owner_revoke_v1('10000000-0000-0000-0000-000000000001','Rotate first Platform Owner access');
reset role;
reset request.jwt.claim.sub;

-- T04: the final active Platform Owner cannot revoke themself.
set role authenticated;
set request.jwt.claim.sub = '10000000-0000-0000-0000-000000000002';
do $test$
declare v_blocked boolean := false;
begin
  begin
    perform public.platform_owner_revoke_v1('10000000-0000-0000-0000-000000000002','Attempt last Owner self revoke');
  exception when sqlstate '55000' then v_blocked := true;
  end;
  if not v_blocked then raise exception 'T04 FAILED: final Platform Owner self-revoke was not blocked'; end if;
end;
$test$;
reset role;
reset request.jwt.claim.sub;

-- T05: a current Owner can grant a third Owner, then self-revoke while another remains.
set role authenticated;
set request.jwt.claim.sub = '10000000-0000-0000-0000-000000000002';
select public.platform_owner_grant_v1('10000000-0000-0000-0000-000000000003','Add third trusted Platform Owner');
select public.platform_owner_revoke_v1('10000000-0000-0000-0000-000000000002','Transfer responsibility to third Owner');
reset role;
reset request.jwt.claim.sub;

-- T06: the remaining active Owner can read the audit trail.
set role authenticated;
set request.jwt.claim.sub = '10000000-0000-0000-0000-000000000003';
do $test$
declare v_count integer;
begin
  select count(*) into v_count from public.platform_owner_audit_list_v1(50);
  if v_count <> 4 then raise exception 'T06 FAILED: expected 4 audit events, found %', v_count; end if;
end;
$test$;
reset role;
reset request.jwt.claim.sub;

-- T07: revoked Owner cannot read audit records or grant another Owner.
set role authenticated;
set request.jwt.claim.sub = '10000000-0000-0000-0000-000000000001';
do $test$
declare v_blocked boolean := false;
begin
  begin
    perform count(*) from public.platform_owner_audit_list_v1(50);
  exception when sqlstate '42501' then v_blocked := true;
  end;
  if not v_blocked then raise exception 'T07 FAILED: revoked Owner read platform audit logs'; end if;
  v_blocked := false;
  begin
    perform public.platform_owner_grant_v1('10000000-0000-0000-0000-000000000004','Revoked actor must not grant');
  exception when sqlstate '42501' then v_blocked := true;
  end;
  if not v_blocked then raise exception 'T07 FAILED: revoked Owner granted another Platform Owner'; end if;
end;
$test$;
reset role;
reset request.jwt.claim.sub;

-- T08: API roles cannot directly read or mutate the audit table.
do $test$
begin
  if has_table_privilege('authenticated','public.platform_audit_logs','SELECT')
     or has_table_privilege('authenticated','public.platform_audit_logs','INSERT')
     or has_table_privilege('authenticated','public.platform_audit_logs','UPDATE')
     or has_table_privilege('authenticated','public.platform_audit_logs','DELETE') then
    raise exception 'T08 FAILED: authenticated direct platform audit table access is granted';
  end if;
  if has_table_privilege('authenticated','public.platform_admin_roles','SELECT')
     or has_table_privilege('authenticated','public.platform_admin_roles','INSERT')
     or has_table_privilege('authenticated','public.platform_admin_roles','UPDATE')
     or has_table_privilege('authenticated','public.platform_admin_roles','DELETE')
     or has_table_privilege('service_role','public.platform_admin_roles','INSERT')
     or has_table_privilege('service_role','public.platform_admin_roles','UPDATE')
     or has_table_privilege('service_role','public.platform_admin_roles','DELETE') then
    raise exception 'T08 FAILED: API role has direct platform Owner assignment access';
  end if;
  if has_function_privilege('anon','public.platform_owner_grant_v1(uuid,text)','EXECUTE')
     or has_function_privilege('service_role','public.platform_owner_grant_v1(uuid,text)','EXECUTE')
     or has_function_privilege('anon','public.platform_owner_revoke_v1(uuid,text)','EXECUTE')
     or has_function_privilege('service_role','public.platform_owner_revoke_v1(uuid,text)','EXECUTE') then
    raise exception 'T08 FAILED: unauthenticated/server API role can call Owner management RPCs';
  end if;
end;
$test$;

-- T09: audit records are immutable even to the database owner.
do $test$
declare v_blocked boolean := false;
begin
  begin
    update public.platform_audit_logs set reason='tampered'
    where action='platform_owner.granted';
  exception when sqlstate '55000' then v_blocked := true;
  end;
  if not v_blocked then raise exception 'T09 FAILED: platform audit record was mutable'; end if;
end;
$test$;

do $test$
begin
  if (select count(*) from public.platform_audit_logs) <> 4 then
    raise exception 'Expected four successful audited grant/revoke operations';
  end if;
  if (select count(*) from public.platform_admin_roles where role_key='platform_owner' and revoked_at is null and (expires_at is null or expires_at>now())) <> 1 then
    raise exception 'Expected exactly one active Platform Owner after tests';
  end if;
end;
$test$;

select 'PASS: verified-user-only Platform Owner grant/revoke' as result;
select 'PASS: last Owner cannot self-revoke' as result;
select 'PASS: every successful Owner grant/revoke is audited' as result;
select 'PASS: Platform Owner audit is immutable and Owner-only' as result;
