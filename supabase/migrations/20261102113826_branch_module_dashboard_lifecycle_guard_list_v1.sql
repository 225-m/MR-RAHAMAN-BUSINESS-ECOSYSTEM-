BEGIN;

-- Normalize branch identifiers and constrain lifecycle states.
CREATE UNIQUE INDEX IF NOT EXISTS branches_org_code_unique_idx
 ON public.branches(organization_id,upper(trim(branch_code)));
DO $$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='branches_status_check') THEN
  ALTER TABLE public.branches ADD CONSTRAINT branches_status_check
   CHECK(status IN ('active','inactive','suspended'));
 END IF;
END $$;

-- A disabled module must not accept writes through any route.
CREATE OR REPLACE FUNCTION private.branch_module_write_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,public
AS $$
DECLARE v_org uuid;
BEGIN
 v_org := COALESCE(NEW.organization_id,OLD.organization_id);
 IF NOT EXISTS (
  SELECT 1 FROM public.organization_modules om
  JOIN public.platform_modules pm ON pm.id=om.module_id
  WHERE om.organization_id=v_org
    AND pm.module_key='branch_management'
    AND pm.is_active=true
    AND om.status='active'
 ) THEN
  RAISE EXCEPTION 'Branch Management module is disabled for this organization'
   USING ERRCODE='55000';
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION private.branch_module_write_guard() FROM PUBLIC,anon,authenticated;

DROP TRIGGER IF EXISTS branch_module_guard_branches ON public.branches;
CREATE TRIGGER branch_module_guard_branches BEFORE INSERT OR UPDATE OR DELETE ON public.branches
 FOR EACH ROW EXECUTE FUNCTION private.branch_module_write_guard();
DROP TRIGGER IF EXISTS branch_module_guard_profiles ON public.branch_profiles;
CREATE TRIGGER branch_module_guard_profiles BEFORE INSERT OR UPDATE OR DELETE ON public.branch_profiles
 FOR EACH ROW EXECUTE FUNCTION private.branch_module_write_guard();
DROP TRIGGER IF EXISTS branch_module_guard_hours ON public.branch_operating_hours;
CREATE TRIGGER branch_module_guard_hours BEFORE INSERT OR UPDATE OR DELETE ON public.branch_operating_hours
 FOR EACH ROW EXECUTE FUNCTION private.branch_module_write_guard();
DROP TRIGGER IF EXISTS branch_module_guard_contacts ON public.branch_contacts;
CREATE TRIGGER branch_module_guard_contacts BEFORE INSERT OR UPDATE OR DELETE ON public.branch_contacts
 FOR EACH ROW EXECUTE FUNCTION private.branch_module_write_guard();
DROP TRIGGER IF EXISTS branch_module_guard_settings ON public.branch_settings;
CREATE TRIGGER branch_module_guard_settings BEFORE INSERT OR UPDATE OR DELETE ON public.branch_settings
 FOR EACH ROW EXECUTE FUNCTION private.branch_module_write_guard();

-- Dashboard summary is a read-only, RLS-respecting view.
CREATE OR REPLACE VIEW public.branch_dashboard_v1
WITH (security_invoker=true)
AS
SELECT b.organization_id,
       count(*) FILTER (WHERE b.status='active') AS active_branches,
       count(*) FILTER (WHERE b.status='inactive') AS inactive_branches,
       count(*) FILTER (WHERE b.status='suspended') AS suspended_branches,
       count(*) AS total_branches,
       count(*) FILTER (WHERE bp.branch_id IS NOT NULL) AS branches_with_profile,
       COALESCE(sum(bp.daily_capacity),0) AS total_daily_capacity,
       (SELECT count(*) FROM public.branch_contacts c
        JOIN public.branches b2 ON b2.id=c.branch_id
        WHERE b2.organization_id=b.organization_id AND c.is_active=true) AS active_contacts
FROM public.branches b
LEFT JOIN public.branch_profiles bp ON bp.branch_id=b.id
GROUP BY b.organization_id;
GRANT SELECT ON public.branch_dashboard_v1 TO authenticated;

-- Branch directory query with safe bounded pagination.
CREATE OR REPLACE FUNCTION public.branch_list_v1(
 p_organization_id uuid,
 p_search text DEFAULT NULL,
 p_status text DEFAULT NULL,
 p_limit integer DEFAULT 50,
 p_offset integer DEFAULT 0
)
RETURNS SETOF public.branch_overview_v1
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path=pg_catalog,public,private,auth
AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT private.is_org_member(p_organization_id)
    OR NOT private.has_org_permission(p_organization_id,'branch.read') THEN
  RAISE EXCEPTION 'Branch read permission required' USING ERRCODE='42501';
 END IF;
 IF p_status IS NOT NULL AND p_status NOT IN ('active','inactive','suspended') THEN
  RAISE EXCEPTION 'Invalid branch status';
 END IF;
 RETURN QUERY
 SELECT v.* FROM public.branch_overview_v1 v
 WHERE v.organization_id=p_organization_id
   AND (p_status IS NULL OR v.status=p_status)
   AND (nullif(trim(p_search),'') IS NULL
     OR v.name ILIKE '%'||trim(p_search)||'%'
     OR v.branch_code ILIKE '%'||trim(p_search)||'%'
     OR v.phone ILIKE '%'||trim(p_search)||'%')
 ORDER BY v.created_at DESC,v.branch_code
 LIMIT LEAST(GREATEST(coalesce(p_limit,50),1),100)
 OFFSET GREATEST(coalesce(p_offset,0),0);
END;
$$;
REVOKE ALL ON FUNCTION public.branch_list_v1(uuid,text,text,integer,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.branch_list_v1(uuid,text,text,integer,integer) TO authenticated;

COMMIT;

