# First Owner Bootstrap v1 — Test Plan

Target: MR RAHAMAN Business Ecosystem (pojhrvmuamdejlutxpng).
Status: implementation draft; not deployed or run against Production.

## Preconditions
- Reviewed Auth account UUID is fixed in the function and SQL.
- Email is confirmed.
- No organization rows, organization memberships, or active platform_owner grant.
- Permission catalogue contains exactly 40 entries and required Branch, Audit and Role permissions.
- Five required platform modules exist.

## Positive tests (isolated non-production project)
1. Valid JWT for allowlisted user + POST creates exactly one organization,
   active Owner membership, Owner role, 40 permission links, five enabled
   core modules, and one append-only audit record.
2. Owner can read own organization, role, membership, modules and audit through
   existing RLS helper functions.
3. Owner can use existing Branch read/create/update RPCs. Bootstrap creates no branch.

## Negative tests
1. Missing Authorization -> 401.
2. Invalid/expired JWT -> rejected; no writes.
3. Another authenticated account -> 403; no writes.
4. Unverified email -> 403; no writes.
5. Second call -> closed-state error; no duplicate data.
6. Any pre-existing organization/member/platform_owner -> transaction abort.
7. Permission count mismatch or missing required permission -> transaction abort.
8. Missing any required core module -> transaction abort.
9. anon/authenticated direct RPC execution -> permission denied.
10. Concurrent calls -> advisory transaction lock; at most one success.

## Post-run checks
- organizations = 1
- active organization_members for allowlisted account = 1
- Owner app_roles = 1
- role_permissions for Owner = 40
- active organization_modules = 5
- OWNER_BOOTSTRAP_COMPLETED audit events = 1
- branches = 0 (intentional)

## Rollback
Before execution: revoke function grants and drop the function.
After execution: do not delete owner/organization/audit rows blindly. Use a
reviewed compensating migration that preserves audit history and owner access.
