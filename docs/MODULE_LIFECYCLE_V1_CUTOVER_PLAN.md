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
7. Install and test Last Active Owner guards, the nine-permission organization Owner floor, and audited single-slot Platform Owner handover; preserve canonical organization role_key = owner.
8. Complete physical Android Chrome smoke testing on a safe isolated preview URL.

## Cutover transaction

supabase/drafts/module_lifecycle_v1_cutover.sql now performs a preflight before revoking anything. It checks:

- current_access_context_v1() exists and is authenticated-only.
- All three V1 public RPCs exist and are authenticated-only.
- Authenticated cannot execute private lifecycle implementations.
- Authenticated has no direct INSERT/UPDATE/DELETE on organization_modules, module_change_requests or approval_requests.
- Last Active Owner guard triggers, Owner permission-floor triggers, Platform Owner audit table RLS, and least-privilege Owner handover RPC grants are present.
- Legacy public/private RPC execution is revoked from PUBLIC, anon, authenticated and service_role.

The script is transactional. If a preflight or post-revocation assertion fails, the transaction aborts and the grant changes roll back.

## Fail-closed rollback

Use supabase/drafts/module_lifecycle_v1_fail_closed_rollback.sql only if the V1 client/RPC release must be stopped after cutover. It revokes the three V1 write wrappers and asserts the legacy RPCs remain disabled.

Do not restore execute grants on branch_module_set_enabled as an ordinary rollback. Doing so reopens the approval bypass. If V1 is defective, stop module writes and correct the V1 client/RPC before re-enabling the workflow.

## Current verification

- Module Lifecycle V1 disposable PostgreSQL tests: PASS.
- Real GoTrue JWT/PostgREST/RLS authorization tests: PASS in Run #285.
- Last Active Owner guards, single-slot Owner handover, paired immutable grant/revoke audit events, and least-privilege Owner RPC grants: PASS in Run #285.
- Mocked Playwright Chromium requester/approver/applier/viewer and 390×844 mobile viewport suite: PASS in Run #285.
- Real Branch Preview UI against isolated local Supabase using GoTrue JWT sessions: PASS in [Run #299](https://github.com/225-m/MR-RAHAMAN-BUSINESS-ECOSYSTEM-/actions/runs/42559010963). Requester self-approval, independent approval, separate apply actor, branch.read-only viewer, and 390×844 layout all passed.
- The same Run #299 passed the complete local Supabase replay, GoTrue JWT/PostgREST/RLS suite, cutover transaction assertions, and fail-closed rollback assertions.
- Physical Android Chrome/device testing is outstanding. The checklist is [ANDROID_CHROME_SMOKE_TEST_PLAN.md](./ANDROID_CHROME_SMOKE_TEST_PLAN.md); mobile viewport emulation is not treated as a device test.
- Cutover preflight and fail-closed rollback assertions pass in the disposable environment. A negative preflight test proves that missing current_access_context_v1 aborts before legacy grants change.
- A fresh read-only Production inspection on 9 Nov 2026 confirms both legacy RPCs remain executable by authenticated; the public wrapper is SECURITY INVOKER and private implementation is SECURITY DEFINER. The V1 access-context, lifecycle and Owner handover RPCs are not installed in Production. organization_modules has RLS and authenticated SELECT only. Active Owners, Organizations and Organization Members remain zero.
- No Production SQL, grants, data, deployment, or Pages publication was changed.

## Explicit release boundary

This plan is not authorization to apply Production SQL, deploy an Edge Function, publish GitHub Pages, merge PR #2, or bootstrap the first Platform Owner. Those are separate release actions after all tests and readiness reviews pass.
