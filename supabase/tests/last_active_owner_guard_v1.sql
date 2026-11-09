-- Last Active Owner Guard V1 integration tests — disposable DB only.
\set ON_ERROR_STOP on

insert into auth.users(id) values
 ('10000000-0000-0000-0000-000000000001'),
 ('10000000-0000-0000-0000-000000000002'),
 ('10000000-0000-0000-0000-000000000003'),
 ('10000000-0000-0000-0000-000000000004'),
 ('10000000-0000-0000-0000-000000000005');

insert into public.platform_admin_roles(id,user_id,role_key) values
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','platform_owner'),
 ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','platform_owner'),
 ('20000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000003','security_admin');

-- T01: one of two platform Owners may be revoked.
update public.platform_admin_roles set revoked_at=now()
where id='20000000-0000-0000-0000-000000000001';

-- T02: the final active platform Owner cannot be revoked.
do $test$
declare v_blocked boolean := false;
begin
  begin
    update public.platform_admin_roles set revoked_at=now()
    where id='20000000-0000-0000-0000-000000000002';
  exception when sqlstate '55000' then v_blocked := true;
  end;
  if not v_blocked then raise exception 'T02 FAILED: last Platform Owner revoke was not blocked'; end if;
  if not exists(select 1 from public.platform_admin_roles where id='20000000-0000-0000-0000-000000000002' and revoked_at is null) then
    raise exception 'T02 FAILED: final Platform Owner row changed despite guard';
  end if;
end;
$test$;

-- T03: expiring or demoting the final active platform Owner is also blocked.
do $test$
declare v_expiry_blocked boolean := false; v_demote_blocked boolean := false;
begin
  begin
    update public.platform_admin_roles set expires_at=now()-interval '1 minute'
    where id='20000000-0000-0000-0000-000000000002';
  exception when sqlstate '55000' then v_expiry_blocked := true;
  end;
  begin
    update public.platform_admin_roles set role_key='platform_admin'
    where id='20000000-0000-0000-0000-000000000002';
  exception when sqlstate '55000' then v_demote_blocked := true;
  end;
  if not v_expiry_blocked or not v_demote_blocked then
    raise exception 'T03 FAILED: final Platform Owner expiry/demotion was not blocked';
  end if;
end;
$test$;

-- T04: non-owner platform role is not protected as an Owner.
update public.platform_admin_roles set revoked_at=now()
where id='20000000-0000-0000-0000-000000000003';

insert into public.organizations(id,status)
values('30000000-0000-0000-0000-000000000001','active');

insert into public.app_roles(id,organization_id,role_key,is_active) values
 ('40000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','owner',true),
 ('40000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000001','owner',true),
 ('40000000-0000-0000-0000-000000000003','30000000-0000-0000-0000-000000000001','staff',true);

insert into public.organization_members(id,organization_id,user_id,role_id,member_status) values
 ('50000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','active'),
 ('50000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-000000000002','active'),
 ('50000000-0000-0000-0000-000000000003','30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','40000000-0000-0000-0000-000000000003','active');

-- T05: removing one of two organization Owners is allowed.
update public.organization_members set member_status='suspended'
where id='50000000-0000-0000-0000-000000000001';

-- T06: disabling the role that owns the final active Owner is blocked.
do $test$
declare v_blocked boolean := false;
begin
  begin
    update public.app_roles set is_active=false
    where id='40000000-0000-0000-0000-000000000002';
  exception when sqlstate '55000' then v_blocked := true;
  end;
  if not v_blocked then raise exception 'T06 FAILED: disabling final Owner role was not blocked'; end if;
end;
$test$;

-- T07: suspending/removing/demoting the final active organization Owner is blocked.
do $test$
declare v_suspend_blocked boolean := false; v_demote_blocked boolean := false; v_delete_blocked boolean := false;
begin
  begin
    update public.organization_members set member_status='suspended'
    where id='50000000-0000-0000-0000-000000000002';
  exception when sqlstate '55000' then v_suspend_blocked := true;
  end;
  begin
    update public.organization_members set role_id='40000000-0000-0000-0000-000000000003'
    where id='50000000-0000-0000-0000-000000000002';
  exception when sqlstate '55000' then v_demote_blocked := true;
  end;
  begin
    delete from public.organization_members
    where id='50000000-0000-0000-0000-000000000002';
  exception when sqlstate '55000' then v_delete_blocked := true;
  end;
  if not v_suspend_blocked or not v_demote_blocked or not v_delete_blocked then
    raise exception 'T07 FAILED: final organization Owner lockout path was not blocked';
  end if;
  if not exists(select 1 from public.organization_members where id='50000000-0000-0000-0000-000000000002' and member_status='active' and role_id='40000000-0000-0000-0000-000000000002') then
    raise exception 'T07 FAILED: final organization Owner membership changed despite guard';
  end if;
end;
$test$;

-- T08: non-owner membership can be removed normally.
delete from public.organization_members
where id='50000000-0000-0000-0000-000000000003';

-- T09: the active platform Owner can be replaced only by a trusted privileged operation
-- that leaves at least one active Owner in place; this guard does not grant table DML.
do $test$
begin
  if (select count(*) from public.platform_admin_roles where role_key='platform_owner' and revoked_at is null and (expires_at is null or expires_at>now())) <> 1 then
    raise exception 'T09 FAILED: expected exactly one active Platform Owner in fixture';
  end if;
  if (select count(*) from public.organization_members m join public.app_roles r on r.id=m.role_id and r.organization_id=m.organization_id where m.organization_id='30000000-0000-0000-0000-000000000001' and m.member_status='active' and r.role_key='owner' and r.is_active) <> 1 then
    raise exception 'T09 FAILED: expected exactly one active organization Owner in fixture';
  end if;
end;
$test$;

select 'PASS: Last Active Platform Owner revoke/expiry/demotion guard' as result;
select 'PASS: Last Active Organization Owner membership/role guard' as result;
select 'PASS: non-owner role/member operations remain available' as result;
