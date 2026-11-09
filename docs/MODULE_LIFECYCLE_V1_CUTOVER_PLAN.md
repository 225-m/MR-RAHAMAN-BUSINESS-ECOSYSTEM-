# Module Lifecycle V1 — Legacy RPC Cutover Plan

Project: MR RAHAMAN Business Ecosystem  
Branch: feature/customer-access-v1  
Status: preparation only; Production cutover NOT applied.

## Production risk identified

The current Production database still exposes the legacy functions:

- public.branch_module_set_enabled(uuid, boolean, text)
- private.branch_module_set_enabled(uuid, boolean, text)

The public wrapper is SECURITY INVOKER and delegates to the private implementation. Authenticated clients can execute both functions under the current grants. The legacy path checks module.manage but does not require an independently approved request, so it bypasses the new approval workflow.

The Branch Preview feature-branch source has been switched to the V1 RPCs. No current Branch Preview source call to branch_module_set_enabled remains. The client source has not been deployed to Production.

## Required V1 surface before cutover

1. Deploy and verify current_access_context_v1() for authenticated users only.
2. Deploy Module Lifecycle V1 schema, functions, RLS and grants.
3. Verify the three public V1 RPCs are executable by authenticated only:
   - module_request_change_v1
   - module_approval_decide_v1
   - module_apply_approved_change_v1
4. Verify private implementations are not directly executable by API roles.
5. Deploy the Branch Preview client that uses only the V1 RPCs.
6. Pass real GoTrue JWT/PostgREST/RLS tests, browser UI tests, and real Android browser/device smoke tests.
7. Confirm Last Active Owner protections and canonical Owner role mapping before any production governance migration.

## Cutover transaction

supabase/drafts/module_lifecycle_v1_cutover.sql now performs a preflight before revoking anything. It checks:

- current_access_context_v1() exists and is authenticated-only.
- All three V1 public RPCs exist and are authenticated-only.
- Authenticated cannot execute private lifecycle implementations.
- Authenticated has no direct INSERT/UPDATE/DELETE on organization_modules, module_change_requests or approval_requests.
- Legacy public/private RPC execution is revoked from PUBLIC, anon, authenticated and service_role.

The script is transactional. If a preflight or post-revocation assertion fails, the transaction aborts and the grant changes roll back.

## Fail-closed rollback

Use supabase/drafts/module_lifecycle_v1_fail_closed_rollback.sql only if the V1 client/RPC release must be stopped after cutover. It revokes the three V1 write wrappers and asserts the legacy RPCs remain disabled.

Do not restore execute grants on branch_module_set_enabled as an ordinary rollback. Doing so reopens the approval bypass. If V1 is defective, stop module writes and correct the V1 client/RPC before re-enabling the workflow.

## Current verification

- Module Lifecycle V1 disposable PostgreSQL tests: PASS in prior runs.
- Real GoTrue JWT/PostgREST/RLS suite: PASS in prior run.
- Playwright Chromium request/approve/apply and mobile viewport smoke test: PASS in Run #197.
- Last Active Owner and permission-floor PostgreSQL suite: PASS in Run #205.
- GitHub Actions Run #249 static-auth-check passed the updated Playwright UI test, Owner guard tests, bootstrap source checks, successful cutover + fail-closed rollback assertions, and a negative preflight test proving that a missing current_access_context_v1 aborts before legacy grants are changed. GitHub Actions Run #249 passed the full local GoTrue JWT/PostgREST/RLS suite with current_access_context_v1 assertions, followed by the cutover preflight and fail-closed rollback in the isolated local Supabase stack.
- No Production SQL, grants, deployment, or Pages publication was changed.

## Explicit release boundary

This plan is not authorization to apply Production SQL, deploy an Edge Function, publish GitHub Pages, merge PR #2, or bootstrap the first Platform Owner. Those are separate release actions after all tests and readiness reviews pass.
