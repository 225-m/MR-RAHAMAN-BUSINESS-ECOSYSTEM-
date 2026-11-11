# Core Foundation Architecture v1
**Project:** MR RAHAMAN BUSINESS ECOSYSTEM  
**Scope:** Architecture baseline only; no production schema/data changes are included in this document.  
**Reviewed against:** Supabase project `pojhrvmuamdejlutxpng`, migration history through `20261102114421`, Git branch `feature/authentication-v1`.

## 1. Architectural decision
Build the platform as a modular monolith with a shared Core Foundation and independently governed feature modules. Modules communicate through documented database/API contracts and permission keys, not by reaching into another module's private implementation. A module can be disabled without deleting its records, audit history, configuration, or files.

## 2. Core Foundation (six mandatory platform capabilities)
| Module key | Responsibility | Owns / governs |
|---|---|---|
| `identity_access` | Authentication-to-application identity mapping, memberships, invitations, roles, permissions, branch access | Auth identity references, organization membership, role assignments, access grants |
| `organization_management` | Organization lifecycle and tenant boundary | Organizations and organization-level profile/configuration |
| `branch_management` | Branch directory, profile, contacts, hours, settings and branch access | Branch records and branch-scoped profile/configuration |
| `module_registry` | Module catalog, versions, dependencies, installation and enable/disable lifecycle | Platform module catalog, dependency graph, organization module state |
| `approval_governance` | Approval requests, decisions and controlled change execution | Approval requests and approval actions |
| `audit_security` | Append-only audit trail, security events and review evidence | Audit records and security review metadata |

All six are platform-critical. They must not be tenant-disableable through ordinary module controls. Access to them is still permission-controlled.

## 3. Shared contracts
- **Identity contract:** a valid Supabase Auth session is authentication only. Business access additionally requires a non-revoked Platform Owner grant (for platform-wide administration) or an active organization membership with role permissions. Do not authorize from user-editable metadata.
- **Tenant contract:** every organization-owned record carries `organization_id`; branch-owned records carry both `organization_id` and `branch_id`. Composite foreign keys must preserve same-organization references.
- **Permission contract:** stable keys use `module.resource.action` naming (for example, `branch.branch.update`). UI visibility is not authorization; database policies/RPCs enforce the same permission.
- **Change contract:** sensitive writes use validated server-side RPC/service functions, approval where policy requires it, and an audit record containing actor, organization, action, target, reason/request ID and outcome.
- **Module contract:** modules expose a manifest (key, version, category, required permissions, dependencies, owned tables, routes/API surface, feature flags and export procedure). Cross-module calls use public contracts only.
- **Configuration contract:** organization/branch settings are validated against a versioned schema. Secrets are never stored in browser-readable configuration.
- **Time/money contract:** default organization timezone is Asia/Dhaka and currency BDT, but calculations and storage remain explicit; timestamps use timestamptz and money fields use fixed-precision numeric with currency context.

## 4. Module lifecycle and data safety
Target lifecycle: **available → install-requested → installed-disabled → enabled → disable-requested → installed-disabled → uninstall-requested → archived**. Approval is required for privileged lifecycle changes. The exact state names must be reconciled with the existing schema before implementation.

Rules:
1. Disabling blocks new module operations and hides its routes; it does not delete, truncate, rewrite or detach historical data.
2. Existing records remain readable to authorized auditors and exportable by the organization.
3. Dependencies are checked before enable; reverse dependencies are checked before disable/uninstall.
4. Core modules cannot be disabled or uninstalled by tenant administrators.
5. Uninstall means detach application code/configuration only after export and retention checks; physical data deletion is a separate, exceptional, explicitly approved retention operation.
6. Every lifecycle transition is transactional, idempotent, authorized, reasoned and audited.
7. Failed transitions leave the prior state intact.

## 5. Current registry baseline observed
Supabase currently contains 16 catalog entries:
- **Core (6):** approval_governance, audit_security, branch_management, identity_access, module_registry, organization_management.
- **Business (8):** business_dashboard, crm, finance_accounting, hr_payroll, inventory_management, purchase_management, reports_analytics, sales_management.
- **Platform (2):** file_documents, notifications.

All 16 catalog entries were observed active at version 1.0.0. The only dependency row currently present is `branch_management → organization_management` (mandatory, minimum 1.0.0). No organization module installations, module change requests or approval requests were present at the time of inspection.

## 6. Known gaps before implementation
- Dependency metadata is incomplete: all business/platform modules need reviewed dependency declarations; reverse-dependency enforcement must be verified.
- The GitHub UI/catalog was previously observed to expose 12 business modules while the database registry contains 8. Inventory the actual UI routes and reconcile keys before adding or removing catalog entries.
- `organization_modules` has no tenant rows yet, so lifecycle behavior has not been runtime-tested.
- There are no organization or organization-member records and no Platform Owner role rows. The existing Auth user therefore must not be assumed to have business-owner authorization.
- Authentication preview still includes phone OTP despite the decision that OTP must remain OFF. The intended owner flow is email/password + email confirmation, followed by controlled server-side owner provisioning.
- Approval and audit tables exist but have no operational records yet. Approval-gated execution and append-only audit behavior require runtime tests.
- Backup retention and a restore test are not yet verified. No production migration or privileged bootstrap should run until recovery readiness is established.

## 7. Business module boundaries (initial ownership proposal)
| Module | Primary data domain | Expected dependencies |
|---|---|---|
| business_dashboard | Read-only KPI composition; no ownership of source transactions | identity_access, organization_management, reports_analytics |
| crm | Customers, contacts, follow-ups | identity_access, organization_management |
| finance_accounting | Accounts, journals, cash/bank, expenses | identity_access, organization_management; optional sales/purchase integrations |
| hr_payroll | Employees, attendance, payroll | identity_access, organization_management |
| inventory_management | Items, warehouses, stock movements | identity_access, organization_management |
| purchase_management | Suppliers, purchase orders, receipts | identity_access, organization_management; optional inventory/finance integrations |
| reports_analytics | Read-only reporting models and exports | identity_access, organization_management; source modules are optional providers |
| sales_management | Sales orders, invoices and customer transactions | identity_access, organization_management; optional inventory/finance integrations |
| file_documents (platform) | File metadata, ownership, retention and storage access | identity_access, organization_management |
| notifications (platform) | Delivery preferences, templates and notification logs | identity_access, organization_management |

This is a proposed boundary map, not proof that all listed domain tables or integrations already exist.

## 8. Implementation sequence
1. Complete a source/schema inventory and map every existing table, RPC, route and permission to one owner module.
2. Reconcile UI module keys with the 16-entry registry; preserve unknown/legacy routes until mapped.
3. Review and complete dependency metadata, including reverse-dependency checks and cycle detection.
4. Finish approval + audit execution contracts and test them with non-production fixtures.
5. Implement email-only owner provisioning with a deny-by-default bootstrap gate.
6. Run tenant-isolation, permission, module lifecycle, and failure/rollback tests.
7. Only after backup/restore readiness, prepare additive, reversible migrations and a reviewed pull request. Do not merge/deploy until tests pass.

## 9. Change-control statement
This architecture baseline does not authorize destructive data operations. No production rows, existing modules, user accounts, credentials, or business records are to be deleted or rewritten as part of the foundation work. Any schema change must be additive where possible, backed up, migration-tracked, tested, and accompanied by a rollback plan.
