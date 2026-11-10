BEGIN;

CREATE OR REPLACE FUNCTION private.touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION private.touch_updated_at() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER organizations_touch_updated_at
BEFORE UPDATE ON public.organizations
FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER branches_touch_updated_at
BEFORE UPDATE ON public.branches
FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER app_roles_touch_updated_at
BEFORE UPDATE ON public.app_roles
FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER organization_members_touch_updated_at
BEFORE UPDATE ON public.organization_members
FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER platform_modules_touch_updated_at
BEFORE UPDATE ON public.platform_modules
FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER organization_modules_touch_updated_at
BEFORE UPDATE ON public.organization_modules
FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();

CREATE OR REPLACE FUNCTION private.reject_audit_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $$
BEGIN
  RAISE EXCEPTION 'module_audit_logs is append-only; UPDATE and DELETE are prohibited'
    USING ERRCODE = '42501';
END;
$$;
REVOKE ALL ON FUNCTION private.reject_audit_mutation() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER module_audit_logs_append_only
BEFORE UPDATE OR DELETE ON public.module_audit_logs
FOR EACH ROW EXECUTE FUNCTION private.reject_audit_mutation();

-- Cover foreign-key lookup paths flagged by Supabase's performance advisor.
CREATE INDEX approval_actions_actor_org_fk_idx ON public.approval_actions(actor_user_id, organization_id);
CREATE INDEX approval_actions_request_org_fk_idx ON public.approval_actions(approval_request_id, organization_id);
CREATE INDEX approval_requests_requester_org_fk_idx ON public.approval_requests(requested_by, organization_id);
CREATE INDEX branches_created_by_fk_idx ON public.branches(created_by);
CREATE INDEX member_branch_access_branch_org_fk_idx ON public.member_branch_access(branch_id, organization_id);
CREATE INDEX member_branch_access_granted_by_fk_idx ON public.member_branch_access(granted_by);
CREATE INDEX member_branch_access_member_org_fk_idx ON public.member_branch_access(user_id, organization_id);
CREATE INDEX module_audit_logs_approval_org_fk_idx ON public.module_audit_logs(approval_request_id, organization_id);
CREATE INDEX module_audit_logs_branch_org_fk_idx ON public.module_audit_logs(branch_id, organization_id);
CREATE INDEX module_change_requests_approval_org_fk_idx ON public.module_change_requests(approval_request_id, organization_id);
CREATE INDEX module_change_requests_requester_org_fk_idx ON public.module_change_requests(requested_by, organization_id);
CREATE INDEX module_change_requests_module_fk_idx ON public.module_change_requests(module_id);
CREATE INDEX organization_invitations_accepted_by_fk_idx ON public.organization_invitations(accepted_by);
CREATE INDEX organization_invitations_invited_by_fk_idx ON public.organization_invitations(invited_by);
CREATE INDEX organization_invitations_role_org_fk_idx ON public.organization_invitations(role_id, organization_id);
CREATE INDEX organization_members_invited_by_fk_idx ON public.organization_members(invited_by);
CREATE INDEX organization_members_role_org_fk_idx ON public.organization_members(role_id, organization_id);
CREATE INDEX organization_modules_enabled_by_fk_idx ON public.organization_modules(enabled_by);
CREATE INDEX organization_modules_module_fk_idx ON public.organization_modules(module_id);
CREATE INDEX organizations_created_by_fk_idx ON public.organizations(created_by);
CREATE INDEX permissions_module_key_fk_idx ON public.permissions(module_key);
CREATE INDEX platform_admin_roles_granted_by_fk_idx ON public.platform_admin_roles(granted_by);
CREATE INDEX role_permissions_permission_fk_idx ON public.role_permissions(permission_id);
CREATE INDEX role_permissions_role_org_fk_idx ON public.role_permissions(role_id, organization_id);

COMMIT;

