BEGIN;

CREATE OR REPLACE FUNCTION private.branch_update_contact(
 p_organization_id uuid,p_branch_id uuid,p_contact_id uuid,
 p_contact_type text,p_contact_name text,p_phone text,p_email text,p_is_primary boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,public,private,auth
AS $$
DECLARE v_old jsonb; v_new jsonb;
BEGIN
 IF auth.uid() IS NULL
  OR NOT private.has_org_permission(p_organization_id,'branch.contact.manage')
  OR NOT private.has_branch_access(p_organization_id,p_branch_id,'branch.manage') THEN
  RAISE EXCEPTION 'Branch contact permission required' USING ERRCODE='42501';
 END IF;
 IF p_contact_type NOT IN ('general','manager','accounts','operations','emergency','other')
    OR length(trim(coalesce(p_contact_name,'')))=0 THEN
  RAISE EXCEPTION 'Valid contact type and contact name are required';
 END IF;

 SELECT jsonb_build_object('contact_type',contact_type,'contact_name',contact_name,
   'phone',phone,'email',email,'is_primary',is_primary,'is_active',is_active)
 INTO v_old
 FROM public.branch_contacts
 WHERE id=p_contact_id AND organization_id=p_organization_id AND branch_id=p_branch_id
 FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Branch contact not found'; END IF;

 IF coalesce(p_is_primary,false) THEN
  UPDATE public.branch_contacts SET is_primary=false
  WHERE organization_id=p_organization_id AND branch_id=p_branch_id
    AND contact_type=p_contact_type AND is_active=true AND id<>p_contact_id;
 END IF;

 UPDATE public.branch_contacts SET
  contact_type=p_contact_type,contact_name=trim(p_contact_name),
  phone=nullif(trim(p_phone),''),email=nullif(trim(p_email),''),
  is_primary=coalesce(p_is_primary,false) AND is_active
 WHERE id=p_contact_id AND organization_id=p_organization_id AND branch_id=p_branch_id;

 v_new:=jsonb_build_object('contact_type',p_contact_type,'contact_name',trim(p_contact_name),
   'phone',nullif(trim(p_phone),''),'email',nullif(trim(p_email),''),
   'is_primary',coalesce(p_is_primary,false));
 INSERT INTO public.module_audit_logs(organization_id,branch_id,actor_user_id,action,
  resource_type,resource_id,old_values,new_values)
 VALUES(p_organization_id,p_branch_id,auth.uid(),'branch.contact_updated',
  'branch_contact',p_contact_id,v_old,v_new);
END;
$$;
REVOKE ALL ON FUNCTION private.branch_update_contact(uuid,uuid,uuid,text,text,text,text,boolean) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.branch_update_contact(
 p_organization_id uuid,p_branch_id uuid,p_contact_id uuid,
 p_contact_type text,p_contact_name text,p_phone text,p_email text,p_is_primary boolean
)
RETURNS void
LANGUAGE sql
SECURITY INVOKER
SET search_path=pg_catalog,public,private,auth
AS $$
 SELECT private.branch_update_contact($1,$2,$3,$4,$5,$6,$7,$8);
$$;
REVOKE ALL ON FUNCTION public.branch_update_contact(uuid,uuid,uuid,text,text,text,text,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.branch_update_contact(uuid,uuid,uuid,text,text,text,text,boolean) TO authenticated;

COMMIT;

