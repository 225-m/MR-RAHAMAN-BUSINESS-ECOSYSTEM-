# Approval + Module Lifecycle V1 — Implementation Design

Status: design draft only; not deployed.
Branch: feature/authentication-v1
Scope: Version 1.0 single-level approval for module enable/disable.

## 1. Verified current state

- The database has 16 platform modules, all currently active at registry version 1.0.0.
- Core modules currently include approval_governance, audit_security, branch_management, identity_access, module_registry, and organization_management.
- organization_modules, organizations, organization_members, app_roles, role_permissions, approval_requests, approval_actions, module_change_requests, and module_audit_logs currently have no business rows.
- The only configured dependency is branch_management -> organization_management (mandatory, minimum version 1.0.0).
- The existing private.branch_module_set_enabled(organization_id, enabled, reason) performs a direct state change after module.manage authorization. It does not require approval and does not check reverse dependencies or dependency cycles.
- public.branch_module_set_enabled is a SECURITY INVOKER wrapper around that private SECURITY DEFINER function.
- Verified function ACL: public wrapper has EXECUTE for authenticated and service_role; private implementation has EXECUTE for authenticated. anon and PUBLIC do not have EXECUTE. This is not an anonymous exposure, but the authenticated direct-call route still bypasses the proposed approval workflow.
- Existing permission catalogue contains approval.approve, approval.manage, approval.read, module.manage, module.read, and module.request. module.manage is currently described as “Approve and execute module changes”; the V1 separation of request, approval, and application needs a clarified permission contract and reviewed role mappings.
- RLS policies for approval requests/actions, module change requests, organization modules, and module audit logs are scoped SELECT policies. Mutations should remain behind reviewed RPCs.
- No organization/member/role records exist, so an end-to-end authorization or approval test cannot yet be performed with a real tenant identity.

## 2. V1 behavior

1. A member with module.request may request enable or disable for a non-core module.
2. The request records the current and proposed configuration and a reason (minimum 5 trimmed characters).
3. The request creates one linked approval_requests row with required_approvals = 1 and an expiry (default 7 days).
4. The requester cannot approve their own request.
5. A different active organization member with approval.approve may approve or reject once. The unique (approval_request_id, actor_user_id) constraint prevents duplicate votes.
6. Only an approved, unexpired request can be applied. Applying it rechecks authorization, module state, dependencies, and core-module protections inside the transaction.
7. Enable requires every mandatory dependency to be active and to meet the supported minimum version policy.
8. Disable is rejected while any active module has a mandatory dependency on the target.
9. A module marked is_core=true cannot be disabled by tenant lifecycle controls. Core module changes require a separate platform-owner-controlled release path.
10. Disabling changes organization_modules.status only. It never deletes module data, tables, records, files, or audit history.
11. The state change, linked approval, module change request completion, and audit log entry commit atomically.

## 3. RPC/API boundary

Implement SECURITY DEFINER routines only in the non-exposed private schema, with a pinned search_path and explicit auth.uid() checks. Expose only SECURITY INVOKER wrappers in public. Grant execution only to authenticated; explicitly keep anon and PUBLIC from executing lifecycle mutation RPCs. Do not grant service_role unless a separately reviewed server-side workflow requires it.

Proposed RPC responsibilities:
- module_request_change(org_id, module_key, request_type, reason): validate active membership + module.request; allow only enable/disable; lock the organization row; reject core modules; snapshot current state; create both linked request rows atomically.
- approval_decide(org_id, approval_request_id, decision, comment): validate active membership + approval.approve; lock request; reject self-approval, expired/non-pending requests, duplicate decisions; update approval status.
- module_apply_approved_change(org_id, module_change_request_id): validate the reviewed application permission and approved status; lock organization and request; recheck all guards; update organization_modules; append audit record; mark request completed.

The exact function signatures and payload JSON shape must be finalized against the frontend contract before migration creation.

## 4. Dependency integrity

- Before applying enable/disable, validate the dependency graph, not only the direct dependency row.
- Detect cycles in the platform dependency graph before allowing a new dependency edge to be introduced.
- Before disabling a module, reject if any currently active module has a mandatory dependency on it.
- Version strings are text today. Do not compare them lexicographically. V1 should either validate strict semantic-version strings and compare numeric major/minor/patch components, or explicitly limit dependency support to exact/current 1.0.0 until a tested comparator is added.
- Serialize lifecycle operations per organization with SELECT ... FOR UPDATE on the organization row; recheck state after acquiring the lock.

## 5. Existing Branch API migration

Do not revoke or remove the existing Branch RPC in isolation: the current UI may call it. In the coordinated release:
1. Update the Branch UI to submit a module change request and show pending/approved/rejected/completed states.
2. Route Branch enable/disable through the generic approval workflow.
3. Verify no direct legacy route can change state without approval.
4. Only then remove/restrict the old direct mutation path and update grants. Include the service_role grant in the review; do not assume it is inherited.
5. Run UI + database regression tests before production rollout.

## 6. V1 exclusions

Defer upgrades, arbitrary configuration changes, multi-level approvals, delegated approvals, automated dependency installation, AI features, and advanced workflow automation. Keep the request_type enum/check values already present, but the V1 RPC should reject upgrade/configure until a later version.

## 7. Preconditions before production

- Provision the first organization, owner membership, owner role, and permission mappings through a separately reviewed secure bootstrap workflow. Do not self-assign owner based only on being the first authenticated account.
- Confirm the intended approval policy and whether a second distinct user can exist for approval. A one-person organization cannot satisfy requester/approver separation without an explicit break-glass policy.
- Establish a disposable staging Supabase project or a local test database. The current project is not to be treated as staging.
- Add pgTAP/integration tests for unauthorized users, self-approval, expiry, duplicate decisions, dependency missing, reverse dependency, core module disable, concurrent requests, audit atomicity, and no data deletion.
- Verify backups and a restore procedure before production migration.
- Coordinate the SQL migration and frontend release. Keep the old Branch UI/API compatible until the new workflow is live.

## 8. Safety statement

This file is a design artifact only. No SQL migration was applied, no organization/member/role was created, no existing business data was changed, and no production RPC/grant was modified.
