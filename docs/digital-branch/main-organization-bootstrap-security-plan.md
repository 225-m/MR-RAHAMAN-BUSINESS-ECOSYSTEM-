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


## 7. Follow-up schema and approval-path verification (2026-11-11)

This section records the deeper read-only inspection performed after the initial plan. It does not change the database.

### 7.1 Verified relational safeguards

- `organizations.organization_key` is unique.
- `app_roles` has unique `(organization_id, role_key)` and unique `(id, organization_id)`.
- `organization_members` has unique organization/user membership and a composite role/organization foreign key; active membership requires a non-null role.
- `role_permissions` has unique `(role_id, permission_id)` and a composite role/organization foreign key.
- `organization_modules` has unique `(organization_id, module_id)`.
- `approval_requests` and `approval_actions` have organization-scoped foreign keys; each approver can record at most one action per request.
- These constraints support the planned one-organization/one-owner-role/member bootstrap, but they do not replace authorization checks inside privileged functions.

### 7.2 Complete permission catalogue inventory

The live catalogue count is **41**. The following keys were read from the database and must be used as the authoritative source for the final owner-role matrix; do not seed guessed or renamed keys:

```text
approval.approve
approval.manage
approval.read
audit.read
branch.access.manage
branch.access.read
branch.contact.manage
branch.hours.manage
branch.manage
branch.profile.manage
branch.read
branch.settings.manage
crm.manage
crm.read
dashboard.read
document.manage
document.read
finance.manage
finance.read
hr.manage
hr.read
inventory.manage
inventory.read
member.invite
member.manage
member.read
module.manage
module.read
module.request
notification.manage
organization.read
organization.update
permission.read
purchase.manage
purchase.read
reports.read
role.manage
role.read
sales.manage
sales.read
security.review
```

The registry contains 16 modules. The currently active core modules are `approval_governance`, `audit_security`, `branch_management`, `identity_access`, `module_registry`, and `organization_management`. Other registered modules are currently non-core. Initial organization-module rows must reflect the reviewed registry/dependency policy, not enable every module just because the platform registry marks it active.

### 7.3 Exact module-approval defect and required correction

The inspected implementation confirms two separate defects in the activation path:

1. `private.create_approval_request_v1` maps `branch.module_enable` to `module.manage`, but its target validation currently requires `target_type = 'branch'` and a non-null branch UUID. Module enablement should target the actual `platform_modules.id` with `target_type = 'module'`; it is not a branch-record operation.
2. `private.branch_module_set_enabled(p_organization_id, p_enabled, p_reason)` does not accept an approval-request ID and does not query `approval_requests` or `approval_actions`. Therefore it cannot prove that the exact requested module change was approved before changing the organization-module state.

The decision helper already rejects a requester approving their own request, requires either platform-owner authority or organization approval permission, records an `approval_actions` row, and updates request status. The activation function must consume that approval evidence; it must not infer approval merely from the caller's `module.manage` permission.

**Required migration design (not applied):**

- Correct `branch.module_enable` request validation to require `target_type = 'module'` and `target_id` equal to the active `branch_management` module UUID.
- Require the payload to describe the intended state (enable/disable) and validate it server-side; do not trust arbitrary client payload fields.
- Change the private activation routine to require `p_approval_request_id` and verify, in the same transaction, all of: matching organization, request type `branch.module_enable`, target type `module`, target ID equal to the branch module UUID, request status `approved`, unexpired request, and at least one approved action by an actor other than the requester.
- For activation, re-check mandatory dependencies while holding the organization-module row/transaction lock. For disablement, separately verify that no active dependent module would be stranded.
- Link the resulting `module_audit_logs.approval_request_id` to the exact request. Record old/new status, actor, reason and module identifier.
- Replace the old public wrapper signature only after checking all callers. Revoke execute on obsolete/unsafe overloads from `PUBLIC`, `anon` and `authenticated`; expose only the hardened RPC to the intended authenticated workflow. Keep the privileged implementation in the non-exposed `private` schema.
- Add tests for wrong organization, wrong module target, pending/rejected/expired request, requester self-approval, missing approval action, stale dependency state, duplicate execution and direct invocation of the old signature.

### 7.4 Function ACL review

The current public `branch_module_set_enabled(uuid, boolean, text)` wrapper is not granted to `authenticated`; its observed ACL lists only database/service roles. This is a useful barrier and must not be weakened to make the current UI work. The public approval-request and approval-decision wrappers are granted to `authenticated`. Keep the activation write path closed until a hardened replacement is tested.

Supabase's current Database Functions guidance recommends preferring `SECURITY INVOKER`; where `SECURITY DEFINER` is required, use a fixed/empty `search_path`, schema-qualify referenced objects, and explicitly narrow EXECUTE grants because PostgreSQL grants EXECUTE to PUBLIC by default. Apply that checklist to every new or replaced privileged RPC. See [Supabase Database Functions](https://supabase.com/docs/guides/database/functions).

### 7.5 Additional release gates

- [ ] Correct module target semantics for `branch.module_enable`.
- [ ] Require approved request evidence in the module activation routine.
- [ ] Check disablement dependencies as well as enablement dependencies.
- [ ] Confirm the full 41-key owner permission matrix and validate it against the live catalogue at execution time.
- [ ] Review all public/private function ACLs, including old overloads, before exposing the new RPC.
- [ ] Run Supabase Security Advisors after the migration is applied in an isolated test environment.
- [ ] Verify the RPC path with a real authenticated owner JWT and a non-owner JWT; a read-only SQL inspection is not an end-to-end authorization test.

**Updated decision:** the schema constraints are largely in place, but organization bootstrap SQL and the approval-enforced module activation SQL are still draft work. No production SQL, migration, grant, or data change has been applied.
