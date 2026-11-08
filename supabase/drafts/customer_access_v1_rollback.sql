-- MR RAHAMAN Business Ecosystem
-- CUSTOMER ACCESS v1 — SAFE ROLLBACK DRAFT; NOT APPLIED TO PRODUCTION.
-- This rollback disables Customer Access but PRESERVES customer profile rows.
-- Run only after confirming the migration version and taking a backup.

begin;

-- Remove only triggers introduced by customer_access_v1.sql.
drop trigger if exists on_auth_user_created_customer_profile on auth.users;
drop trigger if exists customer_profiles_set_updated_at on public.customer_profiles;

-- Disable Customer avatar object access but retain the private bucket and images
-- for a data-preserving rollback. The bucket remains private.
drop policy if exists customer_avatars_select_own on storage.objects;
drop policy if exists customer_avatars_insert_own on storage.objects;
drop policy if exists customer_avatars_update_own on storage.objects;
drop policy if exists customer_avatars_delete_own on storage.objects;

-- Revoke all client access before removing the access-context API.
revoke all on table public.customer_profiles from public, anon, authenticated;

drop function if exists public.current_access_context_v1();
drop function if exists private.current_access_context_v1();
drop function if exists private.create_customer_profile_for_auth_user();
drop function if exists private.set_customer_profile_updated_at();

-- Intentionally retain customer_profiles, its rows, RLS enablement and own-row
-- policies. With table privileges revoked, the retained data is inaccessible
-- to client roles and can be restored by a reviewed forward migration.
commit;

-- POST-ROLLBACK CHECKS (must be run by a privileged operator):
-- 1. public.customer_profiles still exists and all customer rows remain.
-- 2. RLS remains enabled.
-- 3. The two Customer triggers and the new RPC/functions are absent.
-- 4. PUBLIC/anon/authenticated have no table privileges.
-- 5. Existing platform_admin_roles and organization/branch data are untouched.
-- 6. Avatar bucket and files remain private and retained; Customer Storage policies are absent.
-- 7. Do not drop customer_profiles or delete its rows as part of rollback.
