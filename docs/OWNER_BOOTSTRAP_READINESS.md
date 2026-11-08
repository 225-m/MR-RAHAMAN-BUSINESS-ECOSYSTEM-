# MR RAHAMAN Business Ecosystem — Owner Bootstrap Readiness

**Status:** Read-only Production review complete. Draft only; no Production changes made.
**Project:** Supabase `pojhrvmuamdejlutxpng`
**Repository:** `225-m/MR-RAHAMAN-BUSINESS-ECOSYSTEM-`
**Review date:** 2026-11-08

## Verified Production facts

- Auth identity `moklesur225@gmail.com` exists and has a non-null `email_confirmed_at`.
- The Auth user currently has **0 active platform role grants**.
- The Auth user currently has **0 active organization memberships**.
- Both `public.current_access_context_v1()` and `private.current_access_context_v1()` are absent.
- `public.platform_admin_roles`, `public.organizations`, `public.organization_members`, `public.app_roles`, `public.permissions`, and `public.role_permissions` exist.
- `platform_admin_roles.role_key` permits `platform_owner`, `platform_admin`, `security_admin`, and `support_admin`; the table references Auth users and records grant/revoke timestamps.
- Organization membership uses a composite role/organization foreign key. A member cannot be activated without a role.
- `platform_admin_roles` has no unique constraint preventing duplicate grants for the same user/role. Any future bootstrap must therefore lock and check for an existing active grant before inserting.

## Why the preview shows Access Pending

The browser successfully authenticates the verified email, then calls `public.current_access_context_v1()`. Production currently has no such RPC and no active platform/organization grant for this user. The client correctly fails closed and keeps business Dashboard routes hidden.

## Required implementation sequence

1. Review and test the existing `customer_access_v1.sql` RPC draft against the exact Production schema in a disposable PostgreSQL environment. It already exists on `feature/customer-access-v1`; do not copy or reimplement it blindly.
2. Confirm the Owner bootstrap path is a one-time, operator-controlled operation, scoped to the exact verified Auth email. It must refuse to proceed if the identity is absent/unverified or an active Owner already exists.
3. Verify duplicate protection/locking, grant auditability, rollback steps, and the no-self-escalation rule. A browser user must never be able to call an RPC to grant their own Owner role.
4. Run the complete disposable-database tests, including a fresh verified user, duplicate bootstrap attempt, revoked/expired grant, unauthorized user, and Owner access context.
5. Only after review and a separate explicit Production approval: apply the reviewed migration, perform the one-time Owner bootstrap, then re-test the Android login. Do not combine migration deployment and role grant into an unreviewed single action.

## Safety boundary

This document is a review artifact only. It does not create a role, organization, membership, permission, RPC, or database object. No Production DDL/DML, migration, deployment, PR merge, or paid service was performed.
