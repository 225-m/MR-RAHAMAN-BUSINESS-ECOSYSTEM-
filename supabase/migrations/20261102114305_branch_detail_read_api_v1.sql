CREATE OR REPLACE FUNCTION public.branch_detail_v1(
 p_organization_id uuid,p_branch_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path=pg_catalog,public,private,auth
AS $$
DECLARE v_result jsonb;
BEGIN
 IF auth.uid() IS NULL
  OR NOT private.is_org_member(p_organization_id)
  OR NOT private.has_org_permission(p_organization_id,'branch.read')
  OR NOT private.has_branch_access(p_organization_id,p_branch_id,'branch.read') THEN
  RAISE EXCEPTION 'Branch read access required' USING ERRCODE='42501';
 END IF;

 SELECT jsonb_build_object(
  'branch',to_jsonb(v),
  'profile',(SELECT to_jsonb(p) FROM public.branch_profiles p
    WHERE p.organization_id=p_organization_id AND p.branch_id=p_branch_id),
  'operating_hours',COALESCE((SELECT jsonb_agg(to_jsonb(h) ORDER BY h.day_of_week)
    FROM public.branch_operating_hours h
    WHERE h.organization_id=p_organization_id AND h.branch_id=p_branch_id),'[]'::jsonb),
  'contacts',COALESCE((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.is_primary DESC,c.contact_type,c.contact_name)
    FROM public.branch_contacts c
    WHERE c.organization_id=p_organization_id AND c.branch_id=p_branch_id AND c.is_active=true),'[]'::jsonb),
  'settings',COALESCE((SELECT jsonb_object_agg(s.setting_key,s.setting_value)
    FROM public.branch_settings s
    WHERE s.organization_id=p_organization_id AND s.branch_id=p_branch_id),'{}'::jsonb)
 )
 INTO v_result
 FROM public.branch_overview_v1 v
 WHERE v.organization_id=p_organization_id AND v.id=p_branch_id;

 IF v_result IS NULL THEN RAISE EXCEPTION 'Branch not found'; END IF;
 RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.branch_detail_v1(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.branch_detail_v1(uuid,uuid) TO authenticated;

