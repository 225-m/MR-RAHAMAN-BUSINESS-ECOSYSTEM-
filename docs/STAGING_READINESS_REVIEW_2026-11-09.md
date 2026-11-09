# Staging Readiness Review — 9 November 2026

Project: MR RAHAMAN Business Ecosystem  
Repository: `225-m/MR-RAHAMAN-BUSINESS-ECOSYSTEM-`  
Review branch: `feature/customer-access-v1`  
Supabase project: `pojhrvmuamdejlutxpng`  
Scope: read-only readiness review. No Production SQL, settings, users, or data were changed.

## Executive decision

**Cloud staging is not ready. Real JWT/RLS testing must not be pointed at Production.**

The Module Lifecycle disposable PostgreSQL CI passed in GitHub Actions Run #130, but that test is not a Supabase Auth/PostgREST integration test. The repository initially lacked a reproducible migration baseline. I recovered the 14 recorded SQL migration statements read-only from Production's `supabase_migrations.schema_migrations` history and committed them under `supabase/migrations/`; a local-only `supabase/config.toml`, JWT seed fixture, GoTrue/PostgREST test script, and CI job are now added on the feature branch. The connected Supabase account still shows no dedicated cloud staging project; the MR RAHAMAN project has only its default `main` branch. The other listed Supabase project is unrelated and must not be used for this project.

To respect the project's free-tier/no-cost requirement, no Supabase cloud project or development branch was created. The local Supabase CLI stack in CI has passed real GoTrue JWT/PostgREST/RLS tests, including current_access_context_v1 and fail-closed cutover checks. This proves the tested V1 database workflow in an isolated local environment; it does not mean the V1 RPCs are deployed to Production or that a hosted staging environment exists.

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
- The 14 migration SQL files were recovered from the Production migration-history `statements` arrays and added to `supabase/migrations/` on the feature branch. A keyword scan found no password, secret, service-role key, JWT-secret or API-key assignments in those SQL statements.
- `supabase/config.toml` now configures an isolated local Supabase stack with Auth enabled and email confirmations disabled only for local tests.
- A new CI job starts local Supabase, replays the checked-in migrations, applies the Module Lifecycle draft, creates users through local GoTrue, and exercises RPCs through PostgREST using issued access tokens.
- The local GoTrue JWT/RLS job now passes in GitHub Actions Run #249. It starts an isolated Supabase stack, replays all 14 migrations, applies the Module Lifecycle and current_access_context_v1 drafts, creates users through GoTrue, obtains access tokens, verifies caller-scoped access context and permission derivation, then exercises Request → Independent Approval → Apply through PostgREST. It also runs the cutover preflight and fail-closed rollback in the isolated database.

Run: https://github.com/225-m/MR-RAHAMAN-BUSINESS-ECOSYSTEM-/actions/runs/42548461264

The schema baseline now replays successfully under the local Supabase CLI. GoTrue-issued JWTs exercise the expected PostgREST/RLS controls in CI. The restored migration files are a development/test baseline and were not applied to Production.

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

## Local Supabase JWT/RLS test results

GitHub Actions Run #160 passed the isolated local Supabase integration job. It did not connect to Production and did not create a cloud staging project.

- Replayed all 14 checked-in migration files into local Supabase Postgres.
- Started local Auth (GoTrue) and PostgREST; created disposable users through GoTrue and obtained access tokens.
- Called the three Module Lifecycle RPCs through PostgREST with each user's bearer token.
- Verified unauthenticated denial (401), missing request/approval permissions, self-approval denial and pending-apply denial.
- Verified independent approval, separate apply actor, revoked approver permission revalidation and replay denial.
- Verified cross-organization SELECT isolation and direct authenticated `organization_modules` UPDATE denial (403).
- Verified request/approval/apply audit chain, mandatory dependency enforcement, rejection and expiry denial.
- Verified private implementations are not executable by `authenticated`, while only the intended public wrappers are executable.
- Ran the legacy RPC cutover draft in the disposable local database; its assertions passed.
- Local stack teardown completed successfully.

Run: https://github.com/225-m/MR-RAHAMAN-BUSINESS-ECOSYSTEM-/actions/runs/42544295546

The CLI initially warned that several service-exclusion labels were invalid; those exclusions were ignored, but the local stack, migration replay, integration tests and teardown all completed successfully. This is a CI efficiency cleanup, not a failed security assertion.

## Exit criteria before any Production cutover

