# First Platform Owner + Organization Owner Bootstrap v2 — DRAFT

Target project: MR RAHAMAN Business Ecosystem (`pojhrvmuamdejlutxpng`).
Target source branch: `feature/branch-module-v1`.

## Files
- `supabase/drafts/first_platform_owner_bootstrap_v2.sql` — corrected RPC draft; not applied.
- `supabase/functions/owner-bootstrap/index.ts` — server-side JWT allowlist wrapper; not deployed.
- `supabase/drafts/current_access_context_v1.sql` — signed-in user's Platform Owner and organization permission context; not applied.
- `supabase/tests/OWNER-BOOTSTRAP-TEST-PLAN.md` — staging test plan.
- `supabase/drafts/owner_bootstrap_v1_DO_NOT_APPLY.sql` — preserved historical draft; unsafe and not to be used.

## v2 corrections
- Uses the live catalogue: 41 permissions and 16 modules.
- Grants both the separate `platform_owner` platform role and `owner` organization role to the allowlisted, email-confirmed account.
- Grants the current 41 permission rows to the initial organization Owner.
- Enables the six actual `is_core=true` modules: organization_management, identity_access, branch_management, module_registry, approval_governance, audit_security.
- Uses a one-time advisory transaction lock and fails closed if any organization, member, or active Platform Owner already exists.
- Writes an append-only organization audit event in the same transaction.
- Creates no sample branch or business data.
- Keeps the service-role key server-side; never embed it in browser or Android code.

## Safety status
- SQL is a draft only; no Production migration has been applied.
- Edge Function is not deployed.
- No Owner or organization records have been created.
- Staging execution and real JWT tests remain mandatory before any Production decision.
