# Main Organization Bootstrap — live schema review (2026-11-11)

**Scope:** Read-only inspection of Supabase project `pojhrvmuamdejlutxpng` against the draft bootstrap SQL on `feature/digital-branch-readonly-integration-v1`.

**Safety:** No database writes, migrations, function deployments, data changes, or Production tests were performed.

## Verified schema compatibility

- `organizations`: required insert columns exist; `pending` and `active` are permitted statuses.
- `app_roles`: required columns exist; `(organization_id, role_key)` is unique and `(id, organization_id)` supports scoped foreign keys.
- `organization_members`: `active` is a permitted status; active members require a non-null role; organization/user uniqueness and role/org FK are present.
- `role_permissions`: required columns exist; role/org composite FK and unique `(role_id, permission_id)` exist.
- `organization_modules`: required columns exist; statuses `active` and `disabled` are permitted; organization/module uniqueness exists. The correct actor column is `enabled_by`, which matches the draft.
- `module_audit_logs`: all draft insert columns exist; organization and actor FKs are present. An append-only trigger rejects UPDATE/DELETE.
- `organizations`, `app_roles`, `organization_members`, `organization_modules`, and `module_audit_logs` have the expected touch/last-owner/audit triggers.
- The verified-founder helper is SECURITY DEFINER with an empty search_path and binds the authenticated subject to the stored founder profile and active, non-revoked platform-owner grant.
- The last-organization-owner trigger protects an active owner from deletion/demotion when no other active owner remains.
- All 41 permission keys exist and are currently mapped to module keys. The 16-module registry exists; required branch and organization modules are core/active and the branch module's mandatory organization dependency is satisfied.
- Current RLS policies are scoped to organization membership and relevant permissions; platform-admin-role client access is explicitly denied.

## Blocking finding — module enablement is not part of permission evaluation

The current `private.has_org_permission(organization_id, permission_key)` checks active organization membership, active organization, active role, and the role-permission row. It does **not** check whether the permission's `module_key` is enabled for that organization in `organization_modules`.

The draft bootstrap grants all 41 permissions, while only active core modules are enabled and non-core modules are seeded as `disabled`. Because the permission helper ignores `organization_modules.status`, a disabled module's permissions can still evaluate as granted. This undermines the intended disabled-module boundary and can allow RLS/RPC checks to pass for a module that the organization has not enabled.

**Required before Production approval:** retain the approved all-41 Owner role-permission matrix, but make the module-aware runtime gate mandatory. Effective access requires an active member, active organization, active role, explicit role-permission row, active platform registry module, and active organization module row. Disabled, missing, inactive, NULL-mapped, or unknown module state must deny access, including for Owner. No Owner bypass is permitted. The shared helper change must be regression-tested across every RLS/RPC consumer.

## Human decision — APPROVED 2026-11-11

The founder explicitly selected **all 41 current organization-scoped permissions** for the Main Owner. Platform-level grants remain separate in `platform_admin_roles`. The 41 role-permission rows are stored for Owner, but they do not override module state: optional-module permissions remain unusable while their organization module is disabled. Re-enabling a module requires the existing approved module workflow; activation alone does not grant permissions to other members. This decision is recorded in `docs/digital-branch/decisions/2026-11-11-main-owner-41-permissions-module-gate.md`.

## Test status and remaining gates

- This was a live **read-only schema review**, not an execution test.
- BOOT-01 through BOOT-20 have not been run in an isolated Supabase project.
- Need isolated tests for module-disabled authorization, module enable/disable transitions, concurrency, owner lockout, failed-transaction rollback, and wrapper ACLs.
- Need verify the new public wrapper's effective function owner and schema USAGE/EXECUTE behavior in the isolated migration.
- Re-run Supabase Security Advisors after isolated application. Current live findings remain: private founder-profile table has RLS with no direct policies (INFO; retain private access model), and leaked-password protection is disabled (WARN; Auth dashboard decision remains separate).

## Decision

**HOLD — do not convert to a numbered migration, merge PR #5, or apply to Production yet.** Resolve the module-aware authorization boundary and obtain explicit approval for the Owner permission matrix first.


## Authorization-helper blast radius

A catalog scan found the current helper is referenced by **18 database routines (including the helper and branch-access wrapper) and 11 RLS policies**. The affected paths include branch create/update/contact/settings/status/access RPCs, approval request/decision RPCs, branch list/detail/audit RPCs, and read policies for branches, approvals, members, roles, module records, invitations, and audit logs.

This confirms the candidate helper change is not a narrow bootstrap-only edit. Every listed caller and policy must be regression-tested, especially branch read/write checks and approval flows. Do not replace the live helper in Production as an isolated quick fix.
