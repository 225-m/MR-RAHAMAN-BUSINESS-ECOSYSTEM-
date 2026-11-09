BEGIN;

-- Give Branch its own lifecycle boundary in the platform registry.
INSERT INTO public.platform_modules
  (module_key,module_name,description,category,current_version,is_core)
VALUES
  ('branch_management','Branch Management','Branch directory, profile, contacts, operating hours, settings and access','core','1.0.0',true)
ON CONFLICT (module_key) DO UPDATE SET
  module_name=EXCLUDED.module_name,
  description=EXCLUDED.description,
  category=EXCLUDED.category,
  is_core=true,
  updated_at=now();

UPDATE public.permissions
SET module_key='branch_management'
WHERE permission_key IN ('branch.read','branch.manage','branch.access.read','branch.access.manage');

INSERT INTO public.permissions(permission_key,description,module_key)
VALUES
 ('branch.profile.manage','Manage branch profile and operating information','branch_management'),
 ('branch.hours.manage','Manage branch operating hours','branch_management'),
 ('branch.contact.manage','Manage branch contacts','branch_management'),
 ('branch.settings.manage','Manage branch-specific settings','branch_management')
ON CONFLICT(permission_key) DO UPDATE SET
 description=EXCLUDED.description,module_key=EXCLUDED.module_key;

INSERT INTO public.module_dependencies(module_id,depends_on_module_id,minimum_version,is_mandatory)
SELECT b.id,o.id,'1.0.0',true
FROM public.platform_modules b
JOIN public.platform_modules o ON o.module_key='organization_management'
WHERE b.module_key='branch_management'
ON CONFLICT(module_id,depends_on_module_id) DO NOTHING;

-- Branch-owned records; disabling the module never deletes these rows.
CREATE TABLE public.branch_profiles (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
 branch_id uuid NOT NULL,
 branch_type text NOT NULL DEFAULT 'standard',
 manager_name text,
 manager_email text,
 geo_location jsonb NOT NULL DEFAULT '{}'::jsonb,
 daily_capacity numeric(14,2) CHECK (daily_capacity IS NULL OR daily_capacity >= 0),
 notes text,
 tags text[] NOT NULL DEFAULT '{}',
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(branch_id),
 UNIQUE(branch_id,organization_id),
 FOREIGN KEY(branch_id,organization_id) REFERENCES public.branches(id,organization_id) ON DELETE RESTRICT
);

CREATE TABLE public.branch_operating_hours (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
 branch_id uuid NOT NULL,
 day_of_week smallint NOT NULL CHECK(day_of_week BETWEEN 0 AND 6),
 opens_at time,
 closes_at time,
 is_closed boolean NOT NULL DEFAULT false,
 notes text,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(branch_id,day_of_week),
 FOREIGN KEY(branch_id,organization_id) REFERENCES public.branches(id,organization_id) ON DELETE RESTRICT,
 CHECK (
  (is_closed=true AND opens_at IS NULL AND closes_at IS NULL)
  OR
  (is_closed=false AND opens_at IS NOT NULL AND closes_at IS NOT NULL AND opens_at < closes_at)
 )
);

CREATE TABLE public.branch_contacts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
 branch_id uuid NOT NULL,
 contact_type text NOT NULL DEFAULT 'general' CHECK(contact_type IN ('general','manager','accounts','operations','emergency','other')),
 contact_name text NOT NULL,
 phone text,
 email text,
 is_primary boolean NOT NULL DEFAULT false,
 is_active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(branch_id,organization_id) REFERENCES public.branches(id,organization_id) ON DELETE RESTRICT
);
CREATE UNIQUE INDEX branch_contacts_one_primary_type_idx
 ON public.branch_contacts(branch_id,contact_type) WHERE is_primary=true AND is_active=true;

