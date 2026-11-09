-- Disposable PostgreSQL fixture for Last Active Owner Guard V1.
create schema auth;
create table auth.users(id uuid primary key);

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

create table public.organization_members(
 id uuid primary key,
 organization_id uuid not null references public.organizations(id),
 user_id uuid not null references auth.users(id),
 role_id uuid references public.app_roles(id),
 member_status text not null
);
