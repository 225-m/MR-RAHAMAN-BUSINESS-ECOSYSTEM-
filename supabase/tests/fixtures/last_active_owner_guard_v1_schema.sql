-- Disposable PostgreSQL fixture for Last Active Owner Guard V1.
do $roles$
begin
  create role anon nologin;
exception when duplicate_object then null;
end;
$roles$;
do $roles$
begin
  create role authenticated nologin;
exception when duplicate_object then null;
end;
$roles$;
do $roles$
begin
  create role service_role nologin bypassrls;
exception when duplicate_object then null;
end;
$roles$;
create schema auth;
create table auth.users(id uuid primary key, email_confirmed_at timestamptz);

create or replace function auth.uid() returns uuid
language sql stable
as $auth_uid$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $auth_uid$;;

create schema private;

create table public.platform_admin_roles(
 id uuid primary key,
 user_id uuid not null references auth.users(id),
 role_key text not null,
 granted_by uuid,
 granted_at timestamptz not null default now(),
 expires_at timestamptz,
 revoked_at timestamptz
);
create unique index platform_admin_roles_single_active_owner_idx
  on public.platform_admin_roles(role_key)
  where role_key = 'platform_owner' and revoked_at is null;

create table public.organizations(
 id uuid primary key,
 status text not null
);

create table public.app_roles(
 id uuid primary key,
 organization_id uuid not null references public.organizations(id),
 role_key text not null,
 is_active boolean not null default true
);

create table public.permissions(
 id uuid primary key,
 permission_key text not null unique
);

create table public.role_permissions(
 organization_id uuid not null,
 role_id uuid not null,
 permission_id uuid not null
);

create table public.organization_members(
 id uuid primary key,
 organization_id uuid not null references public.organizations(id),
 user_id uuid not null references auth.users(id),
 role_id uuid references public.app_roles(id),
 member_status text not null
);
