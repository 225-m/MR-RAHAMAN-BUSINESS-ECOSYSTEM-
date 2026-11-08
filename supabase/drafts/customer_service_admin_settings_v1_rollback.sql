-- MR RAHAMAN Business Ecosystem
-- CUSTOMER SERVICE ADMIN SETTINGS V1 — FUNCTIONAL ROLLBACK ONLY.
-- Preserves all settings, permission catalogue, and audit history.
-- Never drops customer feature data or audit records.

begin;

revoke all on function public.customer_service_feature_settings_v1()
  from public, anon, authenticated;
revoke all on function public.set_customer_service_feature_v1(text,boolean,text)
  from public, anon, authenticated;

drop function if exists public.customer_service_feature_settings_v1();
drop function if exists public.set_customer_service_feature_v1(text,boolean,text);

revoke all on function private.customer_service_feature_settings_v1()
  from public, anon, authenticated, service_role;
revoke all on function private.set_customer_service_feature_v1(text,boolean,text)
  from public, anon, authenticated, service_role;
revoke all on function private.has_platform_permission(text)
  from public, anon, authenticated, service_role;

drop function if exists private.customer_service_feature_settings_v1();
drop function if exists private.set_customer_service_feature_v1(text,boolean,text);
drop function if exists private.has_platform_permission(text);

commit;

-- Intentionally retained:
-- * private.platform_permissions and platform_role_permissions
-- * private.customer_service_feature_settings
-- * private.customer_service_feature_audit and its append-only trigger
-- * all settings rows and audit history
-- This is a forward-recovery-friendly rollback. Do not drop the retained tables
-- or audit data as part of an application rollback.
