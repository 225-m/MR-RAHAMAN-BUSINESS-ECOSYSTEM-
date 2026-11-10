-- MR RAHAMAN Business Ecosystem
-- CUSTOMER ACCESS v1 — DRAFT ONLY; NOT APPLIED TO PRODUCTION.
-- Purpose: let verified Auth users enter a restricted self-service Customer area
-- without requiring a Platform Owner or organization membership.
-- Run only in an isolated PostgreSQL/Supabase test environment after review.

begin;

create table if not exists public.customer_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.customer_profiles enable row level security;

revoke all on table public.customer_profiles from public, anon, authenticated;
grant select on table public.customer_profiles to authenticated;
grant update (display_name, avatar_path) on table public.customer_profiles to authenticated;

do $avatar_constraint$ begin
  alter table public.customer_profiles
    add constraint customer_profiles_avatar_path_own
    check (avatar_path is null or avatar_path = user_id::text || '/avatar');
exception when duplicate_object then null;
end $avatar_constraint$;

drop policy if exists customer_profiles_select_own on public.customer_profiles;
create policy customer_profiles_select_own
  on public.customer_profiles
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists customer_profiles_update_own on public.customer_profiles;
create policy customer_profiles_update_own
  on public.customer_profiles
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check (
    (select auth.uid()) = user_id
    and (avatar_path is null or avatar_path = user_id::text || '/avatar')
  );

-- Private Customer avatar bucket. Every Customer can manage only one fixed object
-- path under their own Auth UUID. Never expose a public bucket or arbitrary paths.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'customer-avatars',
  'customer-avatars',
  false,
  5242880,
  array['image/jpeg','image/png','image/webp']
)
on conflict (id) do update
set public = false,
    file_size_limit = 5242880,
    allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists customer_avatars_select_own on storage.objects;
create policy customer_avatars_select_own
  on storage.objects for select to authenticated
  using (bucket_id = 'customer-avatars'
    and name = (select auth.uid())::text || '/avatar');

drop policy if exists customer_avatars_insert_own on storage.objects;
create policy customer_avatars_insert_own
  on storage.objects for insert to authenticated
  with check (bucket_id = 'customer-avatars'
    and name = (select auth.uid())::text || '/avatar');

drop policy if exists customer_avatars_update_own on storage.objects;
create policy customer_avatars_update_own
  on storage.objects for update to authenticated
  using (bucket_id = 'customer-avatars'
    and name = (select auth.uid())::text || '/avatar')
  with check (bucket_id = 'customer-avatars'
    and name = (select auth.uid())::text || '/avatar');

drop policy if exists customer_avatars_delete_own on storage.objects;
create policy customer_avatars_delete_own
  on storage.objects for delete to authenticated
  using (bucket_id = 'customer-avatars'
    and name = (select auth.uid())::text || '/avatar');


create or replace function private.set_customer_profile_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  new.updated_at := pg_catalog.now();
  return new;
end;
$function$;

revoke all on function private.set_customer_profile_updated_at() from public, anon, authenticated;

drop trigger if exists customer_profiles_set_updated_at on public.customer_profiles;
create trigger customer_profiles_set_updated_at
before update on public.customer_profiles
for each row execute function private.set_customer_profile_updated_at();

create or replace function private.create_customer_profile_for_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  insert into public.customer_profiles (user_id, display_name)
  values (
    new.id,
    nullif(pg_catalog.btrim(new.raw_user_meta_data ->> 'full_name'), '')
  )
  on conflict (user_id) do nothing;
  return new;
end;
$function$;

revoke all on function private.create_customer_profile_for_auth_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created_customer_profile on auth.users;
create trigger on_auth_user_created_customer_profile
after insert on auth.users
for each row execute function private.create_customer_profile_for_auth_user();

-- Backfill existing Auth identities as customer profiles. This does not grant
-- organization, employee, admin, or platform-owner permissions.
insert into public.customer_profiles (user_id, display_name)
select
  u.id,
  nullif(pg_catalog.btrim(u.raw_user_meta_data ->> 'full_name'), '')
