-- MR RAHAMAN Business Ecosystem
-- MODULE LIFECYCLE V1 — DRAFT ONLY; DO NOT APPLY TO PRODUCTION.
-- Reuses existing approval_requests, approval_actions, module_change_requests,
-- organization_modules and module_audit_logs tables.
-- Deploy only to an isolated Supabase staging project after schema parity checks.

begin;

-- Permission semantics: approval.approve decides; module.manage applies only.
-- Requesters use module.request. Existing role mappings must be reviewed before release.
update public.permissions
set description = 'Apply independently approved module changes'
where permission_key = 'module.manage';

create or replace function private.module_request_change_v1(
  p_organization_id uuid,
  p_module_key text,
  p_request_type text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_module public.platform_modules%rowtype;
  v_org_module public.organization_modules%rowtype;
  v_current_status text := 'disabled';
  v_current_configuration jsonb := '{}'::jsonb;
  v_approval_id uuid;
  v_change_id uuid;
  v_reason text := pg_catalog.btrim(coalesce(p_reason, ''));
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_module_key is null or pg_catalog.btrim(p_module_key) = '' then
    raise exception 'Organization and module key are required' using errcode = '22023';
  end if;
  if p_request_type is null or p_request_type not in ('enable', 'disable') then
    raise exception 'Only enable/disable requests are supported in V1' using errcode = '22023';
  end if;
  if pg_catalog.length(v_reason) < 5 then
    raise exception 'A reason of at least five characters is required' using errcode = '22023';
  end if;
  -- Serialize lifecycle changes, then revalidate the caller's live permission.
  -- Role/member changes in this organization must not race past this authorization check.
  perform 1
  from public.organizations o
  where o.id = p_organization_id and o.status = 'active'
  for update;
  if not found then
    raise exception 'Active organization not found' using errcode = '42501';
  end if;
  if not private.has_org_permission(p_organization_id, 'module.request') then
    raise exception 'module.request permission required' using errcode = '42501';
  end if;

  select pm.* into v_module
  from public.platform_modules pm
  where pm.module_key = pg_catalog.btrim(p_module_key)
    and pm.is_active = true
  for share;
  if not found then
    raise exception 'Module is unavailable' using errcode = '22023';
  end if;
  if v_module.is_core then
    raise exception 'Core modules cannot be changed by tenant workflow' using errcode = '42501';
  end if;

  select om.* into v_org_module
  from public.organization_modules om
  where om.organization_id = p_organization_id
    and om.module_id = v_module.id
  for update;

  if found then
    v_current_status := v_org_module.status;
    v_current_configuration := pg_catalog.jsonb_build_object(
      'status', v_org_module.status,
      'installed_version', v_org_module.installed_version,
      'configuration', v_org_module.configuration
    );
  else
    v_current_status := 'disabled';
    v_current_configuration := pg_catalog.jsonb_build_object(
      'status', 'disabled',
      'installed_version', null,
      'configuration', '{}'::jsonb
    );
  end if;

  if v_current_status not in ('active', 'disabled') then
    raise exception 'Module state % cannot be changed through V1', v_current_status
      using errcode = '55000';
  end if;
  if (p_request_type = 'enable' and v_current_status = 'active')
     or (p_request_type = 'disable' and v_current_status = 'disabled') then
    raise exception 'Requested module state is already current' using errcode = '55000';
  end if;

  if exists (
    select 1
    from public.module_change_requests mcr
    where mcr.organization_id = p_organization_id
      and mcr.module_id = v_module.id
      and mcr.status in ('pending', 'approved')
  ) then
    raise exception 'An unresolved module change request already exists' using errcode = '55000';
  end if;

  insert into public.approval_requests (
    organization_id, requested_by, request_type, target_type, target_id,
    request_payload, reason, status, required_approvals, expires_at
  ) values (
    p_organization_id, v_user_id, 'module_change', 'platform_module', v_module.id,
    pg_catalog.jsonb_build_object(
      'module_key', v_module.module_key,
      'request_type', p_request_type
    ),
    v_reason, 'pending', 1, pg_catalog.now() + interval '7 days'
  )
  returning id into v_approval_id;

  insert into public.module_change_requests (
    organization_id, module_id, request_type, requested_by,
    current_configuration, proposed_configuration, reason,
    approval_request_id, status
  ) values (
    p_organization_id, v_module.id, p_request_type, v_user_id,
    v_current_configuration,
    pg_catalog.jsonb_build_object(
      'status', case when p_request_type = 'enable' then 'active' else 'disabled' end,
      'installed_version', v_module.current_version,
      'configuration', coalesce(v_org_module.configuration, '{}'::jsonb)
    ),
    v_reason, v_approval_id, 'pending'
  )
  returning id into v_change_id;

  update public.approval_requests
  set request_payload = request_payload || pg_catalog.jsonb_build_object(
    'module_change_request_id', v_change_id
  )
  where id = v_approval_id
    and organization_id = p_organization_id;

  insert into public.module_audit_logs (
    organization_id, actor_user_id, action, resource_type, resource_id,
    old_values, new_values, approval_request_id, request_id
  ) values (
    p_organization_id, v_user_id, 'MODULE_CHANGE_REQUESTED',
    'platform_module', v_module.id,
    v_current_configuration,
    pg_catalog.jsonb_build_object(
      'request_type', p_request_type,
      'module_change_request_id', v_change_id,
      'approval_request_id', v_approval_id
    ),
    v_approval_id, v_change_id::text
  );

  return pg_catalog.jsonb_build_object(
    'module_change_request_id', v_change_id,
    'approval_request_id', v_approval_id,
    'status', 'pending'
  );
end;
$function$;

create or replace function private.module_approval_decide_v1(
  p_organization_id uuid,
  p_approval_request_id uuid,
  p_decision text,
  p_comment text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_approval public.approval_requests%rowtype;
  v_change public.module_change_requests%rowtype;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_decision is null or p_decision not in ('approved', 'rejected') then
    raise exception 'Decision must be approved or rejected' using errcode = '22023';
  end if;
  perform 1 from public.organizations o
  where o.id = p_organization_id and o.status = 'active'
  for update;
  if not found then
    raise exception 'Active organization not found' using errcode = '42501';
  end if;
  if not private.has_org_permission(p_organization_id, 'approval.approve') then
    raise exception 'approval.approve permission required' using errcode = '42501';
  end if;

  select ar.* into v_approval
  from public.approval_requests ar
  where ar.id = p_approval_request_id
    and ar.organization_id = p_organization_id
    and ar.request_type = 'module_change'
    and ar.target_type = 'platform_module'
  for update;
  if not found then
    raise exception 'Module approval request not found' using errcode = 'P0002';
  end if;

  if v_user_id = v_approval.requested_by then
    raise exception 'Requester cannot approve or reject their own request' using errcode = '42501';
  end if;
  if v_approval.status <> 'pending' then
    raise exception 'Approval request is not pending' using errcode = '55000';
  end if;
  if v_approval.expires_at is not null and v_approval.expires_at <= pg_catalog.now() then
    raise exception 'Approval request has expired' using errcode = '55000';
  end if;

  select mcr.* into v_change
  from public.module_change_requests mcr
  where mcr.approval_request_id = v_approval.id
    and mcr.organization_id = p_organization_id
  for update;
  if not found or v_change.status <> 'pending' then
    raise exception 'Linked module change is not pending' using errcode = '55000';
  end if;

  insert into public.approval_actions (
    organization_id, approval_request_id, actor_user_id, decision, comment
  ) values (
    p_organization_id, v_approval.id, v_user_id, p_decision,
    nullif(pg_catalog.btrim(coalesce(p_comment, '')), '')
  );

  update public.approval_requests
  set status = p_decision, resolved_at = pg_catalog.now()
  where id = v_approval.id and organization_id = p_organization_id;

  update public.module_change_requests
  set status = p_decision
  where id = v_change.id and organization_id = p_organization_id;

  insert into public.module_audit_logs (
    organization_id, actor_user_id, action, resource_type, resource_id,
    old_values, new_values, approval_request_id, request_id
  ) values (
    p_organization_id, v_user_id,
    case when p_decision = 'approved' then 'MODULE_CHANGE_APPROVED' else 'MODULE_CHANGE_REJECTED' end,
    'platform_module', v_change.module_id,
    pg_catalog.jsonb_build_object('status', 'pending'),
    pg_catalog.jsonb_build_object(
      'status', p_decision,
      'requester_user_id', v_approval.requested_by,
      'approver_user_id', v_user_id,
      'comment', nullif(pg_catalog.btrim(coalesce(p_comment, '')), '')
    ),
    v_approval.id, v_change.id::text
  );

  return v_change.id;
end;
$function$;

create or replace function private.module_apply_approved_change_v1(
  p_organization_id uuid,
  p_module_change_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_change public.module_change_requests%rowtype;
  v_approval public.approval_requests%rowtype;
  v_module public.platform_modules%rowtype;
  v_org_module public.organization_modules%rowtype;
  v_old_values jsonb;
  v_new_status text;
  v_approver_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  perform 1 from public.organizations o
  where o.id = p_organization_id and o.status = 'active'
  for update;
  if not found then
    raise exception 'Active organization not found' using errcode = '42501';
  end if;
  if not private.has_org_permission(p_organization_id, 'module.manage') then
    raise exception 'module.manage permission required to apply approved changes' using errcode = '42501';
  end if;

  select mcr.* into v_change
  from public.module_change_requests mcr
  where mcr.id = p_module_change_request_id
    and mcr.organization_id = p_organization_id
  for update;
  if not found then
    raise exception 'Module change request not found' using errcode = 'P0002';
  end if;
  if v_change.status <> 'approved' then
    raise exception 'Only approved module changes can be applied' using errcode = '55000';
  end if;

  select ar.* into v_approval
  from public.approval_requests ar
  where ar.id = v_change.approval_request_id
    and ar.organization_id = p_organization_id
  for update;
  if not found or v_approval.status <> 'approved'
     or v_change.requested_by is distinct from v_approval.requested_by
     or v_approval.request_payload->>'module_change_request_id' is distinct from v_change.id::text then
    raise exception 'A matching linked approved decision is required' using errcode = '55000';
  end if;
  if v_approval.expires_at is not null and v_approval.expires_at <= pg_catalog.now() then
    raise exception 'Approved request has expired' using errcode = '55000';
  end if;

  select aa.actor_user_id into v_approver_id
  from public.approval_actions aa
  where aa.approval_request_id = v_approval.id
    and aa.organization_id = p_organization_id
    and aa.decision = 'approved'
    and aa.actor_user_id <> v_approval.requested_by
  order by aa.created_at
  limit 1;
  if v_approver_id is null then
    raise exception 'Independent approval record is missing' using errcode = '55000';
  end if;

  select pm.* into v_module
  from public.platform_modules pm
  where pm.id = v_change.module_id and pm.is_active = true
  for share;
  if not found or v_module.is_core then
    raise exception 'Module is unavailable or protected as core' using errcode = '42501';
  end if;

  select om.* into v_org_module
  from public.organization_modules om
  where om.organization_id = p_organization_id
    and om.module_id = v_module.id
  for update;

  if found then
    v_old_values := pg_catalog.jsonb_build_object(
      'status', v_org_module.status,
      'installed_version', v_org_module.installed_version,
      'configuration', v_org_module.configuration
    );
  else
    v_old_values := pg_catalog.jsonb_build_object(
      'status', 'disabled',
      'installed_version', null,
      'configuration', '{}'::jsonb
    );
  end if;

  if v_change.request_type = 'enable' then
    if exists (
      select 1
      from public.module_dependencies md
      where md.module_id = v_module.id
        and md.is_mandatory = true
        and not exists (
          select 1
          from public.organization_modules dep_om
          where dep_om.organization_id = p_organization_id
            and dep_om.module_id = md.depends_on_module_id
            and dep_om.status = 'active'
        )
    ) then
      raise exception 'A mandatory dependency is not active' using errcode = '55000';
    end if;
    v_new_status := 'active';
  elsif v_change.request_type = 'disable' then
    if exists (
      select 1
      from public.module_dependencies md
      join public.organization_modules dependent_om
        on dependent_om.module_id = md.module_id
       and dependent_om.organization_id = p_organization_id
       and dependent_om.status = 'active'
      where md.depends_on_module_id = v_module.id
        and md.is_mandatory = true
    ) then
      raise exception 'An active module has a mandatory dependency on this module' using errcode = '55000';
    end if;
    v_new_status := 'disabled';
  else
    raise exception 'Unsupported module request type' using errcode = '22023';
  end if;

  insert into public.organization_modules (
    organization_id, module_id, status, installed_version, configuration,
    enabled_at, disabled_at, enabled_by, updated_at
  ) values (
    p_organization_id, v_module.id, v_new_status,
    case when v_new_status = 'active' then v_module.current_version else v_org_module.installed_version end,
    coalesce(v_org_module.configuration, '{}'::jsonb),
    case when v_new_status = 'active' then pg_catalog.now() else v_org_module.enabled_at end,
    case when v_new_status = 'disabled' then pg_catalog.now() else null end,
    case when v_new_status = 'active' then v_user_id else v_org_module.enabled_by end,
    pg_catalog.now()
  )
  on conflict (organization_id, module_id) do update
  set status = excluded.status,
      installed_version = excluded.installed_version,
      configuration = excluded.configuration,
      enabled_at = excluded.enabled_at,
      disabled_at = excluded.disabled_at,
      enabled_by = excluded.enabled_by,
      updated_at = pg_catalog.now();

  v_new_status := case when v_change.request_type = 'enable' then 'active' else 'disabled' end;

  update public.module_change_requests
  set status = 'completed', completed_at = pg_catalog.now()
  where id = v_change.id and organization_id = p_organization_id;

  insert into public.module_audit_logs (
    organization_id, actor_user_id, action, resource_type, resource_id,
    old_values, new_values, approval_request_id, request_id
  ) values (
    p_organization_id, v_user_id,
    case when v_new_status = 'active' then 'MODULE_ENABLED_AFTER_APPROVAL' else 'MODULE_DISABLED_AFTER_APPROVAL' end,
    'platform_module', v_module.id, v_old_values,
    pg_catalog.jsonb_build_object(
      'status', v_new_status,
      'requester_user_id', v_change.requested_by,
      'approver_user_id', v_approver_id,
      'apply_actor_user_id', v_user_id,
      'module_change_request_id', v_change.id
    ),
    v_approval.id, v_change.id::text
  );

  return v_change.id;
end;
$function$;

-- Private implementations are callable only through the reviewed public wrappers.
revoke all on function private.module_request_change_v1(uuid,text,text,text) from public, anon, authenticated;
revoke all on function private.module_approval_decide_v1(uuid,uuid,text,text) from public, anon, authenticated;
revoke all on function private.module_apply_approved_change_v1(uuid,uuid) from public, anon, authenticated;

grant usage on schema private to authenticated;
grant execute on function private.module_request_change_v1(uuid,text,text,text) to authenticated;
grant execute on function private.module_approval_decide_v1(uuid,uuid,text,text) to authenticated;
grant execute on function private.module_apply_approved_change_v1(uuid,uuid) to authenticated;

create or replace function public.module_request_change_v1(
  p_organization_id uuid, p_module_key text, p_request_type text, p_reason text
)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
  select private.module_request_change_v1(p_organization_id, p_module_key, p_request_type, p_reason);
$function$;

create or replace function public.module_approval_decide_v1(
  p_organization_id uuid, p_approval_request_id uuid, p_decision text, p_comment text default null
)
returns uuid
language sql
security invoker
set search_path = ''
as $function$
  select private.module_approval_decide_v1(p_organization_id, p_approval_request_id, p_decision, p_comment);
$function$;

create or replace function public.module_apply_approved_change_v1(
  p_organization_id uuid, p_module_change_request_id uuid
)
returns uuid
language sql
security invoker
set search_path = ''
as $function$
  select private.module_apply_approved_change_v1(p_organization_id, p_module_change_request_id);
$function$;

revoke all on function public.module_request_change_v1(uuid,text,text,text) from public, anon, authenticated;
revoke all on function public.module_approval_decide_v1(uuid,uuid,text,text) from public, anon, authenticated;
revoke all on function public.module_apply_approved_change_v1(uuid,uuid) from public, anon, authenticated;

grant execute on function public.module_request_change_v1(uuid,text,text,text) to authenticated;
grant execute on function public.module_approval_decide_v1(uuid,uuid,text,text) to authenticated;
grant execute on function public.module_apply_approved_change_v1(uuid,uuid) to authenticated;

commit;

-- CUTOVER NOTE:
-- This draft intentionally does NOT revoke legacy branch_module_set_enabled yet.
-- First migrate every Branch UI/client caller to these V1 RPCs and verify staging.
-- Then apply the separate module_lifecycle_v1_cutover.sql in the same coordinated
-- release to revoke authenticated/service_role/PUBLIC execution on both legacy
-- public and private signatures. Until cutover, the old RPC remains a known bypass.
