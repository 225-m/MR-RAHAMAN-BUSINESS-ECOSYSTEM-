-- MR RAHAMAN Business Ecosystem — First Owner Bootstrap v1 (DRAFT ONLY)
-- Project: pojhrvmuamdejlutxpng. Do not run until reviewed/approved.
-- One verified account, one-time only; no platform_owner grant and no branch creation.

create or replace function public.bootstrap_first_owner_v1(p_expected_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $function$
declare
  v_user_id constant uuid := 'd1b98876-7803-469d-9228-545ab8f8b3d4';
  v_org_id uuid;
  v_role_id uuid;
  v_permission_count integer;
  v_module_count integer;
  v_email_confirmed boolean;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'service_role required' using errcode = '42501';
  end if;
  if p_expected_user_id is distinct from v_user_id then
    raise exception 'Unexpected bootstrap subject' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtext('mr-rahaman:first-owner-bootstrap:v1'));

  select (u.email_confirmed_at is not null) into v_email_confirmed
  from auth.users u where u.id = v_user_id;
  if coalesce(v_email_confirmed, false) is not true then
    raise exception 'Allowlisted owner account missing or email unverified' using errcode = '42501';
  end if;

  if exists (select 1 from public.organizations)
     or exists (select 1 from public.organization_members)
     or exists (select 1 from public.platform_admin_roles
       where role_key='platform_owner' and revoked_at is null
         and (expires_at is null or expires_at > now())) then
    raise exception 'First-owner bootstrap is closed; existing platform data detected' using errcode = '55000';
  end if;

  select count(*) into v_permission_count from public.permissions;
  if v_permission_count <> 40 then
    raise exception 'Permission catalogue changed: expected 40, found %', v_permission_count using errcode = '55000';
  end if;
  if not exists (select 1 from public.permissions where permission_key='branch.read')
     or not exists (select 1 from public.permissions where permission_key='branch.manage')
     or not exists (select 1 from public.permissions where permission_key='branch.access.manage')
     or not exists (select 1 from public.permissions where permission_key='audit.read')
     or not exists (select 1 from public.permissions where permission_key='role.manage') then
    raise exception 'Required Owner permissions are missing' using errcode = '55000';
  end if;

  insert into public.organizations
    (organization_key,name,legal_name,status,timezone,currency_code,created_by)
  values
    ('mr-rahaman-business-ecosystem','MR RAHAMAN Business Ecosystem',
     'MR RAHAMAN Business Ecosystem','active','Asia/Dhaka','BDT',v_user_id)
  returning id into v_org_id;

  insert into public.app_roles
    (organization_id,role_key,role_name,description,is_system,is_active)
  values
    (v_org_id,'owner','Owner','Initial verified organization owner; bootstrap-created role.',true,true)
  returning id into v_role_id;

  insert into public.role_permissions (organization_id,role_id,permission_id)
  select v_org_id,v_role_id,p.id from public.permissions p;
  get diagnostics v_permission_count = row_count;
  if v_permission_count <> 40 then
    raise exception 'Owner permission assignment incomplete: %',v_permission_count using errcode = '55000';
  end if;

  insert into public.organization_members
    (organization_id,user_id,role_id,member_status,invited_by,joined_at)
  values (v_org_id,v_user_id,v_role_id,'active',v_user_id,now());

  insert into public.organization_modules
    (organization_id,module_id,status,installed_version,configuration,enabled_at,enabled_by)
  select v_org_id,pm.id,'active','1.0.0','{}'::jsonb,now(),v_user_id
  from public.platform_modules pm
  where pm.module_key in
    ('branch_management','business_dashboard','identity_access',
     'organization_management','audit_security');
  get diagnostics v_module_count = row_count;
  if v_module_count <> 5 then
    raise exception 'Required core modules missing: enabled % of 5',v_module_count using errcode = '55000';
  end if;

  insert into public.module_audit_logs
    (organization_id,actor_user_id,action,resource_type,resource_id,old_values,new_values)
  values
    (v_org_id,v_user_id,'OWNER_BOOTSTRAP_COMPLETED','organization_owner',v_role_id,null,
     jsonb_build_object('organization_id',v_org_id,'owner_user_id',v_user_id,
       'role_key','owner','permission_count',v_permission_count,
       'enabled_core_modules',v_module_count,'bootstrap_version',1));

  return jsonb_build_object('success',true,'organization_id',v_org_id,
    'owner_role_id',v_role_id,'owner_user_id',v_user_id,
    'permissions_granted',v_permission_count,'core_modules_enabled',v_module_count,
    'branch_created',false);
end;
$function$;

revoke all on function public.bootstrap_first_owner_v1(uuid) from public,anon,authenticated;
grant execute on function public.bootstrap_first_owner_v1(uuid) to service_role;

-- Function-only rollback (does not delete organization/owner/audit data):
-- revoke all on function public.bootstrap_first_owner_v1(uuid) from public,anon,authenticated,service_role;
-- drop function if exists public.bootstrap_first_owner_v1(uuid);
