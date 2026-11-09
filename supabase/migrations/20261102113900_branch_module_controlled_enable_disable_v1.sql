BEGIN;

CREATE OR REPLACE FUNCTION private.branch_module_set_enabled(
 p_organization_id uuid,p_enabled boolean,p_reason text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,public,private,auth
AS $$
DECLARE v_module_id uuid; v_old_status text; v_org_module_id uuid;
BEGIN
 IF auth.uid() IS NULL OR NOT private.has_org_permission(p_organization_id,'module.manage') THEN
  RAISE EXCEPTION 'Module management permission required' USING ERRCODE='42501';
 END IF;
 IF length(trim(coalesce(p_reason,'')))<5 THEN
  RAISE EXCEPTION 'A reason of at least 5 characters is required';
 END IF;
 SELECT id INTO v_module_id FROM public.platform_modules
 WHERE module_key='branch_management' AND is_active=true;
 IF v_module_id IS NULL THEN RAISE EXCEPTION 'Branch Management is not available on this platform'; END IF;
 IF p_enabled AND EXISTS (
  SELECT 1 FROM public.module_dependencies d
  JOIN public.platform_modules required ON required.id=d.depends_on_module_id
  LEFT JOIN public.organization_modules om
    ON om.organization_id=p_organization_id AND om.module_id=required.id AND om.status='active'
  WHERE d.module_id=v_module_id AND d.is_mandatory=true AND om.id IS NULL
 ) THEN
  RAISE EXCEPTION 'A mandatory module dependency is not enabled';
 END IF;
 SELECT id,status INTO v_org_module_id,v_old_status
 FROM public.organization_modules
 WHERE organization_id=p_organization_id AND module_id=v_module_id
 FOR UPDATE;
 IF v_org_module_id IS NULL THEN
  INSERT INTO public.organization_modules(organization_id,module_id,status,installed_version,enabled_at,enabled_by)
  VALUES(p_organization_id,v_module_id,CASE WHEN p_enabled THEN 'active' ELSE 'disabled' END,
   (SELECT current_version FROM public.platform_modules WHERE id=v_module_id),
   CASE WHEN p_enabled THEN now() ELSE NULL END,
   CASE WHEN p_enabled THEN auth.uid() ELSE NULL END);
 ELSE
  UPDATE public.organization_modules SET
   status=CASE WHEN p_enabled THEN 'active' ELSE 'disabled' END,
   installed_version=CASE WHEN p_enabled THEN (SELECT current_version FROM public.platform_modules WHERE id=v_module_id) ELSE installed_version END,
   enabled_at=CASE WHEN p_enabled THEN now() ELSE enabled_at END,
   disabled_at=CASE WHEN p_enabled THEN NULL ELSE now() END,
   enabled_by=CASE WHEN p_enabled THEN auth.uid() ELSE enabled_by END
  WHERE id=v_org_module_id;
 END IF;
 INSERT INTO public.module_audit_logs(organization_id,actor_user_id,action,resource_type,resource_id,old_values,new_values)
 VALUES(p_organization_id,auth.uid(),CASE WHEN p_enabled THEN 'branch.module_enabled' ELSE 'branch.module_disabled' END,
  'platform_module',v_module_id,jsonb_build_object('status',v_old_status),
  jsonb_build_object('status',CASE WHEN p_enabled THEN 'active' ELSE 'disabled' END,'reason',trim(p_reason)));
END;
$$;
REVOKE ALL ON FUNCTION private.branch_module_set_enabled(uuid,boolean,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION private.branch_module_set_enabled(uuid,boolean,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.branch_module_set_enabled(
 p_organization_id uuid,p_enabled boolean,p_reason text
)
RETURNS void LANGUAGE sql SECURITY INVOKER
SET search_path=pg_catalog,public,private,auth
AS $$ SELECT private.branch_module_set_enabled(p_organization_id,p_enabled,p_reason); $$;
REVOKE ALL ON FUNCTION public.branch_module_set_enabled(uuid,boolean,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.branch_module_set_enabled(uuid,boolean,text) TO authenticated;

COMMIT;

