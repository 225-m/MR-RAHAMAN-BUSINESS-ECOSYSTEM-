# Module Registry Alignment & Lifecycle Gap Review
**Project:** MR RAHAMAN BUSINESS ECOSYSTEM  
**Branch:** `feature/authentication-v1`  
**Review type:** Read-only source/database inspection; no production data or schema changed.

## 1. Verified UI-to-registry mismatch
The current authentication preview presents 12 business-facing tiles. The Supabase catalog has 16 entries: 6 core, 8 business and 2 platform. These are different classification layers, so they must not be forced into a one-to-one match.

| Current UI tile | Existing registry mapping | Decision |
|---|---|---|
| Finance & Accounting | `finance_accounting` | Direct match |
| HR & Payroll | `hr_payroll` | Direct match |
| Inventory & Warehouse | `inventory_management` | Direct match |
| Purchase & Supplier | `purchase_management` | Direct match |
| Sales & CRM | `sales_management` + `crm` | Split into two registry modules in UI or define a deliberate combined presentation |
| Dairy Management | No registry entry | Candidate future business module |
| Manufacturing | No registry entry | Candidate future business module |
| Agriculture | No registry entry | Candidate future business module |
| Retail & Wholesale | No registry entry | Candidate future business module |
| Service & NGO Management | No registry entry | Candidate future business module |
| AI Business Assistant | No registry entry | Candidate future module; isolate AI/provider secrets and data permissions |
| Admin & Security Management | Core capabilities already exist as separate modules | Must not be added as a tenant-disableable business module; present as a protected platform administration area |

The registry also contains `business_dashboard` and `reports_analytics`, which are not standalone tiles in the current 12-tile grid. The UI overview contains a dashboard and the platform services section contains shared reporting/BI language. Their routes and ownership need to be made explicit.

## 2. Existing module data and permission coverage
- 16 registry modules exist and are marked active at version 1.0.0.
- 41 permissions exist and are linked by `permissions.module_key`.
- Permission coverage is uneven by design today: for example, dashboard and reports have read-only permissions; CRM, finance, HR, inventory, purchase and sales have read/manage pairs.
- The six core modules have permissions for organization/branch/member/role/module/approval/audit/security operations.
- Do not automatically grant permissions or create missing permission keys until each module's actual operations and role model are specified.

## 3. Existing database ownership evidence
The public schema currently contains the following Core Foundation tables:
- Organization & identity: `organizations`, `organization_members`, `organization_invitations`, `app_roles`, `role_permissions`, `permissions`, `platform_admin_roles`, `member_branch_access`.
- Branch management: `branches`, `branch_profiles`, `branch_contacts`, `branch_operating_hours`, `branch_settings`.
- Module registry: `platform_modules`, `module_dependencies`, `organization_modules`, `module_change_requests`.
- Approval & audit: `approval_requests`, `approval_actions`, `module_audit_logs`.

These tables establish the platform foundation, but they do not prove that the business module data models are implemented. The current UI itself describes the business tiles as introductory placeholders.

## 4. Lifecycle implementation gap — important
Read-only inspection found a specific server-side function, `private.branch_module_set_enabled(organization_id, enabled, reason)`, plus a public wrapper `branch_module_set_enabled`. It:
- checks `module.manage` and requires a reason;
- checks mandatory dependencies before enabling Branch Management;
- writes the organization module state and an audit log.

However, this is a **Branch Management-specific** lifecycle function, not a general module lifecycle engine. The inspected function does not implement:
- a generic module key/id lifecycle API;
- reverse-dependency checks before disabling a required module;
- cycle detection for the dependency graph;
- approval-request enforcement before executing a module change;
- a universal guard against disabling core modules;
- explicit installed/disabled/archived states with retention/export semantics.

A trigger named `private.branch_module_write_guard` blocks branch table writes when Branch Management is disabled. Its behavior and coverage across every branch-owned table need to be tested. It is not evidence of complete generic module isolation.

## 5. Dependency policy — proposed, not yet applied
Use these dependency principles when the dependency graph is implemented:
1. Every tenant module requires active `organization_management` and `identity_access` foundations.
2. Every module lifecycle action is governed by `module_registry`, `approval_governance` and `audit_security`; these are platform services, not ordinary tenant dependencies that can be switched off.
3. `business_dashboard` and `reports_analytics` are read-model consumers. They may consume enabled modules but must not own or mutate source transactions.
4. `sales_management` and `purchase_management` may integrate with `inventory_management` and `finance_accounting` through explicit optional adapters. Do not make these hard dependencies unless the business workflow requires them.
5. `crm` may be used independently; sales can optionally link customer IDs through the CRM contract.
6. `file_documents` and `notifications` are shared platform services. Consumers should degrade gracefully if these optional services are unavailable.
7. Detect dependency cycles before accepting any graph change.
8. Before disabling module X, reject the action if any enabled module has a mandatory dependency on X. Offer an approved dependency-aware disable plan instead of cascading changes.
9. Never delete module-owned rows during disable. Keep data export, retention and eventual archive separate from enable/disable.

## 6. Next implementation tasks
1. Inventory all current routes, UI tiles, RPCs and tables; create one authoritative module manifest.
2. Decide whether Sales & CRM remains a combined UI group or two independently controlled modules.
3. Add candidate module definitions only after their ownership, data model, permissions, and MVP scope are approved in the architecture—not by simply creating empty active registry entries.
4. Implement generic lifecycle RPCs with authorization, approval enforcement, dependency validation, cycle detection, transaction safety and append-only audit.
5. Add a lifecycle test matrix: enable with dependencies satisfied; enable with missing dependency; disable with active mandatory dependents; core disable attempt; unauthorized actor; repeated request; failure rollback; historical data retained.
6. Test all branch-owned write paths while Branch Management is disabled, not just the existing branch trigger.
7. Keep all tests in a non-production environment until backup/restore readiness is verified.

## 7. Change-control result
No database migration, row insert/update/delete, authentication setting change, GitHub deployment, or main-branch change was made during this review. This document is an implementation specification and gap report only.
