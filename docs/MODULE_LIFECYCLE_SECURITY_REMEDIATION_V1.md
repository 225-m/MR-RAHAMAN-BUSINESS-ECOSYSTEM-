# MR RAHAMAN Business Ecosystem — Module Lifecycle Security Remediation V1

**Status:** Engineering design / acceptance criteria only. No Production changes.
**Target branch:** feature/customer-access-v1
**Production project:** pojhrvmuamdejlutxpng
**Review date:** 2026-11-09

## Verified Production schema (read-only)

The following tables already exist and should be reused; do not create parallel workflow tables:

- approval_requests: requester, request type, target, JSON payload, reason, status, required approvals, expiry and resolution timestamp.
- approval_actions: one actor decision per approval request, enforced by UNIQUE (approval_request_id, actor_user_id); decisions are approved or rejected.
- module_change_requests: module, enable/disable/upgrade/configure request type, current/proposed JSON configuration, requester, linked approval request, status and completion timestamp.
- organization_modules: unique organization/module row; status supports disabled, pending, active and suspended.
- module_audit_logs: audit record with actor, action, old/new values and linked approval request.

Important existing constraints:
- Approval request status: pending, approved, rejected, cancelled, expired.
- Module change request status: pending, approved, rejected, cancelled, completed.
- Module request type supports enable, disable, upgrade, configure. V1 must accept only enable/disable.
- Approval actor and requester foreign keys are organization-scoped.
- Approval action uniqueness prevents one actor voting twice, but does not by itself prevent requester self-approval.
- Current permission catalogue includes module.request, module.manage, module.read, approval.approve, approval.read, and approval.manage.
- Current module.manage description combines approval and execution; role mapping and permission semantics must be separated before release.
- Existing SELECT policies scope approval and module records to active organization membership and the corresponding read permission. Mutations must stay behind reviewed RPCs.

## Confirmed critical bypass

Production still has:
- private.branch_module_set_enabled(uuid, boolean, text): SECURITY DEFINER; checks module.manage, then directly changes organization_modules and writes an audit event. It does not require an approved request.
- public.branch_module_set_enabled(uuid, boolean, text): SECURITY INVOKER wrapper to the private function.

This authenticated RPC is a direct approval bypass. It is not an anonymous exposure, but an authenticated member with the required permission can invoke it without an approval record.

Do not revoke it until the Branch UI has been switched to the new workflow and the coordinated release is ready. Do not leave it executable after the new workflow is released.

## V1 workflow contract

### 1. Request
module_request_change(org_id, module_key, request_type, reason)

- auth.uid() must exist.
- Requester must be an active member of an active organization with module.request.
- Trimmed reason must be at least five characters.
- V1 accepts only enable or disable; reject upgrade/configure.
- Lock the organization row to serialize lifecycle operations.
- Resolve an active platform module by exact module_key.
- Reject is_core = true; tenant workflow cannot disable or alter core modules.
- Snapshot current state and proposed state in module_change_requests.
- Create linked approval_requests and module_change_requests atomically; required approvals = 1; expiry = 7 days.
- The request is immutable to the client after creation.

### 2. Independent decision
approval_decide(org_id, approval_request_id, decision, comment)

- Only active organization members with approval.approve may decide.
- Reject when auth.uid() = approval_requests.requested_by.
- Lock the approval request row and linked module request.
- Require status pending and expires_at > now() (or null only if policy explicitly permits).
- Accept only approved/rejected.
- Enforce one decision per actor using the existing unique constraint.
- Recheck approver active membership and permission at decision time; never trust UI claims or user_metadata.
- On rejection, mark both records rejected and set resolved_at.
- On approval, mark both records approved and set resolved_at.
- An approver cannot modify module state directly.

### 3. Apply
module_apply_approved_change(org_id, module_change_request_id)

- Application must be performed by a separately authorized actor; settle the exact permission contract before implementation. Do not silently reuse a permission that still means “approve and execute”.
- Lock organization, module request, approval request, and organization_modules row in a consistent order.
- Require linked approval status approved, linked change status approved, not expired, and at least one approved action by a user different from the requester. Revalidate that approver's organization membership, role activation and live approval.approve grant at apply time; a revoked or suspended approver must not leave a stale approval executable.
- Recheck current caller membership/permission and module state inside the same transaction.
- Recheck module availability, core-module protection, mandatory dependencies, and reverse dependencies.
- Enable only when all mandatory dependencies are active and platform-enabled. V1 treats a populated minimum_version as an exact version pin; no lexicographic semver comparison is used.
- Disable only when no active module has a mandatory dependency on the target.
- Do not compare version strings lexicographically. Until a tested semantic-version comparator exists, enforce exact supported version compatibility.
- Update organization_modules, mark the change request completed, and append module_audit_logs with approval_request_id, requester/approver/apply actor and old/new states in the same transaction.
- Never delete module data, business records, files or historical audit events.

## Draft implementation and automated test coverage

