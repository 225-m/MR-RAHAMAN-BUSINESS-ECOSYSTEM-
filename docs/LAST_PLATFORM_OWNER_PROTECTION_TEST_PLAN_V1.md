# MR RAHAMAN Business Ecosystem — Last Platform Owner Protection Test Plan V1

**Status:** Draft test plan; no Production changes.
**Project:** pojhrvmuamdejlutxpng
**Review date:** 2026-11-09

## Read-only findings

- platform_admin_roles has role_key, user_id, granted_by, granted_at, expires_at, revoked_at.
- Unique partial index platform_admin_roles_single_active_owner_idx covers role_key where role_key = 'platform_owner' AND revoked_at IS NULL. This prevents two non-revoked Owner rows, but it does not require any Owner to exist.
- Another partial unique index prevents duplicate non-revoked role grants per user/role.
- No existing public/private function definition referencing platform_admin_roles was found in the read-only function-source scan.
- No database trigger on platform_admin_roles was found in the current Production trigger inventory.
- Production currently has zero active Owner grants, zero organizations and zero active organization memberships. Therefore positive last-owner behavior cannot be tested with real Production data.

## Threat model

An Owner can be lost through:
1. Direct DELETE or UPDATE of revoked_at.
2. Setting expires_at into the past.
3. Revoking the only Owner while adding another in a separate non-atomic transaction.
4. Two concurrent revoke/transfer operations that both read the same Owner count.
5. A role grant/expiry path that checks revoked_at IS NULL but forgets expiry.
6. A privileged RPC or service-side job that bypasses the UI check.
7. An organization role-management operation incorrectly affecting the platform Owner role.

## Required invariants

- There must be at least one valid Owner at all times after the first Owner bootstrap has completed.
- A valid Owner is a platform_owner grant with revoked_at IS NULL and (expires_at IS NULL or expires_at > now()).
- No employee, organization Admin, or ordinary authenticated user can create or self-assign a platform Owner grant.
- All Owner changes are server-side, authorized, audited, and transactional.
- Owner transfer must not temporarily create a second active Owner because the existing unique partial index forbids that state.
- Break-glass recovery is a separate, explicitly authorized and audited procedure; it is not an ordinary revoke path.

## Test matrix (isolated staging only)

| ID | Scenario | Expected |
|---|---|---|
| LO-01 | Attempt to revoke the only valid Owner | Reject; Owner remains valid |
| LO-02 | Set only Owner expires_at to past | Reject |
| LO-03 | Delete only Owner row | Reject |
| LO-04 | Employee/Admin calls Owner grant RPC | Permission denied |
| LO-05 | User tries to self-promote | Permission denied; no row |
| LO-06 | Expired Owner attempts privileged operation | Denied |
| LO-07 | Revoked Owner attempts privileged operation | Denied |
| LO-08 | Transfer to verified eligible successor | Atomic success; exactly one valid Owner |
| LO-09 | Transfer successor invalid/unverified | Roll back; original Owner remains valid |
| LO-10 | Two concurrent revocations | At most one can proceed; never zero Owners |
| LO-11 | Two concurrent transfers | Serialized; exactly one valid Owner after commit |
| LO-12 | Owner role grant and audit write fail midway | Entire transaction rolls back |
| LO-13 | Direct table DML from anon/authenticated | Denied |
| LO-14 | Service-role path without approved recovery authorization | Denied |
| LO-15 | Last Owner has expired but row is not revoked | System detects zero valid Owners; no ordinary transfer path assumes this is valid |

## Implementation notes

- The current unique index enforces “at most one non-revoked Owner”, not “at least one unexpired Owner”.
- Do not solve this by dropping the unique index or by adding a second Owner in parallel.
- A transaction-scoped advisory lock or dedicated singleton guard row must serialize all Owner grant/revoke/expiry/transfer paths.
- All paths that can change expires_at must be guarded, not only the revoke function.
- Consider a database trigger as defense in depth for direct DML, but ensure it has a narrowly scoped, non-spoofable trusted execution path for the initial bootstrap and break-glass recovery. A custom GUC supplied by a caller is not sufficient proof of trusted authorization.
- Before implementing a trigger or constraint, inspect all existing Owner/bootstrap paths and rehearse the first-owner bootstrap and transfer in a disposable database.
- Time-based expiry cannot be fully enforced by a static partial index using now(); privileged checks must evaluate expiry at operation time.
- The current Production project has no active Owner. Do not run bootstrap or test mutations against it as part of this work.

## Exit criteria

All LO-01 through LO-15 pass in isolated staging, race tests are repeatable, Security Advisor has no new critical finding, audit history is complete, and a rollback/recovery rehearsal succeeds.

No Production migration, bootstrap, grant, revoke, or settings change is authorized by this document.