CREATE TABLE public.branch_settings (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
 branch_id uuid NOT NULL,
 setting_key text NOT NULL,
 setting_value jsonb NOT NULL DEFAULT '{}'::jsonb,
 updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(branch_id,setting_key),
 FOREIGN KEY(branch_id,organization_id) REFERENCES public.branches(id,organization_id) ON DELETE RESTRICT
);

CREATE INDEX branch_profiles_org_idx ON public.branch_profiles(organization_id);
CREATE INDEX branch_hours_branch_day_idx ON public.branch_operating_hours(branch_id,day_of_week);
CREATE INDEX branch_contacts_branch_active_idx ON public.branch_contacts(branch_id,is_active);
CREATE INDEX branch_settings_org_branch_idx ON public.branch_settings(organization_id,branch_id);

ALTER TABLE public.branch_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branch_operating_hours ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branch_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.branch_settings ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.branch_profiles,public.branch_operating_hours,public.branch_contacts,public.branch_settings FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.branch_profiles,public.branch_operating_hours,public.branch_contacts,public.branch_settings TO authenticated;

-- Organization members with branch.read can see the branch directory;
-- operational data remains limited to explicitly assigned branches.
DROP POLICY branches_scoped_read ON public.branches;
CREATE POLICY branches_scoped_read ON public.branches
 FOR SELECT TO authenticated
 USING (private.is_org_member(organization_id)
    AND private.has_org_permission(organization_id,'branch.read'));

CREATE POLICY branch_profiles_read ON public.branch_profiles
 FOR SELECT TO authenticated
 USING (private.has_branch_access(organization_id,branch_id,'branch.read'));
CREATE POLICY branch_hours_read ON public.branch_operating_hours
 FOR SELECT TO authenticated
 USING (private.has_branch_access(organization_id,branch_id,'branch.read'));
CREATE POLICY branch_contacts_read ON public.branch_contacts
 FOR SELECT TO authenticated
 USING (private.has_branch_access(organization_id,branch_id,'branch.read'));
CREATE POLICY branch_settings_read ON public.branch_settings
 FOR SELECT TO authenticated
 USING (private.has_branch_access(organization_id,branch_id,'branch.read'));

CREATE TRIGGER branch_profiles_touch_updated_at BEFORE UPDATE ON public.branch_profiles
 FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER branch_hours_touch_updated_at BEFORE UPDATE ON public.branch_operating_hours
 FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER branch_contacts_touch_updated_at BEFORE UPDATE ON public.branch_contacts
 FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();
CREATE TRIGGER branch_settings_touch_updated_at BEFORE UPDATE ON public.branch_settings
 FOR EACH ROW EXECUTE FUNCTION private.touch_updated_at();

