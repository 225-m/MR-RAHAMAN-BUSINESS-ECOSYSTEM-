# First Platform Owner + Organization Owner Bootstrap v2 — Staging Test Plan

Target: MR RAHAMAN Business Ecosystem (`pojhrvmuamdejlutxpng`).
Status: draft only; not deployed or run against Production.

## Positive tests — isolated non-production project only
1. Allowlisted user with valid JWT and confirmed email can invoke the server-side Edge Function.
2. Bootstrap creates exactly one active `platform_owner` row with `expires_at IS NULL`.
3. Bootstrap creates exactly one active organization, one active Owner role, and one active membership for the allowlisted user.
4. Owner role receives exactly the 41 current permission rows from the test catalogue.
5. Exactly the six actual core modules are enabled: organization_management, identity_access, branch_management, module_registry, approval_governance, audit_security.
6. One `INITIAL_PLATFORM_OWNER_BOOTSTRAP_COMPLETED` append-only audit row is written.
7. `current_access_context_v1()` returns `is_platform_owner=true` and the active organization permission list.
8. The user can access only operations permitted by existing RLS and server-side RPC checks.

## Negative tests
1. Missing Authorization -> 401.
2. Invalid/expired JWT -> rejected; no writes.
3. Authenticated user other than the allowlisted account -> 403; no writes.
4. Unverified email -> 403; no writes.
5. Direct RPC invocation by anon/authenticated -> permission denied.
6. Second invocation -> closed-state error; no duplicate records.
7. Pre-existing organization/member/active Platform Owner -> entire transaction aborts.
8. Permission count other than 41 or missing required permission -> transaction aborts.
9. Core module count other than six -> transaction aborts.
10. Two concurrent requests -> advisory transaction lock; at most one success.
11. Expired/revoked Platform Owner is not returned as active by access-context RPC.
12. Suspended organization, inactive role, or non-active membership is excluded.
13. A non-member cannot receive organization permissions by altering browser state or user_metadata.
14. Service-role key is absent from web/Android source and build artifacts.

## Post-run checks
- active platform_owner rows = 1
- organizations = 1
- active organization_members for allowlisted account = 1
- active Owner app_roles = 1
- role_permissions for Owner = 41
- active organization_modules for the six core module keys = 6
- INITIAL_PLATFORM_OWNER_BOOTSTRAP_COMPLETED audit events = 1
- branches = 0 (intentional)

## Rollback
Before execution: revoke function grants and drop the draft RPC/Edge Function.
After successful execution: do not delete the Platform Owner, organization, membership, role, or audit rows blindly. Use a reviewed compensating transaction that preserves audit history and prevents last-owner lockout.

## Explicit boundary
No staging or Production execution has been performed by this document. Never apply the SQL draft to Production before a full staging run, backup/restore rehearsal, and security review.
