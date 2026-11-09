-- MR RAHAMAN Business Ecosystem
-- LAST ACTIVE OWNER GUARD V1 — DRAFT ONLY; DO NOT APPLY TO PRODUCTION.
-- Protects the final active platform Owner and final active organization Owner.
-- This is defense in depth: current Production RLS/grants remain the primary boundary.

begin;

create or replace function private.guard_last_platform_owner_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_old_is_active_owner boolean;
  v_new_is_active_owner boolean := false;
  v_other_active_owners bigint;
begin
  v_old_is_active_owner :=
    old.role_key = 'platform_owner'
    and old.revoked_at is null
    and (old.expires_at is null or old.expires_at > pg_catalog.clock_timestamp());

  if tg_op = 'UPDATE' then
    v_new_is_active_owner :=
      new.role_key = 'platform_owner'
      and new.revoked_at is null
      and (new.expires_at is null or new.expires_at > pg_catalog.clock_timestamp());
  end if;

  if v_old_is_active_owner and not v_new_is_active_owner then
    -- Serialize concurrent revoke/expiry/delete operations for the platform Owner set.
    perform pg_catalog.pg_advisory_xact_lock(73021, 1);

    select count(*) into v_other_active_owners
    from public.platform_admin_roles par
    where par.role_key = 'platform_owner'
      and par.revoked_at is null
      and (par.expires_at is null or par.expires_at > pg_catalog.clock_timestamp())
      and par.id <> old.id;

    if v_other_active_owners = 0 then
      raise exception 'Cannot revoke, expire, demote, or delete the last active Platform Owner'
        using errcode = '55000';
    end if;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

create or replace function private.guard_last_organization_owner_role_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_old_is_owner_role boolean;
  v_new_is_owner_role boolean := false;
  v_other_active_owners bigint;
begin
  v_old_is_owner_role := old.role_key = 'owner' and old.is_active = true;
  if tg_op = 'UPDATE' then
    v_new_is_owner_role := new.role_key = 'owner' and new.is_active = true;
  end if;

  if v_old_is_owner_role and not v_new_is_owner_role then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('org-owner-guard:' || old.organization_id::text, 0)
    );

    select count(*) into v_other_active_owners
    from public.organization_members m
    join public.app_roles r
      on r.id = m.role_id
     and r.organization_id = m.organization_id
     and r.role_key = 'owner'
     and r.is_active = true
    join public.organizations o on o.id = m.organization_id and o.status = 'active'
    where m.organization_id = old.organization_id
      and m.member_status = 'active'
      and m.role_id <> old.id;

    if exists (
      select 1 from public.organization_members m
      where m.organization_id = old.organization_id and m.role_id = old.id
        and m.member_status = 'active'
    ) and v_other_active_owners = 0 then
      raise exception 'Cannot disable, rename, or delete the last active organization Owner role'
        using errcode = '55000';
    end if;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

create or replace function private.guard_last_organization_owner_member_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_old_is_active_owner boolean;
  v_new_is_active_owner boolean := false;
  v_other_active_owners bigint;
begin
  select exists (
    select 1
    from public.app_roles r
    join public.organizations o on o.id = old.organization_id and o.status = 'active'
    where r.id = old.role_id
      and r.organization_id = old.organization_id
      and r.role_key = 'owner'
      and r.is_active = true
  ) and old.member_status = 'active'
  into v_old_is_active_owner;

  if tg_op = 'UPDATE' then
    select exists (
      select 1
      from public.app_roles r
      join public.organizations o on o.id = new.organization_id and o.status = 'active'
      where r.id = new.role_id
        and r.organization_id = new.organization_id
        and r.role_key = 'owner'
        and r.is_active = true
    ) and new.member_status = 'active'
    into v_new_is_active_owner;
  end if;

  if v_old_is_active_owner and not v_new_is_active_owner then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('org-owner-guard:' || old.organization_id::text, 0)
    );

    select count(*) into v_other_active_owners
    from public.organization_members m
    join public.app_roles r
      on r.id = m.role_id
     and r.organization_id = m.organization_id
     and r.role_key = 'owner'
     and r.is_active = true
    join public.organizations o on o.id = m.organization_id and o.status = 'active'
    where m.organization_id = old.organization_id
      and m.member_status = 'active'
      and m.id <> old.id;

    if v_other_active_owners = 0 then
      raise exception 'Cannot suspend, remove, or demote the last active organization Owner'
        using errcode = '55000';
    end if;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

drop trigger if exists platform_admin_roles_last_owner_guard on public.platform_admin_roles;
create trigger platform_admin_roles_last_owner_guard
before update or delete on public.platform_admin_roles
for each row execute function private.guard_last_platform_owner_v1();

drop trigger if exists app_roles_last_owner_guard on public.app_roles;
create trigger app_roles_last_owner_guard
before update or delete on public.app_roles
for each row execute function private.guard_last_organization_owner_role_v1();

drop trigger if exists organization_members_last_owner_guard on public.organization_members;
create trigger organization_members_last_owner_guard
before update or delete on public.organization_members
for each row execute function private.guard_last_organization_owner_member_v1();

revoke all on function private.guard_last_platform_owner_v1() from public, anon, authenticated, service_role;
revoke all on function private.guard_last_organization_owner_role_v1() from public, anon, authenticated, service_role;
revoke all on function private.guard_last_organization_owner_member_v1() from public, anon, authenticated, service_role;

commit;

-- Contract:
-- * platform_admin_roles.role_key = 'platform_owner' is the trusted platform Owner.
-- * app_roles.role_key = 'owner' is the canonical organization Owner role.
-- * An Owner transfer is possible only while another active Owner exists, or by
--   changing an active Owner row to another active Owner identity in one trusted
--   privileged transaction. API clients must never receive direct table DML.
-- * Role-permission edits that strip required Owner permissions need a separate
--   policy review; this trigger protects Owner assignment/activation, not role grants.
-- * No Production rows, grants, triggers, or policies were changed by this draft.