- [x] Reproducible checked-in schema baseline and Supabase CLI config.
- [x] Local GoTrue-issued JWT + PostgREST/RLS integration suite passes in CI.
- [x] Branch Preview source now uses the V1 Request → Independent Approval → Apply RPCs on the feature branch; deployment and runtime verification remain outstanding.
- [ ] Real browser/Android smoke tests pass against an isolated test environment.
- [x] Legacy RPC cutover script passes in the disposable local database; Production rollback/cutover review remains outstanding.
- [ ] Owner lockout safeguards and audit coverage are tested.
- [ ] Explicit user authorization is obtained before any Production migration or deployment.

## Current status

**Disposable PostgreSQL CI: PASS. Local Supabase schema replay: PASS. GoTrue JWT/PostgREST/RLS integration: PASS (Run #160). Local legacy cutover assertions: PASS. Cloud staging: NOT CREATED. Production cutover: NOT AUTHORIZED / NOT APPLIED.**


## Branch Preview Module Lifecycle UI integration — feature branch

The Branch Preview source at branch-preview/index.html now includes an organization-scoped Module Lifecycle panel.

- Request controls are gated by module.read + module.request.
- Independent approval controls are gated by approval.read + approval.approve, and the UI hides self-approval.
- Apply controls are gated by module.read + approval.read + module.manage and appear only for linked approved requests.
- The UI calls only module_request_change_v1, module_approval_decide_v1, and module_apply_approved_change_v1.
- The UI does not call branch_module_set_enabled and does not directly mutate lifecycle tables.
- The source passed a local JavaScript parse check, duplicate-ID check, DOM-reference check, and static V1 permission/RPC assertions. GitHub Actions Run #249 passed both jobs. Static validation includes the Playwright Chromium UI test, Owner permission-floor PostgreSQL tests, Owner bootstrap isolation checks, successful cutover/rollback assertions, and a negative preflight test proving missing current_access_context_v1 aborts before legacy grants change. The Playwright test verifies requester self-approval is hidden, a separate approver can approve, a separate apply actor can Apply, unauthorized controls stay hidden, and a 390×844 mobile-sized viewport has no horizontal overflow. This is mobile viewport emulation, not a real Android device test.

Implementation notes: docs/BRANCH_PREVIEW_MODULE_LIFECYCLE_V1.md.

## Last Active Owner protection — draft

Read-only Production schema review confirmed that platform_admin_roles, app_roles and organization_members have no existing last-owner protection triggers. The Production inventory currently contains zero platform Owner rows, zero organizations and zero organization members.

A separate draft, supabase/drafts/last_active_owner_guard_v1.sql, and disposable fixture/tests have been added on the feature branch. The draft protects the last active platform_owner and canonical organization role_key owner against revoke, expiry, demotion, suspension, deletion and role deactivation. Advisory transaction locks are used to serialize concurrent removal attempts.

The draft now defines a nine-permission governance floor for organization Owner roles and adds triggers to reject incomplete Owner assignment and removal of required grants from the final complete Owner role. Disposable tests now include those paths. GitHub Actions Run #205 passed the expanded disposable PostgreSQL Owner permission-floor suite, including incomplete Owner assignment denial and blocking removal of a required permission from the final complete Owner role. The 14 recovered migrations contain no organization Owner seed because Production has no organizations or members. The V2 first-owner bootstrap defines role_key = owner, matching the Owner guard's canonical V1 contract. Owner protection remains a draft and must not be applied to Production.

Details: docs/LAST_ACTIVE_OWNER_GUARD_V1.md.

## Remaining work

1. Preserve the V1 canonical organization Owner key role_key = owner in all future role seeds and bootstrap code.
2. Verify the new platform_owner_management_v1.sql integration tests. The draft now provides active-Owner-only single-slot handover RPC, an append-only platform audit log, and an Owner-only audit-list RPC; direct API-role table access is revoked.
3. Perform real Android Chrome/device smoke tests. The 390×844 Playwright viewport test is not a physical Android device test.
4. A full browser-to-local-Supabase session integration is still outstanding: the Playwright UI test uses a mocked client, while the separate local GoTrue JWT/PostgREST/RLS suite verifies real database authorization.
5. Re-review the final legacy cutover plan against every deployed client and scheduled/Edge Function consumer. Keep Production unchanged until a separately approved release.
6. Production cutover/deployment remains unauthorized and unapplied.

Production remains unchanged.