- Draft SQL: `supabase/drafts/module_lifecycle_v1.sql` defines private SECURITY DEFINER implementations and narrow public SECURITY DEFINER wrappers.
- Coordinated cutover draft: `supabase/drafts/module_lifecycle_v1_cutover.sql` revokes authenticated/service_role/PUBLIC execution from both legacy Branch RPC signatures. Do not execute until all clients use V1.
- Disposable fixture: `supabase/tests/fixtures/module_lifecycle_v1_schema.sql` models the verified table/constraint contract.
- Integration harness: `supabase/tests/module_lifecycle_v1.sql` checks self-approval denial, unauthorized approval denial, pending-apply denial, independent approval, one-time apply and three-step audit trail.
- GitHub Actions runs the fixture, migration, integration harness and legacy cutover in a separate disposable PostgreSQL database.

## RPC security boundary

- Private implementation functions belong in non-exposed private schema with fixed empty/pinned search_path and explicit auth.uid() checks.
- Public RPC wrappers are narrow SECURITY DEFINER privilege-boundary shims with an empty search_path; the private implementation contains all business logic and independently checks auth.uid(), live organization membership and the required permission.
- Revoke EXECUTE on private implementations from PUBLIC, anon, authenticated and service_role. Authenticated users receive EXECUTE only on the three reviewed public wrappers; PUBLIC/anon/service_role receive none.
- Do not expose the privileged implementation functions in an API schema. The three public SECURITY DEFINER wrappers are deliberately narrow entry points; they contain no authorization decision of their own and delegate to private implementations that enforce auth.uid(), active membership and permissions.
- Keep direct table mutation privileges revoked; SELECT remains subject to existing RLS.
- The legacy branch_module_set_enabled private implementation and public wrapper must have authenticated EXECUTE revoked in the same coordinated release after frontend migration. Also inspect/revoke service_role and inherited PUBLIC grants; do not assume the grant set.
- Never use service_role or a service-role key in browser/Android clients.

## Last Owner safeguards (separate control plane)

The current unique partial index platform_admin_roles_single_active_owner_idx guarantees at most one non-revoked platform_owner row. It does not guarantee at least one valid active Owner, and does not protect against expiry.

Required:
- All platform_owner grant/revoke/expiry/transfer actions must use a trusted server-side administrative path, never ordinary organization role-management RPCs.
- A revoke/expiry/transfer transaction must lock a single-owner guard row or use a transaction-scoped advisory lock, then count valid active Owners using revoked_at IS NULL AND (expires_at IS NULL OR expires_at > now()).
- Reject removal, revocation, expiry shortening, or transfer if it would leave zero valid Owners, except a separately approved, audited break-glass recovery procedure.
- Transfer must be atomic: establish and verify the successor before revoking the previous Owner, while respecting the unique partial index. Implement as a reviewed staged transfer strategy; do not disable the unique index or create a temporary second active Owner.
- Protect direct table writes with grants/RLS and database-side guard logic. A UI check is insufficient.
- Include concurrent revoke/transfer tests to prevent two sessions from both observing an Owner count of one and leaving zero.
- Expired rows must not count as valid Owners even though the existing unique index treats every non-revoked row as indexed. Expiry and revocation semantics need a deliberate constraint/index strategy before production release.
- Keep immutable audit history for every grant, revoke, expiry, transfer and break-glass action.

## Coordinated rollout order

1. Complete permission semantics and role mapping.
2. Implement request/decision/apply RPCs in draft SQL and test fixture.
3. Update Branch UI to use request/approval/apply states.
4. Verify all legacy callers and remove/restrict the direct bypass.
5. Run disposable PostgreSQL integration tests and real JWT/RLS tests in a separate staging project.
6. Run concurrency and rollback tests; run Supabase Security Advisor.
7. Only after separate explicit approval: backup/restore rehearsal, reviewed Production migration, and coordinated frontend deployment.

## Release-blocking tests

- Requester cannot approve own request, including direct RPC calls.
- Employee/Admin without module.request cannot request.
- User without approval.approve cannot decide.
- Inactive member, suspended organization, expired request and revoked role cannot decide/apply.
- Duplicate decision rejected; unique constraint remains effective.
- Approval cannot be bypassed by calling old Branch RPC, direct table DML, a guessed RPC, or a public wrapper.
- Approved request cannot be applied twice.
- Rejected/pending/expired request cannot apply.
- Automated tests now cover rejection, expired pending approval and mandatory dependency blocking, including retry after dependency activation.
- Revoking or suspending the approver after approval blocks apply until a currently authorized approval decision is obtained again.
- Enable fails if mandatory dependency is missing/inactive.
- Disable fails if any active module depends on it.
- Core module disable is rejected.
- Concurrent request/apply calls serialize and produce one valid final state.
- Audit row and state transition are atomic; failure rolls back both.
- No business data is deleted on disable.
- An apply actor cannot forge requester/approver identity in JSON payload.
- Only authorized users can read organization-scoped workflow rows.

## Safety boundary

This is a draft implementation and acceptance artifact only. It has not been run against Production. The disposable CI run is the only intended execution target. No Production SQL was applied, no Production settings or grants were changed, no module state was changed, no PR was merged, and no deployment occurred.
