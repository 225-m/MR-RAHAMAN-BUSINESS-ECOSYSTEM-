# Branch Preview — Module Lifecycle V1 UI

Project: MR RAHAMAN Business Ecosystem  
Branch: `feature/customer-access-v1`  
Status: Preview source integration only; no Production deployment.

## User flow

Branch Preview now exposes an organization-scoped Module Lifecycle area:

1. **Request** — a member with `module.read` and `module.request` can request enable/disable for a non-core module. A reason is required.
2. **Independent Approval** — a different active member with `approval.approve` can approve or reject. The requester is not shown an approval action for their own request.
3. **Apply** — an actor with `module.manage` can apply an approved request. The UI requires an approved linked approval record before showing the action.

The UI calls only these public RPCs:

- `module_request_change_v1`
- `module_approval_decide_v1`
- `module_apply_approved_change_v1`

No direct writes are made to `organization_modules`, `module_change_requests`, or `approval_requests`. The legacy `branch_module_set_enabled` RPC is not called anywhere in the Branch Preview source.

## Permission and read model

- `platform_modules` is read through its authenticated active-catalog SELECT policy.
- Current module state and change history require `module.read`.
- Approval status/history requires `approval.read`.
- Request, decision, and apply controls are independently gated in the UI by `module.request`, `approval.approve`, and `module.manage`.
- These UI gates are only usability controls. Every mutation is re-authorized inside the V1 database RPC.
- If the V1 RPCs are not deployed, the UI reports the RPC error and does not fall back to the legacy RPC.

## Test coverage added

The Branch Preview CI validation now checks:

- JavaScript syntax, unique DOM IDs, and referenced DOM IDs.
- Presence of all three V1 RPC calls and all four lifecycle permissions.
- Absence of the legacy module toggle RPC.
- No direct mutation methods against `organization_modules`.
- Existing Branch Preview authentication and branch RPC checks remain enabled.

## Deployment boundary

This commit is on the feature branch only. It does not publish GitHub Pages, deploy the Edge Function, apply SQL to Supabase Production, or revoke legacy RPC grants. Production still needs a coordinated V1 database deployment and client cutover after isolated tests and Owner safeguards pass.
