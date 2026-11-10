CREATE OR REPLACE FUNCTION public.branch_audit_list_v1(
 p_organization_id uuid,p_branch_id uuid,
 p_limit integer DEFAULT 50,p_before timestamptz DEFAULT NULL
)
RETURNS TABLE(
 id uuid,action text,resource_type text,resource_id uuid,
 actor_user_id uuid,old_values jsonb,new_values jsonb,created_at timestamptz
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path=pg_catalog,public,private,auth
AS $$
BEGIN
 IF auth.uid() IS NULL
  OR NOT private.is_org_member(p_organization_id)
  OR NOT private.has_org_permission(p_organization_id,'audit.read')
  OR NOT private.has_branch_access(p_organization_id,p_branch_id,'audit.read') THEN
  RAISE EXCEPTION 'Branch audit read permission required' USING ERRCODE='42501';
 END IF;

 RETURN QUERY
 SELECT l.id,l.action,l.resource_type,l.resource_id,l.actor_user_id,
        l.old_values,l.new_values,l.created_at
 FROM public.module_audit_logs l
 WHERE l.organization_id=p_organization_id
   AND l.branch_id=p_branch_id
   AND (p_before IS NULL OR l.created_at<p_before)
 ORDER BY l.created_at DESC,l.id DESC
 LIMIT LEAST(GREATEST(coalesce(p_limit,50),1),100);
END;
$$;
REVOKE ALL ON FUNCTION public.branch_audit_list_v1(uuid,uuid,integer,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.branch_audit_list_v1(uuid,uuid,integer,timestamptz) TO authenticated;

