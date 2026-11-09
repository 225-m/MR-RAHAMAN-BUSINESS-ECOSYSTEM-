-- Minimal disposable PostgreSQL fixture for Module Lifecycle V1 RPC tests.
-- This models the Production table/constraint contracts used by the draft migration.
-- Never run this fixture against Supabase Production.

do $roles$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin; end if;
end;
$roles$;

create schema auth;
create schema private;

create table auth.users (id uuid primary key);

create or replace function auth.uid()
returns uuid
language sql
stable
set search_path = ''
as $function$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$function$;

create table public.organizations (
  id uuid primary key,
  name text not null default 'Fixture Organization',
  status text not null
);

create table public.platform_admin_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  role_key text not null,
  expires_at timestamptz,
  revoked_at timestamptz
);

create table public.permissions (
  id uuid primary key,
  permission_key text not null unique,
  description text,
  module_key text
);

create table public.app_roles (
  id uuid primary key,
  organization_id uuid not null references public.organizations(id),
  role_key text not null,
  is_active boolean not null default true
);

create table public.organization_members (
  id uuid primary key,
  organization_id uuid not null references public.organizations(id),
  user_id uuid not null references auth.users(id),
  role_id uuid references public.app_roles(id),
  member_status text not null,
  unique (user_id, organization_id)
);

create table public.role_permissions (
  id uuid primary key,
  organization_id uuid not null references public.organizations(id),
  role_id uuid not null references public.app_roles(id),
  permission_id uuid not null references public.permissions(id)
);

create or replace function private.has_org_permission(p_organization_id uuid, p_permission_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.organization_members m
    join public.organizations o on o.id = m.organization_id
    join public.app_roles r on r.id = m.role_id and r.organization_id = m.organization_id and r.is_active
    join public.role_permissions rp on rp.role_id = r.id and rp.organization_id = r.organization_id
    join public.permissions p on p.id = rp.permission_id
    where m.organization_id = p_organization_id
      and m.user_id = auth.uid()
      and m.member_status = 'active'
      and o.status = 'active'
      and p.permission_key = p_permission_key
  );
$function$;

create table public.platform_modules (
  id uuid primary key,
  module_key text not null unique,
  is_active boolean not null,
  is_core boolean not null,
  current_version text not null
);

create table public.organization_modules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  module_id uuid not null references public.platform_modules(id),
  status text not null check (status in ('disabled','pending','active','suspended')),
  installed_version text,
  configuration jsonb not null default '{}'::jsonb,
  enabled_at timestamptz,
  disabled_at timestamptz,
  enabled_by uuid,
  updated_at timestamptz not null default now(),
  unique (organization_id, module_id)
);

create table public.module_dependencies (
  id uuid primary key,
  module_id uuid not null references public.platform_modules(id),
  depends_on_module_id uuid not null references public.platform_modules(id),
  is_mandatory boolean not null,
  minimum_version text,
  check (module_id <> depends_on_module_id),
  unique (module_id, depends_on_module_id)
);

create table public.approval_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  requested_by uuid not null,
  request_type text not null,
  target_type text not null,
  target_id uuid,
  request_payload jsonb not null default '{}'::jsonb,
  reason text not null,
  status text not null default 'pending'
    check (status in ('pending','approved','rejected','cancelled','expired')),
  required_approvals integer not null default 1 check (required_approvals > 0),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  unique (id, organization_id),
  foreign key (requested_by, organization_id)
    references public.organization_members(user_id, organization_id)
);

create table public.approval_actions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  approval_request_id uuid not null,
  actor_user_id uuid not null,
  decision text not null check (decision in ('approved','rejected')),
  comment text,
  created_at timestamptz not null default now(),
  unique (approval_request_id, actor_user_id),
  foreign key (approval_request_id, organization_id)
    references public.approval_requests(id, organization_id),
  foreign key (actor_user_id, organization_id)
    references public.organization_members(user_id, organization_id)
);

create table public.module_change_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  module_id uuid not null references public.platform_modules(id),
  request_type text not null check (request_type in ('enable','disable','upgrade','configure')),
  requested_by uuid not null,
  current_configuration jsonb not null default '{}'::jsonb,
  proposed_configuration jsonb not null default '{}'::jsonb,
  reason text not null,
  approval_request_id uuid,
  status text not null default 'pending'
    check (status in ('pending','approved','rejected','cancelled','completed')),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (approval_request_id),
  unique (id, organization_id),
  foreign key (approval_request_id, organization_id)
    references public.approval_requests(id, organization_id),
  foreign key (requested_by, organization_id)
    references public.organization_members(user_id, organization_id)
);

