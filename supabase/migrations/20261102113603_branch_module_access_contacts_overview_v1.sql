BEGIN;
ALTER TABLE public.member_branch_access
  ADD COLUMN revoked_at timestamptz;

CREATE OR REPLACE FUNCTION private.branch_assign_member_access(
 p_organization_id uuid,p_branch_id uuid,p_user_id uuid,p_access_level text
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,private,auth
AS $$
DECLARE v_id uuid;
BEGIN
 IF auth.uid() IS NULL OR NOT private.has_org_permission(p_organization_id,'branch.access.manage')
 OR NOT private.has_branch_access(p_organization_id,p_branch_id,'branch.access.manage') THEN
  RAISE EXCEPTION 'Branch access management permission required' USING ERRCODE='42501';
 END IF;
 IF p_access_level NOT IN ('read','standard','manager') THEN RAISE EXCEPTION 'Invalid access level'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.organization_members
  WHERE organization_id=p_organization_id AND user_id=p_user_id AND member_status='active') THEN
  RAISE EXCEPTION 'Target user is not an active organization member';
 END IF;
 INSERT INTO public.member_branch_access(organization_id,user_id,branch_id,access_level,granted_by,revoked_at)
 VALUES(p_organization_id,p_user_id,p_branch_id,p_access_level,auth.uid(),NULL)
 ON CONFLICT(organization_id,user_id,branch_id) DO UPDATE
 SET access_level=EXCLUDED.access_level,granted_by=auth.uid(),revoked_at=NULL
 RETURNING id INTO v_id;
 INSERT INTO public.module_audit_logs(organization_id,branch_id,actor_user_id,action,resource_type,resource_id,new_values)
 VALUES(p_organization_id,p_branch_id,auth.uid(),'branch.access_granted','member_branch_access',v_id,
  jsonb_build_object('user_id',p_user_id,'access_level',p_access_level));
 RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION private.branch_revoke_member_access(
 p_organization_id uuid,p_branch_id uuid,p_user_id uuid,p_reason text
)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,private,auth
AS $$
DECLARE v_count integer;
BEGIN
 IF auth.uid() IS NULL OR NOT private.has_org_permission(p_organization_id,'branch.access.manage')
 OR NOT private.has_branch_access(p_organization_id,p_branch_id,'branch.access.manage') THEN
  RAISE EXCEPTION 'Branch access management permission required' USING ERRCODE='42501';
 END IF;
 IF length(trim(coalesce(p_reason,'')))<5 THEN RAISE EXCEPTION 'A reason of at least 5 characters is required'; END IF;
 UPDATE public.member_branch_access SET revoked_at=now()
 WHERE organization_id=p_organization_id AND branch_id=p_branch_id AND user_id=p_user_id
 AND revoked_at IS NULL;
 GET DIAGNOSTICS v_count=ROW_COUNT;
 IF v_count>0 THEN
  INSERT INTO public.module_audit_logs(organization_id,branch_id,actor_user_id,action,resource_type,new_values)
  VALUES(p_organization_id,p_branch_id,auth.uid(),'branch.access_revoked','member_branch_access',
   jsonb_build_object('user_id',p_user_id,'reason',trim(p_reason)));
 END IF;
 RETURN v_count>0;
END;
$$;

CREATE OR REPLACE FUNCTION private.branch_set_contact_status(
 p_organization_id uuid,p_branch_id uuid,p_contact_id uuid,p_is_active boolean
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,private,auth
AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT private.has_org_permission(p_organization_id,'branch.contact.manage')
 OR NOT private.has_branch_access(p_organization_id,p_branch_id,'branch.manage') THEN
  RAISE EXCEPTION 'Branch contact permission required' USING ERRCODE='42501';
 END IF;
 UPDATE public.branch_contacts SET is_active=p_is_active,is_primary=CASE WHEN p_is_active THEN is_primary ELSE false END
 WHERE id=p_contact_id AND branch_id=p_branch_id AND organization_id=p_organization_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Branch contact not found'; END IF;
 INSERT INTO public.module_audit_logs(organization_id,branch_id,actor_user_id,action,resource_type,resource_id,new_values)
 VALUES(p_organization_id,p_branch_id,auth.uid(),
  CASE WHEN p_is_active THEN 'branch.contact_activated' ELSE 'branch.contact_deactivated' END,
  'branch_contact',p_contact_id,jsonb_build_object('is_active',p_is_active));
END;
$$;

REVOKE ALL ON FUNCTION private.branch_assign_member_access(uuid,uuid,uuid,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION private.branch_revoke_member_access(uuid,uuid,uuid,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION private.branch_set_contact_status(uuid,uuid,uuid,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION private.branch_assign_member_access(uuid,uuid,uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.branch_revoke_member_access(uuid,uuid,uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.branch_set_contact_status(uuid,uuid,uuid,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.branch_assign_member_access(p_organization_id uuid,p_branch_id uuid,p_user_id uuid,p_access_level text)
RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog,public,private,auth
AS $$ SELECT private.branch_assign_member_access(p_organization_id,p_branch_id,p_user_id,p_access_level); $$;
CREATE OR REPLACE FUNCTION public.branch_revoke_member_access(p_organization_id uuid,p_branch_id uuid,p_user_id uuid,p_reason text)
RETURNS boolean LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog,public,private,auth
AS $$ SELECT private.branch_revoke_member_access(p_organization_id,p_branch_id,p_user_id,p_reason); $$;
CREATE OR REPLACE FUNCTION public.branch_set_contact_status(p_organization_id uuid,p_branch_id uuid,p_contact_id uuid,p_is_active boolean)
RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog,public,private,auth
AS $$ SELECT private.branch_set_contact_status(p_organization_id,p_branch_id,p_contact_id,p_is_active); $$;

REVOKE ALL ON FUNCTION public.branch_assign_member_access(uuid,uuid,uuid,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.branch_revoke_member_access(uuid,uuid,uuid,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.branch_set_contact_status(uuid,uuid,uuid,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.branch_assign_member_access(uuid,uuid,uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.branch_revoke_member_access(uuid,uuid,uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.branch_set_contact_status(uuid,uuid,uuid,boolean) TO authenticated;

CREATE OR REPLACE VIEW public.branch_overview_v1 WITH (security_invoker=true) AS
SELECT b.id,b.organization_id,b.branch_code,b.name,b.status,b.address,b.phone,b.created_at,b.updated_at,
 bp.branch_type,bp.manager_name,bp.manager_email,bp.daily_capacity,
 (SELECT count(*) FROM public.branch_contacts c WHERE c.branch_id=b.id AND c.is_active=true) AS active_contact_count,
 (SELECT count(*) FROM public.branch_operating_hours h WHERE h.branch_id=b.id) AS configured_days
FROM public.branches b LEFT JOIN public.branch_profiles bp ON bp.branch_id=b.id;
GRANT SELECT ON public.branch_overview_v1 TO authenticated;
COMMIT;

