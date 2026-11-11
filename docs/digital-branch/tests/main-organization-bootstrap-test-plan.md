# Main Organization Bootstrap — isolated test plan

**Status:** Draft only. No test has been executed against Production. Run only against a disposable Supabase test project restored from the current schema.

## Test setup
- Restore the reviewed schema and seed catalogues into an isolated project.
- Use real test Auth users/JWTs representing: verified founder, non-owner, unverified founder, and revoked/expired platform owner.
- Never copy production service-role credentials into client-side tests.
- Capture database state before/after every test; use a fresh database or transaction rollback between cases.
- Run Security Advisors after applying the draft migration in the isolated environment.

## Required cases

| ID | Scenario | Expected result |
|---|---|---|
| BOOT-01 | Call without an authenticated user | Reject; no rows created |
| BOOT-02 | Authenticated non-platform-owner calls | Reject; no rows created |
| BOOT-03 | Founder email not confirmed | Reject; no rows created |
| BOOT-04 | Founder profile does not match verified identity | Reject; no rows created |
| BOOT-05 | Platform-owner grant revoked or expired | Reject; no rows created |
| BOOT-06 | Two concurrent valid calls | Exactly one succeeds; the other fails closed |
| BOOT-07 | Call again after successful bootstrap | Reject; no second organization |
| BOOT-08 | Permission catalogue has a missing key | Reject and roll back all inserts |
| BOOT-09 | Permission catalogue has an extra/new key | Reject and roll back all inserts |
| BOOT-10 | Module registry count differs from 16 | Reject and roll back all inserts |
| BOOT-11 | Mandatory dependency is not active/core | Reject and roll back all inserts |
| BOOT-12 | Inject a failure after role/member creation | Full transaction rollback; no partial organization |
| BOOT-13 | Successful founder bootstrap | One active org, one active owner member, one owner role, exactly 41 role-permission rows, 16 module rows |
| BOOT-14 | Optional/non-core modules after bootstrap | Remain disabled |
| BOOT-15 | Non-member attempts to read organization/branch data | RLS/RPC denies access |
| BOOT-16 | Ordinary authenticated user invokes private function directly | Execute denied |
| BOOT-17 | anon invokes public wrapper | Execute denied |
| BOOT-18 | Authenticated non-owner invokes public wrapper | Function rejects via verified-owner guard |
| BOOT-19 | Owner role is demoted/removed as sole active owner | Existing last-owner protection blocks lockout |
| BOOT-20 | Owner attempts to approve own approval request | Existing approval engine rejects self-approval |

## Read-only preflight assertions

Run `preflight.sql` before applying the draft. It verifies the live catalogues and that the canonical organization does not already exist. It does not create or modify data.

## Release gates
- [ ] Confirm all 41 permission keys and the decision to grant all 41 to the organization Owner.
- [ ] Confirm exact module registry and mandatory dependency behavior.
- [ ] Review function ownership, EXECUTE ACLs, schema USAGE, RLS policies, triggers and audit immutability.
- [ ] Run BOOT-01 through BOOT-20 in isolation, including concurrency and transaction rollback.
- [ ] Run Security Advisors and inspect every finding.
- [ ] Review rollback procedure and recovery access.
- [ ] Obtain explicit Production apply approval.

## Rollback boundary
Do not delete the organization, owner membership, audit trail, or business data as a routine rollback. If bootstrap succeeds, recovery must be a separately approved, audited deactivation/repair procedure. The companion rollback SQL only removes the two newly introduced RPC functions; it does not erase created records.
