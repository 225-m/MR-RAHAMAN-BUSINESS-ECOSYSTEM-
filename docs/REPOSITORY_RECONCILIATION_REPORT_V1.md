# MR RAHAMAN Business Ecosystem — Repository Reconciliation Report v1

**Canonical repository:** 225-m/MR-RAHAMAN-BUSINESS-ECOSYSTEM-  
**Canonical production branch:** main  
**Reconciliation source:** feature/branch-module-v1  
**Target Supabase project:** pojhrvmuamdejlutxpng  
**Review mode:** GitHub source inspection + read-only live Supabase catalogue checks  
**Status:** Draft report; no merge, deployment, or Production database mutation.

## 1. Branch topology verified

- main is the default branch.
- feature/authentication-v1 is 13 commits ahead of main (comparison at review time).
- feature/branch-module-v1 is 35 commits ahead of main and includes the authentication branch history (22 commits ahead of feature/authentication-v1).
- Therefore feature/branch-module-v1 is the single consolidated feature source for review. Do not merge both feature branches separately.
- The compare endpoint reports 17 added files relative to main. These include the preview UIs, design docs, data, SQL drafts, test plans, and Owner bootstrap draft.

## 2. Recovered artifacts to preserve

- .github/workflows/deploy-auth-preview.yml
- auth-preview/SETUP-BN.md
- auth-preview/index.html
- branch-preview/ARCHITECTURE-LOCATION-TARGET-FINANCE.md
- branch-preview/README-BN.md
- branch-preview/data/bangladesh-admin-hierarchy.json
- branch-preview/index.html
- branch-preview/migrations/branch-target-finance-draft.sql
- branch-preview/tests/LOCATION-TARGET-FINANCE-TEST-PLAN.md
- docs/APPROVAL_MODULE_LIFECYCLE_V1_IMPLEMENTATION_PLAN.md
- docs/AUTH_PREVIEW_SECURITY_REVIEW_V1.md
- docs/CORE_FOUNDATION_ARCHITECTURE_V1.md
- docs/MODULE_REGISTRY_ALIGNMENT_AND_GAPS_V1.md
- supabase/OWNER-BOOTSTRAP-README.md
- supabase/functions/owner-bootstrap/index.ts
- supabase/migrations/202611080001_owner_bootstrap_v1.sql
- supabase/tests/OWNER-BOOTSTRAP-TEST-PLAN.md

## 3. Live catalogue cross-check

Read-only query of the live target project confirms:
- 41 permission rows.
- 16 platform module rows.
- Six core modules: approval_governance, audit_security, branch_management, identity_access, module_registry, organization_management.
- Eight business modules and two platform modules.
No database changes were made.

## 4. Blocking findings — do not merge/deploy these drafts as-is

### Authentication preview
- The preview requires email AND phone confirmation, including phone_change OTP. Current user requirement is Phone OTP OFF.
- The preview does not implement a trusted database-backed platform role / organization membership / permission authorization gate.
- Its business workspace is a UI preview, not a complete live business application.
- Public signup abuse controls, redirects, email delivery and password protection configuration remain unverified.

### Owner bootstrap
- Draft SQL expects exactly 40 permissions; live project has 41.
- Draft enables five modules but lists business_dashboard as a required core module and omits approval_governance and module_registry from its list of six actual core modules.
- Draft explicitly creates an organization Owner and does NOT grant platform_owner. This does not satisfy a Platform Owner bootstrap request.
- Edge Function and SQL contain a hardcoded Auth UUID; it must be checked against the approved account from live Auth before use. Never infer/replace it from repository content.
- Uses auth.role() in the SQL role check; replace with a supported, verified service-role check pattern after reviewing current Supabase guidance.
- Audit, idempotency, last-owner safety and RPC security need a full staging test.
- No Owner role assignment has been made.

### Branch target & finance
- SQL is explicitly DRAFT ONLY and ends with ROLLBACK.
- New permission keys branch.target.read/manage are not in the current live permission catalogue.
- Approval RPC contract, accounting model, currency rules and RPC write paths are not yet implemented/verified.
- No migration should be applied until permission governance, RLS, RPCs, immutability, tests and rollback are complete.

### Approval / module lifecycle
- Prior read-only review identified an authenticated direct module lifecycle RPC that bypasses the proposed independent approval workflow.
- Do not revoke or replace it until client compatibility and replacement request→approval→apply RPCs are tested in staging.
- Dependency reverse checks, cycle detection, core-module protection and immutable audit need test coverage.

## 5. Source and deployment boundary

- The repository currently contains preview HTML and documentation, not a complete production web/Android app source tree.
- The authentication workflow deploys only a preview and is gated by ENABLE_AUTH_PREVIEW_DEPLOY=true; keep it disabled until the preview is corrected and explicitly approved.
- No package.json, pubspec.yaml, full app source, complete migration source history, or Android project was verified in the inspected paths.
- Never copy any MUHAIMIN Dairy source/data/configuration into this repository.

## 6. Reconciliation decision

1. Preserve feature/branch-module-v1 as the recovered consolidated source branch.
2. Keep all 17 artifacts intact; do not delete the feature branches.
3. Correct the security blockers in separate reviewed commits.
4. Build an authoritative module/permission manifest from live schema + source.
5. Run static checks and staging tests; obtain a full source and migration history before claiming app readiness.
6. Only then merge to main. This report does not authorize a Production migration or public deployment.

## 7. Verification statement

This report was committed only to feature/branch-module-v1. No merge to main, deployment, Supabase schema/data/Auth/role change, or repository deletion was performed.
