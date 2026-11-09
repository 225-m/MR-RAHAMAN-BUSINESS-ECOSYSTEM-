BEGIN;

CREATE TABLE public.organizations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_key text NOT NULL UNIQUE,
  name text NOT NULL,
  legal_name text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','active','suspended','closed')),
  timezone text NOT NULL DEFAULT 'Asia/Dhaka',
  currency_code text NOT NULL DEFAULT 'BDT' CHECK (currency_code ~ '^[A-Z]{3}$'),
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.branches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  branch_code text NOT NULL,
  name text NOT NULL,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive','suspended')),
  address jsonb NOT NULL DEFAULT '{}'::jsonb,
  phone text,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, branch_code),
  UNIQUE (id, organization_id)
);

CREATE TABLE public.app_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  role_key text NOT NULL,
  role_name text NOT NULL,
  description text,
  is_system boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, role_key),
  UNIQUE (id, organization_id)
);

CREATE TABLE public.permissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  permission_key text NOT NULL UNIQUE,
  description text,
  module_key text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.organization_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  role_id uuid,
  member_status text NOT NULL DEFAULT 'invited' CHECK (member_status IN ('invited','active','suspended','removed')),
  invited_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  joined_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, user_id),
  UNIQUE (user_id, organization_id),
  UNIQUE (id, organization_id),
  CHECK (member_status <> 'active' OR role_id IS NOT NULL),
  CONSTRAINT organization_members_role_fk
    FOREIGN KEY (role_id, organization_id) REFERENCES public.app_roles(id, organization_id) ON DELETE RESTRICT
);

CREATE TABLE public.organization_invitations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  email text NOT NULL,
  role_id uuid,
  token_hash text NOT NULL UNIQUE,
  invitation_status text NOT NULL DEFAULT 'pending' CHECK (invitation_status IN ('pending','accepted','revoked','expired')),
  invited_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  accepted_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  expires_at timestamptz NOT NULL,
  accepted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT organization_invitations_role_fk
    FOREIGN KEY (role_id, organization_id) REFERENCES public.app_roles(id, organization_id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX organization_invitations_one_pending_per_email_idx
  ON public.organization_invitations(organization_id, lower(email))
  WHERE invitation_status = 'pending';

CREATE TABLE public.role_permissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  role_id uuid NOT NULL,
  permission_id uuid NOT NULL REFERENCES public.permissions(id) ON DELETE RESTRICT,
  granted_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (role_id, permission_id),
  CONSTRAINT role_permissions_role_fk
    FOREIGN KEY (role_id, organization_id) REFERENCES public.app_roles(id, organization_id) ON DELETE CASCADE
);

CREATE TABLE public.member_branch_access (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL,
  branch_id uuid NOT NULL,
  access_level text NOT NULL DEFAULT 'standard' CHECK (access_level IN ('read','standard','manager')),
  granted_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, user_id, branch_id),
  CONSTRAINT member_branch_access_member_fk
    FOREIGN KEY (user_id, organization_id) REFERENCES public.organization_members(user_id, organization_id) ON DELETE CASCADE,
  CONSTRAINT member_branch_access_branch_fk
    FOREIGN KEY (branch_id, organization_id) REFERENCES public.branches(id, organization_id) ON DELETE CASCADE
);

CREATE TABLE public.platform_modules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  module_key text NOT NULL UNIQUE,
  module_name text NOT NULL,
  description text,
  category text NOT NULL,
  current_version text NOT NULL DEFAULT '1.0.0',
  min_platform_version text,
  is_core boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  configuration_schema jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.permissions
  ADD CONSTRAINT permissions_module_key_fk
  FOREIGN KEY (module_key) REFERENCES public.platform_modules(module_key) ON DELETE RESTRICT;

CREATE TABLE public.module_dependencies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  module_id uuid NOT NULL REFERENCES public.platform_modules(id) ON DELETE CASCADE,
  depends_on_module_id uuid NOT NULL REFERENCES public.platform_modules(id) ON DELETE RESTRICT,
  minimum_version text,
  is_mandatory boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (module_id <> depends_on_module_id),
  UNIQUE (module_id, depends_on_module_id)
);

CREATE TABLE public.organization_modules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  module_id uuid NOT NULL REFERENCES public.platform_modules(id) ON DELETE RESTRICT,
  status text NOT NULL DEFAULT 'disabled' CHECK (status IN ('disabled','pending','active','suspended')),
  installed_version text,
  configuration jsonb NOT NULL DEFAULT '{}'::jsonb,
  enabled_at timestamptz,
  disabled_at timestamptz,
  enabled_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, module_id),
  UNIQUE (id, organization_id)
);

