-- Integration tests for customer_service_admin_settings_v1.sql.
-- Run only in disposable PostgreSQL after customer_access_v1.integration.sql.

\set ON_ERROR_STOP on

insert into auth.users (id,email,email_confirmed_at,raw_user_meta_data)
values
 ('dddddddd-dddd-4ddd-8ddd-dddddddddddd','platform-owner@example.test',now(),'{}'),
 ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','platform-admin@example.test',now(),'{}'),
 ('ffffffff-ffff-4fff-8fff-ffffffffffff','support-admin@example.test',now(),'{}'),
 ('99999999-9999-4999-8999-999999999999','expired-admin@example.test',now(),'{}');

insert into public.platform_admin_roles(user_id,role_key,revoked_at,expires_at)
values
 ('dddddddd-dddd-4ddd-8ddd-dddddddddddd','platform_owner',null,null),
 ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','platform_admin',null,null),
 ('ffffffff-ffff-4fff-8fff-ffffffffffff','support_admin',null,null),
 ('99999999-9999-4999-8999-999999999999','platform_admin',null,now() - interval '1 day');

do $$
begin
  if (select count(*) from private.customer_service_feature_settings) <> 7 then
    raise exception 'Expected seven customer service feature settings';
  end if;
  if exists (
    select 1 from private.customer_service_feature_settings
    where is_enabled is true or readiness_status <> 'prepared'
  ) then
    raise exception 'All optional features must start OFF and prepared';
  end if;
  if exists (
    select 1 from private.platform_role_permissions
    where role_key <> 'platform_admin'
  ) then
    raise exception 'Only platform_admin should receive the settings permissions by default';
  end if;
end $$;

set role anon;
do $$
begin
  begin
    perform public.customer_service_feature_settings_v1();
    raise exception 'anon unexpectedly read customer service settings';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- A normal customer must not read settings, change flags, or query private tables.
set role authenticated;
set request.jwt.claim.sub = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
do $$
begin
  begin
    perform public.customer_service_feature_settings_v1();
    raise exception 'Customer unexpectedly read Admin settings';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.set_customer_service_feature_v1(
      'customer_verification.master', true, 'Customer attempts privilege escalation'
    );
    raise exception 'Customer unexpectedly enabled verification master';
  exception when insufficient_privilege then null;
  end;
  begin
    perform (select count(*) from private.customer_service_feature_settings);
    raise exception 'Customer unexpectedly read private feature table';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- Support Admin does not automatically receive Customer Verification settings permission.
set role authenticated;
set request.jwt.claim.sub = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
do $$
begin
  begin
    perform public.customer_service_feature_settings_v1();
    raise exception 'Support Admin unexpectedly read settings';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- Expired platform_admin grant must not authorize.
set role authenticated;
set request.jwt.claim.sub = '99999999-9999-4999-8999-999999999999';
do $$
begin
  begin
    perform public.customer_service_feature_settings_v1();
    raise exception 'Expired platform_admin unexpectedly read settings';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- Active Platform Admin can view the controls, but cannot enable an unready feature.
set role authenticated;
set request.jwt.claim.sub = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
do $$
declare
  v_settings jsonb;
begin
  v_settings := public.customer_service_feature_settings_v1();
  if jsonb_array_length(v_settings -> 'features') <> 7 then
    raise exception 'Platform Admin should see all seven feature controls';
  end if;

  begin
    perform public.set_customer_service_feature_v1(
      'customer_verification.master', true, 'Attempt before readiness review'
    );
    raise exception 'Feature enabled before readiness gate';
  exception when object_not_in_prerequisite_state then null;
  end;

  begin
    perform public.set_customer_service_feature_v1(
      'customer_verification.phone_otp', true, 'Attempt before master switch'
    );
    raise exception 'Child feature enabled while master switch is off';
  exception when object_not_in_prerequisite_state then null;
  end;
end $$;
reset role;

-- Readiness is release-governed metadata, changed by the privileged test runner only.
update private.customer_service_feature_settings
set readiness_status = 'ready_to_enable'
where feature_key in (
  'customer_verification.master',
  'customer_verification.phone_otp',
  'customer_verification.nid',
  'customer_verification.passport',
  'customer_verification.biometric',
  'customer_verification.ai_review',
  'customer_payment.card_payments'
);

set role authenticated;
set request.jwt.claim.sub = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
do $$
declare
  v_result jsonb;
  v_count integer;
begin
  perform public.set_customer_service_feature_v1(
    'customer_verification.master', true, 'Release gates approved for test'
  );
  perform public.set_customer_service_feature_v1(
    'customer_verification.phone_otp', true, 'Provider readiness test approved'
  );
  perform public.set_customer_service_feature_v1(
    'customer_verification.nid', true, 'NID readiness test approved'
  );
  perform public.set_customer_service_feature_v1(
    'customer_payment.card_payments', true, 'Payment sandbox readiness test'
  );

  v_result := public.set_customer_service_feature_v1(
    'customer_verification.master', false, 'Emergency disable test completed'
  );
  if (v_result ->> 'verification_children_disabled')::integer <> 2 then
    raise exception 'Master-off should disable exactly two enabled verification children';
  end if;

end $;
reset role;

-- Privileged test runner verifies server-side state and audit rows after the RPC calls.
do $
declare
  v_count integer;
begin
  if exists (
    select 1 from private.customer_service_feature_settings
    where feature_group='customer_verification' and is_enabled
  ) then
    raise exception 'Master-off failed to disable every verification feature';
  end if;
  if not exists (
    select 1 from private.customer_service_feature_settings
    where feature_key='customer_payment.card_payments' and is_enabled
  ) then
    raise exception 'Payment card feature must remain independent of verification master';
  end if;
  select count(*) into v_count
  from private.customer_service_feature_audit
  where actor_user_id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  if v_count <> 7 then
    raise exception 'Expected seven audit rows for Admin test actions; found %', v_count;
  end if;
end $;

-- Platform Owner is independently authorized, even without organization membership.
set role authenticated;
set request.jwt.claim.sub = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
do $$
declare
  v_settings jsonb;
begin
  v_settings := public.customer_service_feature_settings_v1();
  if v_settings ->> 'can_manage_verification' <> 'true'
     or v_settings ->> 'can_manage_payment' <> 'true' then
    raise exception 'Active Platform Owner should have both platform settings permissions';
  end if;
  perform public.set_customer_service_feature_v1(
    'customer_verification.master', true, 'Platform Owner authorization test'
  );
end $$;
reset role;

-- Audit data is append-only even for a privileged SQL session.
do $$
begin
  begin
    update private.customer_service_feature_audit
       set reason='tampered'
     where id=(select min(id) from private.customer_service_feature_audit);
    raise exception 'Audit row update unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end $$;

select 'PASS: customer feature defaults, platform-scoped permissions, readiness gates, master-off cascade, payment independence, and append-only audit' as result;
