-- MR RAHAMAN Business Ecosystem
-- PLATFORM OWNER MANAGEMENT + AUDIT V1 — DRAFT ONLY; DO NOT APPLY TO PRODUCTION.
-- First Owner creation remains the separate one-time service_role bootstrap.
-- After bootstrap, active Platform Owners can grant/revoke other Platform Owners.
-- Every successful grant/revoke is written to an append-only platform audit log.

begin;

create table if not exists public.platform_audit_logs (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  actor_user_id uuid not null references auth.users(id),
  target_user_id uuid not null references auth.users(id),
  action text not null check (action in ('platform_owner.granted','platform_owner.revoked')),
  role_key text not null check (role_key = 'platform_owner'),
  reason text not null check (length(pg_catalog.btrim(reason)) >= 5),
  old_values jsonb,
  new_values jsonb,
  created_at timestamptz not null default pg_catalog.clock_timestamp()
);

alter table public.platform_audit_logs enable row level security;
revoke all on table public.platform_audit_logs from public, anon, authenticated, service_role;

create or replace function private.is_active_platform_owner_v1(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.platform_admin_roles par
    where par.user_id = p_user_id
      and par.role_key = 'platform_owner'
      and par.revoked_at is null
      and (par.expires_at is null or par.expires_at > pg_catalog.statement_timestamp())
  );
$function$;

create or replace function private.reject_platform_audit_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  raise exception 'platform_audit_logs is append-only'
    using errcode = '55000';
end;
$function$;

drop trigger if exists platform_audit_logs_immutable on public.platform_audit_logs;
create trigger platform_audit_logs_immutable
before update or delete on public.platform_audit_logs
for each row execute function private.reject_platform_audit_mutation_v1();

create or replace function public.platform_owner_grant_v1(
  p_target_user_id uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_role_id uuid;
begin
  if v_actor_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not private.is_active_platform_owner_v1(v_actor_id) then
    raise exception 'Active Platform Owner required' using errcode = '42501';
  end if;
  if p_target_user_id is null or p_reason is null or pg_catalog.length(pg_catalog.btrim(p_reason)) < 5 then
    raise exception 'Target user and a reason of at least five characters are required' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(73021, 1);

  if not exists (
    select 1 from auth.users u
    where u.id = p_target_user_id and u.email_confirmed_at is not null
  ) then
    raise exception 'Target Auth user must exist and have a verified email' using errcode = '22023';
  end if;

  if private.is_active_platform_owner_v1(p_target_user_id) then
    raise exception 'Target user is already an active Platform Owner' using errcode = '23505';
  end if;

  insert into public.platform_admin_roles(user_id, role_key, granted_by, expires_at, revoked_at)
  values (p_target_user_id, 'platform_owner', v_actor_id, null, null)
  returning id into v_role_id;

  insert into public.platform_audit_logs(
    actor_user_id, target_user_id, action, role_key, reason, old_values, new_values
  ) values (
    v_actor_id, p_target_user_id, 'platform_owner.granted', 'platform_owner', pg_catalog.btrim(p_reason),
    null, pg_catalog.jsonb_build_object('platform_admin_role_id', v_role_id, 'active', true)
  );

  return v_role_id;
end;
$function$;

create or replace function public.platform_owner_revoke_v1(
  p_target_user_id uuid,
  p_reason text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_role record;
  v_revoked_count integer := 0;
  v_revoked_at timestamptz := pg_catalog.clock_timestamp();
begin
  if v_actor_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not private.is_active_platform_owner_v1(v_actor_id) then
    raise exception 'Active Platform Owner required' using errcode = '42501';
  end if;
  if p_target_user_id is null or p_reason is null or pg_catalog.length(pg_catalog.btrim(p_reason)) < 5 then
    raise exception 'Target user and a reason of at least five characters are required' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(73021, 1);

  for v_role in
    select par.id
    from public.platform_admin_roles par
    where par.user_id = p_target_user_id
      and par.role_key = 'platform_owner'
      and par.revoked_at is null
      and (par.expires_at is null or par.expires_at > v_revoked_at)
    order by par.id
    for update
  loop
    update public.platform_admin_roles
    set revoked_at = v_revoked_at
    where id = v_role.id;
    v_revoked_count := v_revoked_count + 1;
  end loop;

  if v_revoked_count = 0 then
    raise exception 'No active Platform Owner grant exists for target user' using errcode = 'P0002';
  end if;

  insert into public.platform_audit_logs(
    actor_user_id, target_user_id, action, role_key, reason, old_values, new_values
  ) values (
    v_actor_id, p_target_user_id, 'platform_owner.revoked', 'platform_owner', pg_catalog.btrim(p_reason),
    pg_catalog.jsonb_build_object('active_grant_count', v_revoked_count),
    pg_catalog.jsonb_build_object('revoked_at', v_revoked_at)
  );

  return v_revoked_count;
end;
$function$;

create or replace function public.platform_owner_audit_list_v1(p_limit integer default 50)
returns table (
  id uuid,
  actor_user_id uuid,
  target_user_id uuid,
  action text,
  role_key text,
  reason text,
  old_values jsonb,
  new_values jsonb,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_limit integer := greatest(1, least(coalesce(p_limit, 50), 200));
begin
  if v_actor_id is null or not private.is_active_platform_owner_v1(v_actor_id) then
    raise exception 'Active Platform Owner required' using errcode = '42501';
  end if;

  return query
  select l.id, l.actor_user_id, l.target_user_id, l.action, l.role_key,
         l.reason, l.old_values, l.new_values, l.created_at
  from public.platform_audit_logs l
  order by l.created_at desc, l.id desc
  limit v_limit;
end;
$function$;

revoke all on function private.is_active_platform_owner_v1(uuid) from public, anon, authenticated, service_role;
revoke all on function private.reject_platform_audit_mutation_v1() from public, anon, authenticated, service_role;
revoke all on function public.platform_owner_grant_v1(uuid,text) from public, anon, service_role;
revoke all on function public.platform_owner_revoke_v1(uuid,text) from public, anon, service_role;
revoke all on function public.platform_owner_audit_list_v1(integer) from public, anon, service_role;

grant execute on function public.platform_owner_grant_v1(uuid,text) to authenticated;
grant execute on function public.platform_owner_revoke_v1(uuid,text) to authenticated;
grant execute on function public.platform_owner_audit_list_v1(integer) to authenticated;

commit;

-- The first-owner bootstrap V2 must run only after this audit table exists and
-- must write its initial platform_owner.granted event in the same transaction.
-- Direct table reads/writes remain unavailable to API roles; use the audited RPCs.
