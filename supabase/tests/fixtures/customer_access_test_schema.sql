-- Disposable PostgreSQL fixture for customer_access_v1.sql integration checks.
-- Never run against the Supabase Production project.
do $$ begin create role anon nologin; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated nologin; exception when duplicate_object then null; end $$;
create schema if not exists auth;
create schema if not exists private;
grant usage on schema auth, private to authenticated;
grant usage on schema auth to anon;

create table auth.users (
  id uuid primary key,
  email text unique not null,
  email_confirmed_at timestamptz,
  raw_user_meta_data jsonb not null default '{}'::jsonb
);
create or replace function auth.uid()
returns uuid language sql stable
as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant execute on function auth.uid() to authenticated, anon;

create table public.platform_admin_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  role_key text not null,
  revoked_at timestamptz,
  expires_at timestamptz
);
create table public.organizations (
  id uuid primary key,
  name text not null,
  status text not null
);
create table public.app_roles (
  id uuid primary key,
  organization_id uuid not null,
  role_key text not null,
  is_active boolean not null
);
create table public.organization_members (
  organization_id uuid not null,
  user_id uuid not null,
  role_id uuid,
  member_status text not null
);
create table public.permissions (
  id uuid primary key,
  permission_key text not null
);
create table public.role_permissions (
  organization_id uuid not null,
  role_id uuid not null,
  permission_id uuid not null
);

-- Existing Auth identity for migration backfill.
insert into auth.users (id,email,email_confirmed_at,raw_user_meta_data)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','customer-a@example.test',now(),'{"full_name":"Customer A"}');