CREATE TABLE public.approval_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  requested_by uuid NOT NULL,
  request_type text NOT NULL,
  target_type text NOT NULL,
  target_id uuid,
  request_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  reason text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','cancelled','expired')),
  required_approvals integer NOT NULL DEFAULT 1 CHECK (required_approvals > 0),
  expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  UNIQUE (id, organization_id),
  CONSTRAINT approval_requests_requester_fk
    FOREIGN KEY (requested_by, organization_id) REFERENCES public.organization_members(user_id, organization_id) ON DELETE RESTRICT
);

CREATE TABLE public.module_change_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  module_id uuid NOT NULL REFERENCES public.platform_modules(id) ON DELETE RESTRICT,
  request_type text NOT NULL CHECK (request_type IN ('enable','disable','upgrade','configure')),
  requested_by uuid NOT NULL,
  current_configuration jsonb NOT NULL DEFAULT '{}'::jsonb,
  proposed_configuration jsonb NOT NULL DEFAULT '{}'::jsonb,
  reason text NOT NULL,
  approval_request_id uuid UNIQUE,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','cancelled','completed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  UNIQUE (id, organization_id),
  CONSTRAINT module_change_requester_fk
    FOREIGN KEY (requested_by, organization_id) REFERENCES public.organization_members(user_id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT module_change_approval_fk
    FOREIGN KEY (approval_request_id, organization_id) REFERENCES public.approval_requests(id, organization_id) ON DELETE RESTRICT
);

CREATE TABLE public.approval_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  approval_request_id uuid NOT NULL,
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  decision text NOT NULL CHECK (decision IN ('approved','rejected')),
  comment text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (approval_request_id, actor_user_id),
  CONSTRAINT approval_actions_request_fk
    FOREIGN KEY (approval_request_id, organization_id) REFERENCES public.approval_requests(id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT approval_actions_org_member_fk
    FOREIGN KEY (actor_user_id, organization_id) REFERENCES public.organization_members(user_id, organization_id) ON DELETE RESTRICT
);

CREATE TABLE public.platform_admin_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  role_key text NOT NULL CHECK (role_key IN ('platform_owner','platform_admin','security_admin','support_admin')),
  granted_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  granted_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX platform_admin_roles_one_active_idx
  ON public.platform_admin_roles(user_id, role_key)
  WHERE revoked_at IS NULL;

CREATE UNIQUE INDEX platform_admin_roles_single_active_owner_idx
  ON public.platform_admin_roles(role_key)
  WHERE role_key = 'platform_owner' AND revoked_at IS NULL;

CREATE TABLE public.module_audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid REFERENCES public.organizations(id) ON DELETE RESTRICT,
  branch_id uuid,
  actor_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  action text NOT NULL,
  resource_type text NOT NULL,
  resource_id uuid,
  old_values jsonb,
  new_values jsonb,
  approval_request_id uuid,
  request_id text,
  ip_address inet,
  user_agent text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (branch_id IS NULL OR organization_id IS NOT NULL),
  CONSTRAINT module_audit_branch_fk
    FOREIGN KEY (branch_id, organization_id) REFERENCES public.branches(id, organization_id) ON DELETE RESTRICT,
  CONSTRAINT module_audit_approval_fk
    FOREIGN KEY (approval_request_id, organization_id) REFERENCES public.approval_requests(id, organization_id) ON DELETE RESTRICT
);

CREATE INDEX branches_org_status_idx ON public.branches(organization_id, status);
CREATE INDEX organization_members_user_status_idx ON public.organization_members(user_id, member_status);
CREATE INDEX organization_invitations_org_status_idx ON public.organization_invitations(organization_id, invitation_status);
CREATE INDEX role_permissions_org_role_idx ON public.role_permissions(organization_id, role_id);
CREATE INDEX member_branch_access_user_idx ON public.member_branch_access(organization_id, user_id);
CREATE INDEX module_dependencies_dependency_idx ON public.module_dependencies(depends_on_module_id);
CREATE INDEX organization_modules_org_status_idx ON public.organization_modules(organization_id, status);
CREATE INDEX approval_requests_org_status_created_idx ON public.approval_requests(organization_id, status, created_at DESC);
CREATE INDEX module_change_requests_org_status_idx ON public.module_change_requests(organization_id, status);
CREATE INDEX approval_actions_org_request_idx ON public.approval_actions(organization_id, approval_request_id);
CREATE INDEX module_audit_logs_org_created_idx ON public.module_audit_logs(organization_id, created_at DESC);
CREATE INDEX module_audit_logs_actor_created_idx ON public.module_audit_logs(actor_user_id, created_at DESC);

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.member_branch_access ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_modules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.module_dependencies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_modules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.approval_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.module_change_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.approval_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_admin_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.module_audit_logs ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE
  public.organizations, public.branches, public.app_roles, public.permissions,
  public.organization_members, public.organization_invitations, public.role_permissions,
  public.member_branch_access, public.platform_modules, public.module_dependencies,
  public.organization_modules, public.approval_requests, public.module_change_requests,
  public.approval_actions, public.platform_admin_roles, public.module_audit_logs
FROM PUBLIC, anon, authenticated;

COMMIT;