-- Branch creation: the caller receives manager access to the new branch.
CREATE OR REPLACE FUNCTION public.branch_create(
 p_organization_id uuid,
 p_branch_code text,
 p_name text,
 p_address jsonb DEFAULT '{}'::jsonb,
 p_phone text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,public,private,auth
AS $$
DECLARE v_branch_id uuid;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT private.is_org_member(p_organization_id)
    OR NOT private.has_org_permission(p_organization_id,'branch.manage') THEN
   RAISE EXCEPTION 'Branch management permission required' USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS (
   SELECT 1 FROM public.organization_modules om
   JOIN public.platform_modules pm ON pm.id=om.module_id
   WHERE om.organization_id=p_organization_id
     AND pm.module_key='branch_management' AND om.status='active'
 ) THEN RAISE EXCEPTION 'Branch Management module is not enabled'; END IF;
 IF length(trim(coalesce(p_branch_code,'')))=0 OR length(trim(coalesce(p_name,'')))=0 THEN
   RAISE EXCEPTION 'Branch code and name are required';
 END IF;
 INSERT INTO public.branches(organization_id,branch_code,name,address,phone,created_by)
 VALUES(p_organization_id,upper(trim(p_branch_code)),trim(p_name),coalesce(p_address,'{}'::jsonb),nullif(trim(p_phone),''),auth.uid())
 RETURNING id INTO v_branch_id;
 INSERT INTO public.member_branch_access(organization_id,user_id,branch_id,access_level,granted_by)
 VALUES(p_organization_id,auth.uid(),v_branch_id,'manager',auth.uid());
 INSERT INTO public.module_audit_logs(organization_id,branch_id,actor_user_id,action,resource_type,resource_id,new_values)
 VALUES(p_organization_id,v_branch_id,auth.uid(),'branch.created','branch',v_branch_id,
  jsonb_build_object('branch_code',upper(trim(p_branch_code)),'name',trim(p_name),'status','active'));
 RETURN v_branch_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.branch_update(
 p_organization_id uuid,
 p_branch_id uuid,
 p_branch_code text,
 p_name text,
 p_address jsonb,
 p_phone text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,public,private,auth
AS $$
DECLARE v_old jsonb; v_new jsonb;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT private.is_org_member(p_organization_id)
    OR NOT private.has_org_permission(p_organization_id,'branch.manage')
    OR NOT private.has_branch_access(p_organization_id,p_branch_id,'branch.manage') THEN
   RAISE EXCEPTION 'Branch update permission required' USING ERRCODE='42501';
 END IF;
 SELECT jsonb_build_object('branch_code',branch_code,'name',name,'address',address,'phone',phone)
 INTO v_old FROM public.branches
 WHERE id=p_branch_id AND organization_id=p_organization_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Branch not found'; END IF;
 IF length(trim(coalesce(p_branch_code,'')))=0 OR length(trim(coalesce(p_name,'')))=0 THEN
   RAISE EXCEPTION 'Branch code and name are required';
 END IF;
 UPDATE public.branches SET branch_code=upper(trim(p_branch_code)),name=trim(p_name),
   address=coalesce(p_address,'{}'::jsonb),phone=nullif(trim(p_phone),'')
 WHERE id=p_branch_id AND organization_id=p_organization_id;
 v_new:=jsonb_build_object('branch_code',upper(trim(p_branch_code)),'name',trim(p_name),
   'address',coalesce(p_address,'{}'::jsonb),'phone',nullif(trim(p_phone),''));
 INSERT INTO public.module_audit_logs(organization_id,branch_id,actor_user_id,action,resource_type,resource_id,old_values,new_values)
 VALUES(p_organization_id,p_branch_id,auth.uid(),'branch.updated','branch',p_branch_id,v_old,v_new);
END;
$$;

CREATE OR REPLACE FUNCTION public.branch_set_status(
 p_organization_id uuid,p_branch_id uuid,p_status text,p_reason text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,public,private,auth
AS $$
DECLARE v_old text;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF p_status NOT IN ('active','inactive','suspended') THEN RAISE EXCEPTION 'Invalid branch status'; END IF;
 IF length(trim(coalesce(p_reason,'')))<5 THEN RAISE EXCEPTION 'A reason of at least 5 characters is required'; END IF;
 IF NOT private.is_org_member(p_organization_id)
    OR NOT private.has_org_permission(p_organization_id,'branch.manage')
    OR NOT private.has_branch_access(p_organization_id,p_branch_id,'branch.manage') THEN
   RAISE EXCEPTION 'Branch status permission required' USING ERRCODE='42501';
 END IF;
 SELECT status INTO v_old FROM public.branches
 WHERE id=p_branch_id AND organization_id=p_organization_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Branch not found'; END IF;
 UPDATE public.branches SET status=p_status WHERE id=p_branch_id AND organization_id=p_organization_id;
 INSERT INTO public.module_audit_logs(organization_id,branch_id,actor_user_id,action,resource_type,resource_id,old_values,new_values)
 VALUES(p_organization_id,p_branch_id,auth.uid(),'branch.status_changed','branch',p_branch_id,
  jsonb_build_object('status',v_old),jsonb_build_object('status',p_status,'reason',trim(p_reason)));
END;
$$;

CREATE OR REPLACE FUNCTION public.branch_upsert_profile(
 p_organization_id uuid,p_branch_id uuid,p_branch_type text,p_manager_name text,
 p_manager_email text,p_geo_location jsonb,p_daily_capacity numeric,p_notes text,p_tags text[]
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,public,private,auth
AS $$
DECLARE v_id uuid;
BEGIN
 IF auth.uid() IS NULL OR NOT private.has_org_permission(p_organization_id,'branch.profile.manage')
 OR NOT private.has_branch_access(p_organization_id,p_branch_id,'branch.manage') THEN
  RAISE EXCEPTION 'Branch profile permission required' USING ERRCODE='42501';
 END IF;
 INSERT INTO public.branch_profiles(organization_id,branch_id,branch_type,manager_name,manager_email,geo_location,daily_capacity,notes,tags)
 VALUES(p_organization_id,p_branch_id,coalesce(nullif(trim(p_branch_type),''),'standard'),
  nullif(trim(p_manager_name),''),nullif(trim(p_manager_email),''),coalesce(p_geo_location,'{}'::jsonb),p_daily_capacity,p_notes,coalesce(p_tags,'{}'))
 ON CONFLICT(branch_id) DO UPDATE SET branch_type=EXCLUDED.branch_type,manager_name=EXCLUDED.manager_name,
  manager_email=EXCLUDED.manager_email,geo_location=EXCLUDED.geo_location,daily_capacity=EXCLUDED.daily_capacity,
  notes=EXCLUDED.notes,tags=EXCLUDED.tags
 RETURNING id INTO v_id;
 INSERT INTO public.module_audit_logs(organization_id,branch_id,actor_user_id,action,resource_type,resource_id,new_values)
 VALUES(p_organization_id,p_branch_id,auth.uid(),'branch.profile_saved','branch_profile',v_id,
  jsonb_build_object('branch_type',p_branch_type,'daily_capacity',p_daily_capacity));
 RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.branch_set_operating_hours(
 p_organization_id uuid,p_branch_id uuid,p_day_of_week smallint,
 p_is_closed boolean,p_opens_at time,p_closes_at time,p_notes text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,public,private,auth
AS $$
DECLARE v_id uuid;
BEGIN
 IF auth.uid() IS NULL OR NOT private.has_org_permission(p_organization_id,'branch.hours.manage')
 OR NOT private.has_branch_access(p_organization_id,p_branch_id,'branch.manage') THEN
  RAISE EXCEPTION 'Branch hours permission required' USING ERRCODE='42501';
 END IF;
 INSERT INTO public.branch_operating_hours(organization_id,branch_id,day_of_week,is_closed,opens_at,closes_at,notes)
 VALUES(p_organization_id,p_branch_id,p_day_of_week,p_is_closed,
  CASE WHEN p_is_closed THEN NULL ELSE p_opens_at END,
  CASE WHEN p_is_closed THEN NULL ELSE p_closes_at END,p_notes)
 ON CONFLICT(branch_id,day_of_week) DO UPDATE SET is_closed=EXCLUDED.is_closed,
  opens_at=EXCLUDED.opens_at,closes_at=EXCLUDED.closes_at,notes=EXCLUDED.notes
 RETURNING id INTO v_id;
 INSERT INTO public.module_audit_logs(organization_id,branch_id,actor_user_id,action,resource_type,resource_id,new_values)
 VALUES(p_organization_id,p_branch_id,auth.uid(),'branch.hours_saved','branch_operating_hours',v_id,
  jsonb_build_object('day_of_week',p_day_of_week,'is_closed',p_is_closed,'opens_at',p_opens_at,'closes_at',p_closes_at));
 RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.branch_add_contact(
 p_organization_id uuid,p_branch_id uuid,p_contact_type text,p_contact_name text,
 p_phone text,p_email text,p_is_primary boolean
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,public,private,auth
AS $$
DECLARE v_id uuid;
BEGIN
 IF auth.uid() IS NULL OR NOT private.has_org_permission(p_organization_id,'branch.contact.manage')
 OR NOT private.has_branch_access(p_organization_id,p_branch_id,'branch.manage') THEN
  RAISE EXCEPTION 'Branch contact permission required' USING ERRCODE='42501';
 END IF;
 IF length(trim(coalesce(p_contact_name,'')))=0 THEN RAISE EXCEPTION 'Contact name is required'; END IF;
 IF p_is_primary THEN
  UPDATE public.branch_contacts SET is_primary=false
   WHERE branch_id=p_branch_id AND contact_type=p_contact_type AND is_active=true;
 END IF;
 INSERT INTO public.branch_contacts(organization_id,branch_id,contact_type,contact_name,phone,email,is_primary)
 VALUES(p_organization_id,p_branch_id,p_contact_type,trim(p_contact_name),nullif(trim(p_phone),''),nullif(trim(p_email),''),coalesce(p_is_primary,false))
 RETURNING id INTO v_id;
 INSERT INTO public.module_audit_logs(organization_id,branch_id,actor_user_id,action,resource_type,resource_id,new_values)
 VALUES(p_organization_id,p_branch_id,auth.uid(),'branch.contact_added','branch_contact',v_id,
  jsonb_build_object('contact_type',p_contact_type,'contact_name',trim(p_contact_name),'is_primary',p_is_primary));
 RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.branch_set_setting(
 p_organization_id uuid,p_branch_id uuid,p_setting_key text,p_setting_value jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,public,private,auth
AS $$
DECLARE v_id uuid;
BEGIN
 IF auth.uid() IS NULL OR NOT private.has_org_permission(p_organization_id,'branch.settings.manage')
 OR NOT private.has_branch_access(p_organization_id,p_branch_id,'branch.manage') THEN
  RAISE EXCEPTION 'Branch settings permission required' USING ERRCODE='42501';
 END IF;
 IF p_setting_key NOT IN ('collection_enabled','sales_enabled','allow_cash','default_currency','local_timezone','operational_notes') THEN
  RAISE EXCEPTION 'Unsupported branch setting key';
 END IF;
 INSERT INTO public.branch_settings(organization_id,branch_id,setting_key,setting_value,updated_by)
 VALUES(p_organization_id,p_branch_id,p_setting_key,coalesce(p_setting_value,'{}'::jsonb),auth.uid())
 ON CONFLICT(branch_id,setting_key) DO UPDATE SET setting_value=EXCLUDED.setting_value,updated_by=auth.uid()
 RETURNING id INTO v_id;
 INSERT INTO public.module_audit_logs(organization_id,branch_id,actor_user_id,action,resource_type,resource_id,new_values)
 VALUES(p_organization_id,p_branch_id,auth.uid(),'branch.setting_saved','branch_setting',v_id,
  jsonb_build_object('setting_key',p_setting_key,'setting_value',p_setting_value));
 RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.branch_create(uuid,text,text,jsonb,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.branch_update(uuid,uuid,text,text,jsonb,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.branch_set_status(uuid,uuid,text,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.branch_upsert_profile(uuid,uuid,text,text,text,jsonb,numeric,text,text[]) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.branch_set_operating_hours(uuid,uuid,smallint,boolean,time,time,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.branch_add_contact(uuid,uuid,text,text,text,text,boolean) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.branch_set_setting(uuid,uuid,text,jsonb) FROM PUBLIC,anon;

GRANT EXECUTE ON FUNCTION public.branch_create(uuid,text,text,jsonb,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.branch_update(uuid,uuid,text,text,jsonb,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.branch_set_status(uuid,uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.branch_upsert_profile(uuid,uuid,text,text,text,jsonb,numeric,text,text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.branch_set_operating_hours(uuid,uuid,smallint,boolean,time,time,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.branch_add_contact(uuid,uuid,text,text,text,text,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.branch_set_setting(uuid,uuid,text,jsonb) TO authenticated;

COMMIT;

