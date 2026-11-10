BEGIN;

-- Complete the FK indexes for the new branch-owned tables.
CREATE INDEX branch_contacts_branch_org_fk_idx ON public.branch_contacts(branch_id,organization_id);
CREATE INDEX branch_contacts_org_fk_idx ON public.branch_contacts(organization_id);
CREATE INDEX branch_hours_branch_org_fk_idx ON public.branch_operating_hours(branch_id,organization_id);
CREATE INDEX branch_hours_org_fk_idx ON public.branch_operating_hours(organization_id);
CREATE INDEX branch_settings_branch_org_fk_idx ON public.branch_settings(branch_id,organization_id);
CREATE INDEX branch_settings_updated_by_fk_idx ON public.branch_settings(updated_by);
CREATE INDEX branch_settings_org_fk_idx ON public.branch_settings(organization_id);

-- Keep privileged implementation outside the exposed API schema.
ALTER FUNCTION public.branch_create(uuid,text,text,jsonb,text) SET SCHEMA private;
ALTER FUNCTION public.branch_update(uuid,uuid,text,text,jsonb,text) SET SCHEMA private;
ALTER FUNCTION public.branch_set_status(uuid,uuid,text,text) SET SCHEMA private;
ALTER FUNCTION public.branch_upsert_profile(uuid,uuid,text,text,text,jsonb,numeric,text,text[]) SET SCHEMA private;
ALTER FUNCTION public.branch_set_operating_hours(uuid,uuid,smallint,boolean,time,time,text) SET SCHEMA private;
ALTER FUNCTION public.branch_add_contact(uuid,uuid,text,text,text,text,boolean) SET SCHEMA private;
ALTER FUNCTION public.branch_set_setting(uuid,uuid,text,jsonb) SET SCHEMA private;

REVOKE ALL ON FUNCTION private.branch_create(uuid,text,text,jsonb,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION private.branch_update(uuid,uuid,text,text,jsonb,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION private.branch_set_status(uuid,uuid,text,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION private.branch_upsert_profile(uuid,uuid,text,text,text,jsonb,numeric,text,text[]) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION private.branch_set_operating_hours(uuid,uuid,smallint,boolean,time,time,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION private.branch_add_contact(uuid,uuid,text,text,text,text,boolean) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION private.branch_set_setting(uuid,uuid,text,jsonb) FROM PUBLIC,anon;

GRANT EXECUTE ON FUNCTION private.branch_create(uuid,text,text,jsonb,text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.branch_update(uuid,uuid,text,text,jsonb,text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.branch_set_status(uuid,uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.branch_upsert_profile(uuid,uuid,text,text,text,jsonb,numeric,text,text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION private.branch_set_operating_hours(uuid,uuid,smallint,boolean,time,time,text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.branch_add_contact(uuid,uuid,text,text,text,text,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION private.branch_set_setting(uuid,uuid,text,jsonb) TO authenticated;

-- Public RPC endpoints are SECURITY INVOKER; permission checks and controlled writes
-- occur inside fixed-search-path private SECURITY DEFINER implementations.
CREATE OR REPLACE FUNCTION public.branch_create(p_organization_id uuid,p_branch_code text,p_name text,p_address jsonb DEFAULT '{}'::jsonb,p_phone text DEFAULT NULL)
RETURNS uuid LANGUAGE sql SECURITY INVOKER
SET search_path=pg_catalog,public,private,auth
AS $$ SELECT private.branch_create(p_organization_id,p_branch_code,p_name,p_address,p_phone); $$;

CREATE OR REPLACE FUNCTION public.branch_update(p_organization_id uuid,p_branch_id uuid,p_branch_code text,p_name text,p_address jsonb,p_phone text)
RETURNS void LANGUAGE sql SECURITY INVOKER
SET search_path=pg_catalog,public,private,auth
AS $$ SELECT private.branch_update(p_organization_id,p_branch_id,p_branch_code,p_name,p_address,p_phone); $$;

CREATE OR REPLACE FUNCTION public.branch_set_status(p_organization_id uuid,p_branch_id uuid,p_status text,p_reason text)
RETURNS void LANGUAGE sql SECURITY INVOKER
SET search_path=pg_catalog,public,private,auth
AS $$ SELECT private.branch_set_status(p_organization_id,p_branch_id,p_status,p_reason); $$;

CREATE OR REPLACE FUNCTION public.branch_upsert_profile(p_organization_id uuid,p_branch_id uuid,p_branch_type text,p_manager_name text,p_manager_email text,p_geo_location jsonb,p_daily_capacity numeric,p_notes text,p_tags text[])
RETURNS uuid LANGUAGE sql SECURITY INVOKER
SET search_path=pg_catalog,public,private,auth
AS $$ SELECT private.branch_upsert_profile(p_organization_id,p_branch_id,p_branch_type,p_manager_name,p_manager_email,p_geo_location,p_daily_capacity,p_notes,p_tags); $$;

CREATE OR REPLACE FUNCTION public.branch_set_operating_hours(p_organization_id uuid,p_branch_id uuid,p_day_of_week smallint,p_is_closed boolean,p_opens_at time,p_closes_at time,p_notes text)
RETURNS uuid LANGUAGE sql SECURITY INVOKER
SET search_path=pg_catalog,public,private,auth
AS $$ SELECT private.branch_set_operating_hours(p_organization_id,p_branch_id,p_day_of_week,p_is_closed,p_opens_at,p_closes_at,p_notes); $$;

CREATE OR REPLACE FUNCTION public.branch_add_contact(p_organization_id uuid,p_branch_id uuid,p_contact_type text,p_contact_name text,p_phone text,p_email text,p_is_primary boolean)
RETURNS uuid LANGUAGE sql SECURITY INVOKER
SET search_path=pg_catalog,public,private,auth
AS $$ SELECT private.branch_add_contact(p_organization_id,p_branch_id,p_contact_type,p_contact_name,p_phone,p_email,p_is_primary); $$;

CREATE OR REPLACE FUNCTION public.branch_set_setting(p_organization_id uuid,p_branch_id uuid,p_setting_key text,p_setting_value jsonb)
RETURNS uuid LANGUAGE sql SECURITY INVOKER
SET search_path=pg_catalog,public,private,auth
AS $$ SELECT private.branch_set_setting(p_organization_id,p_branch_id,p_setting_key,p_setting_value); $$;

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

