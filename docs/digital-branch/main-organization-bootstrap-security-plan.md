# Main Organization Bootstrap — Security Review & Implementation Plan

**Project:** MR RAHAMAN Business Ecosystem  
**Supabase project:** `pojhrvmuamdejlutxpng`  
**Review date:** 2026-11-11  
**Status:** Read-only review complete; implementation draft only  
**Production writes:** None performed

## 1. Verified current state

- Exactly one active, non-expiring `platform_owner` grant exists.
- The authenticated owner identity is protected by `private.is_verified_platform_owner_v1()`, which checks the authenticated user ID, verified email, founder profile and active platform-owner grant.
- `organizations`, `organization_members`, `app_roles`, `role_permissions`, `organization_modules`, `approval_requests`, and `approval_actions` have RLS enabled.
- There are currently zero organization rows and zero branch rows.
- The platform registry contains 16 modules; `branch_management` is a platform-level active core module.
- The permission catalog contains the branch permissions `branch.access.manage`, `branch.access.read`, `branch.contact.manage`, `branch.hours.manage`, `branch.manage`, `branch.profile.manage`, `branch.read`, and `branch.settings.manage`.
- Branch list/detail/create RPCs already exist. The Dashboard had not been connected to the read RPC before the current feature branch work.

## 2. Important security findings

### 2.1 Owner identity check

The verified-founder function is fail-closed and binds the owner grant to a fixed authenticated user ID, verified email and founder profile. The bootstrap entry point must call this check directly; it must not trust a caller-supplied user ID, email, role name or organization ID.

### 2.2 Organization bootstrap is not present

No organization-creation/bootstrap RPC was found in the inspected public/private function catalog. Organization creation must therefore be introduced as a reviewed, one-time migration—not performed by direct browser table writes.

### 2.3 Module enablement needs approval hardening

`private.branch_module_set_enabled` currently checks `module.manage`, a reason string and mandatory dependencies, then writes the organization-module row and audit log. It does not itself require a previously approved `approval_requests` record. The approval request helper supports a `branch.module_enable` request type, but its target validation currently treats that request as a branch-targeted request. This mismatch must be resolved before exposing module activation in the UI.

### 2.4 Keep direct writes closed

Do not remove branch write guards or grant direct table write access as part of the bootstrap. Branch create/update should remain behind approved RPC flows and scoped permission checks.

## 3. Proposed one-time bootstrap transaction

A future migration should add a narrowly scoped private function plus a public RPC wrapper, with these invariants:

1. Require `auth.uid()` and `private.is_verified_platform_owner_v1()`.
2. Take a transaction-scoped advisory lock so two simultaneous bootstrap attempts cannot create duplicate primary organizations.
3. Fail closed if a primary organization already exists; never silently reassign its owner.
4. Create the canonical organization using a fixed, reviewed organization key and the configured legal/display name. Keep the status pending until all related records are ready.
5. Create an organization-scoped `owner` role; never accept a role key or permission list from the client.
6. Assign the verified founder as the active organization member using `auth.uid()`.
7. Grant the approved owner permission set from the existing permission catalog, validating that all expected permission keys exist exactly once.
8. Initialize organization-module rows from the 16-module registry. Keep optional modules disabled. Enable only explicitly approved core dependencies.
9. Activate the organization only after all required records and invariants pass in the same transaction.
10. Write an immutable audit event containing the bootstrap action, actor, organization ID and migration version.
11. Revoke execution from `PUBLIC` and `anon`; grant execution only to `authenticated` and retain the internal founder check.
12. Set a fixed safe `search_path` and schema-qualify sensitive references.

The exact organization name/key, owner permission matrix and initial core-module activation list must be reviewed against the product's master architecture before SQL is finalized.

## 4. Required test cases before production

| ID | Scenario | Expected result |
|---|---|---|
| BOOT-01 | Unauthenticated caller | Rejected |
| BOOT-02 | Authenticated non-owner | Rejected |
| BOOT-03 | Unverified founder email | Rejected |
| BOOT-04 | Founder profile mismatch | Rejected |
| BOOT-05 | Revoked/expired owner grant | Rejected |
| BOOT-06 | Two concurrent bootstrap calls | At most one organization created |
| BOOT-07 | Repeat after successful bootstrap | No duplicate; fail closed with stable response |
| BOOT-08 | Missing expected permission key | Transaction rolls back |
| BOOT-09 | Role/member/module insert failure | Entire transaction rolls back |
| BOOT-10 | Owner member removal/demotion | Last-owner guard prevents lockout |
| BOOT-11 | Non-member reads organization data | RLS denies access |
| BOOT-12 | Branch module enable without approved request | Rejected |
| BOOT-13 | Approved module enable with unmet dependency | Rejected |
| BOOT-14 | Approved module enable with dependencies met | Audited activation only |
| BOOT-15 | Direct browser INSERT/UPDATE on branch tables | Denied |

## 5. Rollback requirements

- Do not use a destructive rollback that deletes an organization after business data may exist.
- Before production release, prepare a forward-only disable/revoke procedure for the bootstrap RPC.
- If a test deployment must be reset, permit deletion only in an isolated disposable environment and only when no dependent records exist.
- Preserve owner identity and audit evidence; never revoke the only trusted platform owner as a rollback step.

## 6. Release gates

- [ ] Confirm canonical organization name and organization key.
- [ ] Finalize the owner permission matrix against all 41 permissions.
- [ ] Resolve module-enable approval target semantics and enforce approved-request verification in the activation function.
- [ ] Write migration SQL and rollback/disable SQL.
- [ ] Run all 15 tests in an isolated test project or disposable branch environment.
- [ ] Review SQL grants, RLS, function search paths and audit output.
- [ ] Obtain explicit production-apply approval.
- [ ] Only then run the production migration.

**Current decision:** do not apply SQL to production. The safe next implementation artifact is a reviewed migration draft plus tests, not a live bootstrap.