create table public.module_audit_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid,
  branch_id uuid,
  actor_user_id uuid,
  action text not null,
  resource_type text not null,
  resource_id uuid,
  old_values jsonb,
  new_values jsonb,
  approval_request_id uuid,
  request_id text,
  ip_address inet,
  user_agent text,
  created_at timestamptz not null default now()
);

-- Seed one organization, four users, one non-core active module and scoped permissions.
insert into public.organizations(id,status)
values ('00000000-0000-0000-0000-000000000001','active');

insert into auth.users(id) values
  ('00000000-0000-0000-0000-000000000101'),
  ('00000000-0000-0000-0000-000000000102'),
  ('00000000-0000-0000-0000-000000000103'),
  ('00000000-0000-0000-0000-000000000104');

insert into public.app_roles(id,organization_id,role_key,is_active) values
  ('00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000001','requester',true),
  ('00000000-0000-0000-0000-000000000202','00000000-0000-0000-0000-000000000001','approver',true),
  ('00000000-0000-0000-0000-000000000203','00000000-0000-0000-0000-000000000001','module_applier',true),
  ('00000000-0000-0000-0000-000000000204','00000000-0000-0000-0000-000000000001','observer',true);

insert into public.organization_members(id,organization_id,user_id,role_id,member_status) values
  ('00000000-0000-0000-0000-000000000211','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000201','active'),
  ('00000000-0000-0000-0000-000000000212','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000102','00000000-0000-0000-0000-000000000202','active'),
  ('00000000-0000-0000-0000-000000000213','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000103','00000000-0000-0000-0000-000000000203','active'),
  ('00000000-0000-0000-0000-000000000214','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000104','00000000-0000-0000-0000-000000000204','active');

insert into public.permissions(id,permission_key,description,module_key) values
  ('00000000-0000-0000-0000-000000000401','module.request','Request module changes','module_registry'),
  ('00000000-0000-0000-0000-000000000402','approval.approve','Approve/reject requests','approval_governance'),
  ('00000000-0000-0000-0000-000000000403','module.manage','Apply approved module changes','module_registry'),
  ('00000000-0000-0000-0000-000000000404','module.read','Read module status','module_registry');

insert into public.role_permissions(id,organization_id,role_id,permission_id) values
  ('00000000-0000-0000-0000-000000000501','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000401'),
  ('00000000-0000-0000-0000-000000000502','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000402'),
  ('00000000-0000-0000-0000-000000000503','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000202','00000000-0000-0000-0000-000000000402'),
  ('00000000-0000-0000-0000-000000000504','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000203','00000000-0000-0000-0000-000000000403'),
  ('00000000-0000-0000-0000-000000000505','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000203','00000000-0000-0000-0000-000000000404'),
  ('00000000-0000-0000-0000-000000000506','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000204','00000000-0000-0000-0000-000000000404');

insert into public.platform_modules(id,module_key,is_active,is_core,current_version)
values
 ('00000000-0000-0000-0000-000000000301','test_sales_module',true,false,'1.0.0'),
 ('00000000-0000-0000-0000-000000000302','test_dependency_module',true,false,'1.0.0');

insert into public.module_dependencies(id,module_id,depends_on_module_id,minimum_version,is_mandatory)
values (
 '00000000-0000-0000-0000-000000000303',
 '00000000-0000-0000-0000-000000000301',
 '00000000-0000-0000-0000-000000000302',
 '1.0.0',
 true
);

insert into public.organization_modules(
  id,organization_id,module_id,status,installed_version,configuration,enabled_at,enabled_by
) values (
  '00000000-0000-0000-0000-000000000311',
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000301',
  'active','1.0.0','{}'::jsonb,now(),'00000000-0000-0000-0000-000000000101'
);

-- Model the legacy API bypass so the separate cutover draft can assert its revocation.
create or replace function private.branch_module_set_enabled(uuid, boolean, text)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  return;
end;
$function$;

create or replace function public.branch_module_set_enabled(uuid, boolean, text)
returns void
language sql
security invoker
set search_path = ''
as $function$
  select private.branch_module_set_enabled($1, $2, $3);
$function$;

grant usage on schema private to authenticated, service_role;
grant execute on function private.branch_module_set_enabled(uuid, boolean, text)
  to authenticated, service_role;
grant execute on function public.branch_module_set_enabled(uuid, boolean, text)
  to authenticated, service_role;
