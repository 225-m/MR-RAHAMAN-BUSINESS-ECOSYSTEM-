BEGIN;
CREATE OR REPLACE FUNCTION private.has_branch_access(
 p_organization_id uuid,p_branch_id uuid,p_permission_key text
)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,auth
AS $$
 SELECT private.has_org_permission(p_organization_id,p_permission_key)
 AND EXISTS (
  SELECT 1 FROM public.member_branch_access a
  WHERE a.organization_id=p_organization_id AND a.branch_id=p_branch_id
    AND a.user_id=auth.uid() AND a.revoked_at IS NULL
 );
$$;

CREATE INDEX IF NOT EXISTS branch_contacts_branch_org_fk_idx ON public.branch_contacts(branch_id,organization_id);
CREATE INDEX IF NOT EXISTS branch_contacts_org_fk_idx ON public.branch_contacts(organization_id);
CREATE INDEX IF NOT EXISTS branch_hours_branch_org_fk_idx ON public.branch_operating_hours(branch_id,organization_id);
CREATE INDEX IF NOT EXISTS branch_hours_org_fk_idx ON public.branch_operating_hours(organization_id);
CREATE INDEX IF NOT EXISTS branch_settings_branch_org_fk_idx ON public.branch_settings(branch_id,organization_id);
CREATE INDEX IF NOT EXISTS branch_settings_updated_by_fk_idx ON public.branch_settings(updated_by);
CREATE INDEX IF NOT EXISTS branch_settings_org_fk_idx ON public.branch_settings(organization_id);
COMMIT;

