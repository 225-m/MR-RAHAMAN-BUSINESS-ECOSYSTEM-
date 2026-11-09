# Staging Readiness Review — 9 November 2026

Project: MR RAHAMAN Business Ecosystem  
Repository: `225-m/MR-RAHAMAN-BUSINESS-ECOSYSTEM-`  
Review branch: `feature/customer-access-v1`  
Supabase project: `pojhrvmuamdejlutxpng`  
Scope: read-only readiness review. No Production SQL, settings, users, or data were changed.

## Executive decision

**Cloud staging is not ready. Real JWT/RLS testing must not be pointed at Production.**

The Module Lifecycle disposable PostgreSQL CI passed in GitHub Actions Run #130, but that test is not a Supabase Auth/PostgREST integration test. The repository currently has no checked-in `supabase/config.toml` and no `supabase/migrations/` baseline. The connected Supabase account shows no dedicated staging project; the MR RAHAMAN project has only its default `main` branch. The other listed Supabase project is unrelated and must not be used for this project.

To respect the project's free-tier/no-cost requirement, do not create a Supabase cloud project or development branch as part of this work. Prepare a local Supabase CLI stack in CI instead, after a reproducible schema baseline is available.

## Checks completed

### CI

- GitHub Actions Run #130 completed successfully.
- Customer Access SQL disposable PostgreSQL tests: passed.
- Module Lifecycle V1 RPC/Test Suite disposable PostgreSQL tests: passed.
- Authentication Preview validation: passed.
- Branch Preview and Bangladesh location dataset validation: passed.
- Cleanup: passed.

Run: https://github.com/225-m/MR-RAHAMAN-BUSINESS-ECOSYSTEM-/actions/runs/42542629115

### Supabase environment inventory

- MR RAHAMAN project is active and healthy.
- No dedicated project named staging was found.
- Only the default Supabase branch `main` was listed for this project.
- No new project or branch was created; no cost was incurred.
- The separate project named `225-m's Project` is not part of this ecosystem and is excluded.

### Repository reproducibility gap

- `supabase/drafts/` and `supabase/tests/` exist.
- `supabase/config.toml` is absent.
- `supabase/migrations/` is absent from the active development branch.
- Production has 14 recorded migrations, but the full migration source chain is not checked into this repository.
- The current CI uses a hand-built disposable PostgreSQL fixture. It does not start Supabase Auth (GoTrue), PostgREST, or issue a GoTrue access token.

This is the main blocker for a trustworthy local JWT/RLS integration test. Do not create an incomplete baseline by copying only the Module Lifecycle fixture: it would not reproduce the real policies, helper functions, grants, triggers, Auth schema, and migration order.

### Production schema parity — read-only

The inspected Production tables and relevant columns are present for the current Module Lifecycle draft:

- `approval_requests`: request identity, target, JSON payload, status, required approvals, expiry and resolution fields.
- `approval_actions`: approval request, organization, actor, decision, comment and timestamp.
- `module_change_requests`: module, requester, current/proposed configuration, approval link, status and completion timestamp.
- `module_audit_logs`: actor, action, resource, old/new values, approval link and text request ID.
- `organization_modules`: status, installed version, configuration and enable/disable metadata.
- `module_dependencies`: mandatory flag and minimum version.
- Supporting organization, member, role and permission tables exist.

The relevant target tables all have RLS enabled. Their inspected policies are scoped SELECT policies; the `organization_modules` table grants `authenticated` SELECT only, with no direct authenticated INSERT/UPDATE/DELETE. This supports keeping all module state changes behind reviewed RPCs.

### Critical Production blockers still present

- `module_request_change_v1`, `module_approval_decide_v1`, and `module_apply_approved_change_v1` do not exist in Production.
- `current_access_context_v1` does not exist in either `public` or `private`.
- The legacy `public.branch_module_set_enabled(uuid,boolean,text)` remains executable by `authenticated` and `service_role`.
- The private legacy `private.branch_module_set_enabled(uuid,boolean,text)` is SECURITY DEFINER and remains executable by `authenticated`. The public wrapper is SECURITY INVOKER, so authenticated callers can reach the privileged private implementation.
- Production currently has zero organizations and zero organization members. There are no real tenant identities/role assignments to exercise in a tenant-scoped JWT test.
- Supabase Security Advisor reports leaked-password protection disabled.

**Do not claim that Production approval enforcement is complete. Do not run the legacy RPC cutover until every client has moved to V1 and the isolated integration suite passes.**

## Local Supabase JWT/RLS test plan

After restoring a reproducible schema baseline, add a separate CI job that starts a local Supabase stack using the Supabase CLI and Docker. It must not link to or connect to the Production project.

1. Start local Postgres, Auth (GoTrue), and PostgREST using checked-in config and migrations.
2. Apply the schema baseline and the Module Lifecycle V1 draft migration to the local database only.
3. Seed disposable organization/module/role/permission fixtures and create separate test users through the local Auth API.
4. Sign in through local Auth to obtain actual access tokens; call PostgREST RPC endpoints with the publishable/anon key plus each user's bearer token.
5. Verify unauthenticated denial, requester permission, self-approval denial, independent approver decision, separate apply permission, revoked approver permission, expired/rejected request denial, dependency enforcement, replay denial, and audit chain.
6. Verify cross-organization SELECT isolation and that authenticated clients cannot directly mutate `organization_modules`.
7. Verify private implementation RPCs are not executable by `authenticated`, and only the intended public wrappers are executable.
8. Run the legacy cutover script only inside the disposable local database and prove the old public/private RPCs are no longer executable by API roles.
9. Tear down the local stack and ensure no secrets or test users are committed.

## Exit criteria before any Production cutover

- [ ] Reproducible checked-in schema baseline and Supabase CLI config.
- [ ] Local GoTrue-issued JWT + PostgREST/RLS integration suite passes in CI.
- [ ] Actual Branch Preview/client uses the V1 Request → Independent Approval → Apply RPCs.
- [ ] Real browser/Android smoke tests pass against an isolated test environment.
- [ ] Legacy RPC cutover script passes in isolation and rollback steps are reviewed.
- [ ] Owner lockout safeguards and audit coverage are tested.
- [ ] Explicit user authorization is obtained before any Production migration or deployment.

## Current status

**CI fixture tests: PASS. Cloud staging readiness: BLOCKED. Production cutover: NOT AUTHORIZED / NOT APPLIED.**

Next engineering task: reconstruct and review the complete, reproducible Supabase schema baseline from the existing migration history without changing Production, then add the local Supabase Auth/JWT/RLS CI job.
