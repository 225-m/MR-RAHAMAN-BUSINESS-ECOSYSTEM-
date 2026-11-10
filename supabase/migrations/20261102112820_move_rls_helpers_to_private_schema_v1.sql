BEGIN;

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA private TO authenticated;

CREATE OR REPLACE FUNCTION private.is_org_member(p_organization_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
 SELECT EXISTS (
  SELECT 1 FROM public.organization_members m
  JOIN public.organizations o ON o.id=m.organization_id
  WHERE m.organization_id=p_organization_id AND m.user_id=auth.uid()
    AND m.member_status='active' AND o.status='active'
 );
$$;

CREATE OR REPLACE FUNCTION private.has_org_permission(p_organization_id uuid,p_permission_key text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
 SELECT EXISTS (
  SELECT 1 FROM public.organization_members m
  JOIN public.organizations o ON o.id=m.organization_id
  JOIN public.app_roles r ON r.id=m.role_id AND r.organization_id=m.organization_id AND r.is_active=true
  JOIN public.role_permissions rp ON rp.role_id=r.id AND rp.organization_id=r.organization_id
  JOIN public.permissions p ON p.id=rp.permission_id
  WHERE m.organization_id=p_organization_id AND m.user_id=auth.uid()
    AND m.member_status='active' AND o.status='active' AND p.permission_key=p_permission_key
 );
$$;

CREATE OR REPLACE FUNCTION private.has_branch_access(p_organization_id uuid,p_branch_id uuid,p_permission_key text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
 SELECT private.has_org_permission(p_organization_id,p_permission_key)
 AND EXISTS (
  SELECT 1 FROM public.member_branch_access a
  WHERE a.organization_id=p_organization_id AND a.branch_id=p_branch_id AND a.user_id=auth.uid()
 );
$$;

REVOKE ALL ON FUNCTION private.is_org_member(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.has_org_permission(uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.has_branch_access(uuid,uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.is_org_member(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.has_org_permission(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.has_branch_access(uuid,uuid,text) TO authenticated;

DROP POLICY organizations_member_read ON public.organizations;
DROP POLICY branches_scoped_read ON public.branches;
DROP POLICY app_roles_member_read ON public.app_roles;
DROP POLICY organization_members_scoped_read ON public.organization_members;
DROP POLICY organization_invitations_scoped_read ON public.organization_invitations;
DROP POLICY role_permissions_scoped_read ON public.role_permissions;
DROP POLICY member_branch_access_scoped_read ON public.member_branch_access;
DROP POLICY organization_modules_scoped_read ON public.organization_modules;
DROP POLICY approval_requests_scoped_read ON public.approval_requests;
DROP POLICY module_change_requests_scoped_read ON public.module_change_requests;
DROP POLICY approval_actions_scoped_read ON public.approval_actions;
DROP POLICY module_audit_logs_scoped_read ON public.module_audit_logs;

DROP FUNCTION public.is_org_member(uuid);
DROP FUNCTION public.has_org_permission(uuid,text);
DROP FUNCTION public.has_branch_access(uuid,uuid,text);

CREATE POLICY organizations_member_read ON public.organizations
 FOR SELECT TO authenticated USING (private.is_org_member(id));
CREATE POLICY branches_scoped_read ON public.branches
 FOR SELECT TO authenticated USING (private.has_branch_access(organization_id,id,'branch.read'));
CREATE POLICY app_roles_member_read ON public.app_roles
 FOR SELECT TO authenticated USING (private.is_org_member(organization_id) AND private.has_org_permission(organization_id,'role.read'));
CREATE POLICY organization_members_scoped_read ON public.organization_members
 FOR SELECT TO authenticated USING (private.is_org_member(organization_id) AND private.has_org_permission(organization_id,'member.read'));
CREATE POLICY organization_invitations_scoped_read ON public.organization_invitations
 FOR SELECT TO authenticated USING (private.is_org_member(organization_id) AND private.has_org_permission(organization_id,'member.invite'));
CREATE POLICY role_permissions_scoped_read ON public.role_permissions
 FOR SELECT TO authenticated USING (private.is_org_member(organization_id) AND private.has_org_permission(organization_id,'role.read'));
CREATE POLICY member_branch_access_scoped_read ON public.member_branch_access
 FOR SELECT TO authenticated USING (private.is_org_member(organization_id) AND private.has_org_permission(organization_id,'branch.access.read'));
CREATE POLICY organization_modules_scoped_read ON public.organization_modules
 FOR SELECT TO authenticated USING (private.is_org_member(organization_id) AND private.has_org_permission(organization_id,'module.read'));
CREATE POLICY approval_requests_scoped_read ON public.approval_requests
 FOR SELECT TO authenticated USING (private.is_org_member(organization_id) AND private.has_org_permission(organization_id,'approval.read'));
CREATE POLICY module_change_requests_scoped_read ON public.module_change_requests
 FOR SELECT TO authenticated USING (private.is_org_member(organization_id) AND private.has_org_permission(organization_id,'module.read'));
CREATE POLICY approval_actions_scoped_read ON public.approval_actions
 FOR SELECT TO authenticated USING (private.is_org_member(organization_id) AND private.has_org_permission(organization_id,'approval.read'));
CREATE POLICY module_audit_logs_scoped_read ON public.module_audit_logs
 FOR SELECT TO authenticated USING (
  organization_id IS NOT NULL AND private.is_org_member(organization_id)
  AND private.has_org_permission(organization_id,'audit.read')
  AND (branch_id IS NULL OR private.has_branch_access(organization_id,branch_id,'audit.read'))
 );

COMMIT;