from auth.users u
on conflict (user_id) do nothing;

create or replace function private.current_access_context_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_is_platform_owner boolean := false;
  v_is_customer boolean := false;
  v_customer_profile jsonb := null;
  v_organizations jsonb := '[]'::jsonb;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select exists (
    select 1
    from public.platform_admin_roles par
    where par.user_id = v_user_id
      and par.role_key = 'platform_owner'
      and par.revoked_at is null
      and (par.expires_at is null or par.expires_at > pg_catalog.now())
  ) into v_is_platform_owner;

  select exists (
    select 1 from public.customer_profiles cp where cp.user_id = v_user_id
  ) into v_is_customer;

  select pg_catalog.jsonb_build_object(
    'display_name', cp.display_name,
    'avatar_path', cp.avatar_path,
    'created_at', cp.created_at
  )
  into v_customer_profile
  from public.customer_profiles cp
  where cp.user_id = v_user_id;

  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'organization_id', membership.organization_id,
        'organization_name', membership.organization_name,
        'role_key', membership.role_key,
        'permissions', membership.permissions
      )
      order by membership.organization_name
    ),
    '[]'::jsonb
  )
  into v_organizations
  from (
    select
      m.organization_id,
      o.name as organization_name,
      r.role_key,
      coalesce((
        select pg_catalog.jsonb_agg(p.permission_key order by p.permission_key)
        from public.role_permissions rp
        join public.permissions p on p.id = rp.permission_id
        where rp.organization_id = m.organization_id
          and rp.role_id = r.id
      ), '[]'::jsonb) as permissions
    from public.organization_members m
    join public.organizations o
      on o.id = m.organization_id and o.status = 'active'
    join public.app_roles r
      on r.id = m.role_id
     and r.organization_id = m.organization_id
     and r.is_active = true
    where m.user_id = v_user_id
      and m.member_status = 'active'
  ) membership;

  return pg_catalog.jsonb_build_object(
    'user_id', v_user_id,
    'is_customer', v_is_customer,
    'customer_profile', v_customer_profile,
    'is_platform_owner', v_is_platform_owner,
    'organizations', v_organizations
  );
end;
$function$;

-- The public SECURITY INVOKER wrapper must be able to resolve this private function.
-- Schema USAGE does not grant table access; the private tables remain ungranted.
grant usage on schema private to authenticated;
revoke all on function private.current_access_context_v1() from public, anon, authenticated;
grant execute on function private.current_access_context_v1() to authenticated;

create or replace function public.current_access_context_v1()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
  select private.current_access_context_v1();
$function$;

revoke all on function public.current_access_context_v1() from public, anon, authenticated;
grant execute on function public.current_access_context_v1() to authenticated;

commit;

-- REQUIRED TESTS BEFORE ANY PRODUCTION RELEASE:
-- * New Auth signup creates exactly one customer_profiles row.
-- * Existing Auth users are backfilled exactly once.
-- * Unauthenticated/anon cannot call the RPC or read/write customer_profiles.
-- * Authenticated Customer A can read/update only their own display_name.
-- * Customer A cannot read/update Customer B's profile.
-- * Customer cannot INSERT, DELETE, or change user_id/created_at/updated_at.
-- * Avatar upload/replace/delete is limited to auth.uid()/avatar in private bucket;
--   MIME allowlist and 5 MiB limit enforced by Storage bucket.
-- * Customer context reports is_customer=true, is_platform_owner=false,
--   organizations=[] when no authorized organization membership exists.
-- * Missing/failed RPC keeps all business/admin workspaces closed.
-- * Existing active Owner/member context remains compatible with the current UI.
-- * User metadata is used only as an initial display name, never as authorization.
-- * Rollback tested only in disposable DB; never delete customer profile/business data
--   after users have begun using the feature.
