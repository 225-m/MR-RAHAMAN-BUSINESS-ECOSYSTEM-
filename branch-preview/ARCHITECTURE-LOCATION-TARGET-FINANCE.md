# Branch Module — Location, Target & Finance Architecture (Draft)

**Project:** MR RAHAMAN Business Ecosystem  
**Development branch:** `feature/branch-module-v1`  
**Status:** Development-only design; no Production schema changes  
**Reviewed Supabase project:** `pojhrvmuamdejlutxpng`

## 1. Verified current state

The current public schema contains these relevant tables:

- Branch: `branches`, `branch_profiles`, `branch_contacts`, `branch_operating_hours`, `branch_settings`
- Branch access and audit: `member_branch_access`, `module_audit_logs`
- Organization and authorization: `organizations`, `organization_members`, `permissions`, `app_roles`, `role_permissions`
- Approval: `approval_requests`, `approval_actions`, `module_change_requests`

No existing dedicated branch target, financial transaction/ledger, or Bangladesh administrative-location table was found. Existing `branches.address` is JSONB and can safely hold structured address data without a schema change.

Existing relevant permission keys verified:
- `branch.read`, `branch.manage`, `branch.profile.manage`, `branch.access.read`, `branch.access.manage`
- `finance.read`, `finance.manage`
- `approval.read`, `approval.approve`, `approval.manage`

No target-specific permission key was found. Do not assume target permissions already exist.

## 2. Bangladesh Location Selector — implemented on this branch

- Bundled offline JSON reference dataset, bilingual Bangla + English.
- Cascading selectors: Division → District → Upazila.
- Optional manual Union / Ward / Pourashava, area, postal code and detailed address fields.
- Saved to existing `branches.address` JSONB. No table migration needed.
- New structured address shape:

```json
{
  "country": "Bangladesh",
  "division": {"id": "BD10", "name_bn": "বরিশাল", "name_en": "Barishal"},
  "district": {"id": "BD1004", "name_bn": "বরগুনা", "name_en": "Barguna"},
  "upazila": {"id": "BD10040009", "name_bn": "আমতলী", "name_en": "Amtali"},
  "union_or_ward": "manual value",
  "area": "manual value",
  "postal_code": "8710",
  "full_address": "house / road / market"
}
```

Legacy string or JSON addresses are preserved when editing. If a parent division/district changes, stale child selections are removed. The UI does not claim union/ward completeness; those values remain manual until a verified, maintainable source is adopted.

**Dataset attribution:** Open Admin Data, Bangladesh Administrative Divisions, CC BY 4.0. See `data/bangladesh-admin-hierarchy.json` and its embedded attribution. Dataset currently includes 8 divisions, 64 districts and 495 upazilas. This is a community-maintained reference dataset, not a government API; validate spellings and future administrative changes before treating it as authoritative.

## 3. Branch Target Management — proposed, not implemented

Proposed table: `branch_targets`.

Suggested fields:
- `id`, `organization_id`, `branch_id`
- `metric_key` (e.g. sales_amount, collection_liters, customer_count)
- `target_value` numeric, `unit`, `currency_code` where applicable
- `period_start`, `period_end`
- `status`: draft / pending / approved / rejected / cancelled
- `created_by`, `created_at`, `updated_at`
- Optional `approval_request_id` linked to `approval_requests(id, organization_id)`

Rules:
- Period start must be on/before period end; target must be non-negative.
- Prevent overlapping active targets for the same organization, branch, metric and period unless the product owner explicitly chooses a revision/versioning model.
- A submitted target is immutable while approval is pending. Changes create a new revision or a new request; do not overwrite the audit trail.
- Approval requests use existing `approval_requests` and `approval_actions` tables with `target_type='branch_target'`; the exact request/decision RPC contract must be reviewed before UI wiring.
- New permissions `branch.target.read` and `branch.target.manage` are proposals only. They must be added to `permissions` and mapped to roles through the existing permission governance process, not silently granted.

## 4. Branch Financial Reports — proposed, not implemented

No current finance ledger or branch transaction table was found. Do not calculate financial KPIs from branch profile capacity or settings.

Proposed first-stage operational ledger: `branch_financial_entries`:
- `id`, `organization_id`, `branch_id`
- `entry_date`, `direction` (income / expense)
- `category_key`, `amount` (strictly positive), `currency_code` (organization currency; BDT only as a default, not a hard-coded global assumption)
- `payment_method`, `reference_no`, `description`
- `status` (draft / pending_approval / posted / void)
- `created_by`, `posted_by`, timestamps
- Optional `approval_request_id` with composite organization FK

Important accounting boundary:
- This is a branch operational cash/income/expense register, **not** a double-entry general ledger.
- If MR RAHAMAN needs full accounting, use a chart of accounts + journal header + journal lines with debit/credit balancing. Do not represent that as a single amount column.
- Reports aggregate only `posted` entries. Draft, pending, rejected and void entries are excluded.
- Posted entries are immutable; corrections use reversal entries, never silent edits/deletes.
- Use existing `finance.read` and `finance.manage`; writes only through permission-checked RPCs. Do not expose direct table writes from browser clients.

## 5. Security / RLS design requirements

- Composite FK `(branch_id, organization_id)` → `branches(id, organization_id)` prevents cross-organization branch references.
- Every query and RPC takes organization scope from the active org, then validates membership and permission on the server.
- Read: `private.is_org_member(organization_id)` plus `private.has_org_permission(...)`; branch-scoped reads also require `private.has_branch_access(...)` as appropriate.
- Mutation: permission-checked server-side RPC; audit event written in the same transaction.
- Approval: requester cannot approve their own request; enforce this server-side, not only in UI.
- Use `SECURITY DEFINER` only where required, in the non-exposed `private` schema, with fixed search_path, explicit `auth.uid()` and permission checks. Review grants and function body before release.
- Any public view used by the browser must be `security_invoker=true` on PostgreSQL 15+ and still have appropriate grants/RLS.
- No service-role key in browser code.

## 6. Required before schema migration

1. Confirm whether target metrics should be operational quantities, revenue, or both.
2. Confirm whether financial reporting is cash register only or double-entry accounting.
3. Confirm target approval thresholds and who can approve; requester self-approval must be blocked.
4. Add proposed permission keys and role mappings through permission governance.
5. Write migration + rollback + RLS/RPC tests, then review advisors.
6. Apply only after explicit production release approval.

## 7. Current implementation boundary

Implemented on the development branch:
- Offline Bangladesh Division / District / Upazila cascading selector.
- Manual union/ward/area/postal/detailed address fields.
- Structured address saved in existing `branches.address` JSONB.

Not implemented:
- Target tables, target RPCs, finance ledger, financial report RPCs, approval integration for those new records.
- No production DB changes, migration application, merge or deployment.
