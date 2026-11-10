# MR RAHAMAN Business Ecosystem — Owner Bootstrap Readiness

**Status:** Read-only Production review complete. Bootstrap remains draft-only.
**Project:** Supabase `pojhrvmuamdejlutxpng`
**Repository:** `225-m/MR-RAHAMAN-BUSINESS-ECOSYSTEM-`
**Review date:** 2026-11-08

## Verified Production facts

- Auth identity `moklesur225@gmail.com` exists and has a non-null `email_confirmed_at`.
- This Auth user currently has **0 active platform role grants** and **0 active organization memberships**.
- Both `public.current_access_context_v1()` and `private.current_access_context_v1()` are absent in Production.
- The required role, organization, membership, permission, and role-permission tables exist.
- `platform_admin_roles.role_key` permits `platform_owner`; grants track `granted_at`, `expires_at`, and `revoked_at`.
- Organization membership uses a composite role/organization foreign key and requires a role for active membership.
- `platform_admin_roles` has no unique constraint preventing duplicate grants. The bootstrap must rely on a transaction lock and explicit closed-state checks.

## Why the preview shows Access Pending

The browser successfully authenticates the verified email, then calls `public.current_access_context_v1()`. Production currently has no such RPC and this user has no active platform role or organization membership. The client correctly fails closed and keeps business Dashboard routes hidden.

## Existing bootstrap work discovered

The repository already contains a more relevant first-owner bootstrap v2 draft on `feature/branch-module-v1`:

- `supabase/drafts/first_platform_owner_bootstrap_v2.sql`
- `supabase/drafts/current_access_context_v1.sql`
- `supabase/functions/owner-bootstrap/index.ts`
- `supabase/tests/OWNER-BOOTSTRAP-TEST-PLAN.md`

The v2 design is allowlisted to the verified Auth user, requires a server-side service-role invocation, uses an advisory transaction lock, fails closed if organization/member/active-owner data already exists, checks the 41-permission catalogue, enables six named core modules, creates the Platform Owner and organization Owner records, and writes an audit event. It intentionally creates no branch or sample business data.

These files are **drafts only**. The staging test plan says the positive and negative JWT tests have not yet been run. The Edge Function is not deployed. The existing Customer Access branch also contains a separate customer-focused access-context draft; do not merge or deploy either RPC blindly without reconciling the two contracts and testing the final single RPC against the live schema.

## Required implementation sequence

1. Reconcile the two access-context drafts into one reviewed RPC contract that supports Platform Owner, organization permissions, and Customer-only access without leaking customer or business data.
2. Review the v2 bootstrap SQL against the exact Production schema, especially service-role claim handling, core module selection, permission count, audit insertion, and rollback/last-owner protection.
3. Run positive and negative tests in an isolated staging project with real JWTs, including concurrent/duplicate bootstrap attempts, wrong user, unverified user, pre-existing data, expired/revoked grants, and unauthorized direct RPC calls.
4. Verify the final RPC response from the authenticated browser session and confirm the UI remains fail-closed for all unauthorized identities.
5. Only after a separate explicit Production approval: take/verify backup, apply the reviewed migration, perform the one-time bootstrap, and re-test Android login.

## Safety boundary

This document is a review artifact only. It does not create a role, organization, membership, permission, RPC, or database object. No Production DDL/DML, migration, Edge Function deployment, Pages deployment, PR merge, or paid service was performed.
