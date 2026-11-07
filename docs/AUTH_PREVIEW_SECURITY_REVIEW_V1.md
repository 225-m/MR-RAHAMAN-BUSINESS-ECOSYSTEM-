# Authentication Preview & Recovered Bundle Security Review — v1

**Project:** MR RAHAMAN Business Ecosystem  
**Supabase project:** `pojhrvmuamdejlutxpng`  
**Repository branch reviewed:** `feature/authentication-v1`  
**Review mode:** static source inspection + read-only live Supabase metadata/migration inspection  
**Status:** findings only; no application deployment, SQL execution, database mutation, Auth setting change, or user/role provisioning performed.

## 1. Executive result

The recovered ZIPs are a **partial recovery**, not the complete application source. They contain a static HTML authentication preview, a draft 16-table core schema, security design notes, and read-only SQL checks. They do not contain the complete web/Android application, the full migration source history, the full Branch API implementation, or an Owner bootstrap implementation.

The authentication preview is not ready for deployment under the current user requirement because it requires both email and phone verification. The user has explicitly selected **Phone OTP OFF**. More importantly, the preview does not perform a database-backed Platform Owner or active organization membership/permission check. It keeps the business workspace hidden, but that is not a complete authorization gate.

## 2. Recovered ZIP contents and integrity boundary

Reviewed artifacts:
- `MR_RAHAMAN_Authentication_Preview_v1.zip`: `index.html` and `SETUP-BN.md`.
- `MR_RAHAMAN_Business_Ecosystem_Recovered_Source_Bundle.zip`: draft core schema, RLS/permission design, schema review, read-only preflight and post-migration verification SQL, README, and manifest.
- `mr_rahaman_phase2_security_schema_bundle_v1_1.zip`: duplicate schema/security design artifacts.

The bundle manifest and README explicitly identify the archive as `partial_recovery_not_complete_application_source`. The archive excludes complete frontend/Android source, full migration history, current schema/function/policy export, Owner bootstrap implementation, and build/test/deployment configuration. The separate Muhaimin Dairy archive is not part of this project and must not be mixed into this repository.

## 3. Authentication preview findings

### Positive findings
- Uses the target Supabase project URL and a browser-safe publishable key; no `service_role` or secret key was found in the preview.
- Supabase JS CDN is pinned to `2.118.0`.
- Supports email/password sign-up and login, email confirmation redirect, password recovery, and password update.
- Inline JavaScript syntax check passed in the recovered review.
- The UI comments correctly state that authentication is not the same as Platform Owner authorization.

### Blocking issues
1. **Phone OTP conflicts with the approved account policy.** The page includes phone registration, `updateUser({phone})`, and `verifyOtp({phone, token, type: "phone_change"})`. The access condition is `email_confirmed_at && phone_confirmed_at`. This contradicts Phone OTP OFF and must be removed from the authentication flow before deployment.
2. **No actual Platform Owner authorization check.** The `displayApp(user)` function only checks email and phone confirmation. It does not query `platform_admin_roles`, verify an active `organization_members` row, or check a role permission. The `accessPendingView` is a UI holding screen, not proof of authorization.
3. **No owner bootstrap or organization membership provisioning.** The preview has no secure bootstrap RPC or trusted server-side provisioning flow. A verified Auth account alone must never receive platform or organization privileges.
4. **Public signup abuse controls remain unverified.** CAPTCHA/abuse protection, rate limits, redirect allowlist, email delivery, and password protection settings need review before enabling public signup.
5. **The preview does not load business data.** Its workspace navigation is local UI only. It must not be described as a functioning business dashboard.

### Required authentication design
- Email/password authentication only for v1; keep Phone Auth/OTP disabled.
- After sign-in, resolve the user through trusted database authorization: active Platform Owner/Platform Admin grant where required, and/or active organization membership plus role-permission checks for tenant features.
- Deny by default if the authorization query/function fails, returns no eligible role, or the organization is suspended.
- Do not trust user-editable `user_metadata` for authorization.
- Keep platform roles separate from organization roles.
- Owner bootstrap must be one-time, server-side, concurrency-safe, audited, and unavailable to public signup.
- The one-person organization approval problem must be explicitly resolved (break-glass/second approver policy); do not silently allow self-approval.

## 4. Live Supabase metadata cross-check

Read-only inspection of project `pojhrvmuamdejlutxpng` confirmed:
- 14 recorded migrations, from `20261102112539_core_schema_v1_1_secure_rls_baseline` through `20261102114421_branch_audit_read_api_v1`.
- The 16 core tables named in the recovered schema draft are present in the live project.
- Four additional Branch extension tables are present: `branch_profiles`, `branch_operating_hours`, `branch_contacts`, and `branch_settings` (20 public tables in the inspected set).
- RLS is enabled on the inspected tables.
- The permission catalogue has 41 rows.
- The organization, organization-member, platform-admin-role, approval, module-change, organization-module, and module-audit business tables currently have no tenant/owner/workflow rows. This means a real tenant authorization or approval end-to-end test cannot yet be performed.
- The live migration history is not included in the recovered ZIP. The ZIP's draft schema is therefore not a replacement for the current database or migration history.

This metadata check does not prove all policies, grants, functions, and UI paths are secure. Those require separate targeted read-only inspection and later isolated integration tests.

## 5. Do not execute the recovered core schema draft

The file `mr_rahaman_core_schema_v1_1.sql` is explicitly marked DRAFT / NOT EXECUTED and uses `CREATE TABLE IF NOT EXISTS`. Since the corresponding tables already exist live, rerunning it would not reconcile differences between the draft and the actual tables. It is not an upgrade migration and must not be run against production.

The preflight and post-migration SQL files are SELECT-only diagnostics. The schema review itself says SQL parsing, target FK creation, migration execution, automated integration testing, backup/restore drill, and rollback rehearsal were not verified.

## 6. Required next steps, in order

1. Recover the complete frontend source and the full 14 migration files plus current Edge Functions/API implementation from the original repository/workspace.
2. Reconcile each migration and the actual live schema/functions/policies/grants; do not infer current implementation from the draft ZIP.
3. Replace the preview's phone-OTP flow with email-only authentication, preserving password recovery and secure session handling.
4. Implement and test the database-backed authorization gate and controlled first-owner bootstrap in an isolated staging database.
5. Resolve the single-owner approval policy and implement approval request/decision/apply as separate audited operations.
6. Run negative security tests (anonymous, authenticated non-member, cross-organization, suspended member, privilege escalation, self-approval, duplicate/concurrent approval).
7. Verify backup retention and perform a restore drill in an isolated project before any production migration or release.

## 7. Change and verification statement

No SQL was executed. No production data, schema, RLS policy, grants, Auth provider, secret, or user role was changed. No app deployment or merge to `main` was performed. This document records review findings only.


## 8. Follow-up repository and live RPC authorization review (2026-11-03)

### Repository branch/source discovery
- Enumerated all repository branches: only `main` and `feature/authentication-v1` were returned; no additional branch cursor remained.
- Checked both branches for `package.json`, `index.html`, `src/App.tsx`, `app/page.tsx`, `src/main.tsx`, and `supabase/config.toml`. These paths were not found on either branch.
- `README.md` on both branches contains only the repository title. This confirms that the complete app source was not found at these common paths in the two enumerated branches. It does **not** prove that no source exists in another repository, an unenumerated GitHub location, a differently named path, or the original local workspace.

### Live Branch module lifecycle RPC — confirmed approval bypass
Read-only inspection of `pg_get_functiondef`, function ACLs, and `pg_policies` confirmed:
- `private.branch_module_set_enabled(uuid,boolean,text)` is SECURITY DEFINER, has a pinned search_path, and is directly executable by `authenticated`.
- `public.branch_module_set_enabled(...)` is a SECURITY INVOKER wrapper and is also executable by `authenticated`.
- The private implementation checks `auth.uid()`, `module.manage` permission, a reason of at least five characters, and mandatory dependencies when enabling.
- It directly inserts/updates `organization_modules` and writes `module_audit_logs`. It does **not** create an approval request, require an independent approver, verify an approved request, or enforce requester/approver separation.
- Disable does not check whether another active module depends on Branch Management. The implementation also has no general protected-core-module rule (the current target is Branch Management, but the lifecycle pattern is unsafe to reuse for core modules).
- The function is therefore an authenticated direct path around the proposed approval workflow. The presence of the new approval tables and read-only RLS policies does not close this bypass.

Other inspected Branch SECURITY DEFINER routines (for example branch create/update/status) check authentication and organization/branch permissions and write audit rows. Their wrappers are SECURITY INVOKER. The inspected approval, module-change, organization-module, and module-audit tables expose scoped SELECT policies; no client-side write policy was found in that subset. This is not a complete audit of every table or every RPC.

### Required remediation — do not hot-fix production yet
1. Design the replacement request → independent approval → apply-approved-change RPC flow and test it in staging.
2. Make the apply function re-check current actor authorization, request status/expiry, non-self-approval, organization lock, module status, mandatory dependencies, reverse dependencies, dependency cycles, and protected-core rules inside one transaction.
3. Only after the replacement UI/API is deployed and tested, remove authenticated execution from the legacy direct lifecycle path and retire the old wrapper in a coordinated migration. Do not revoke it now because a client may still depend on it.
4. Preserve all module data on disable; change lifecycle status only and retain audit history.

**No production change was made during this follow-up.** The checks were read-only; no migration, grant, policy, function, Auth, role, or data mutation was executed.



## 9. Email-only authentication and database access-gate follow-up (2026-11-08)

- Removed registration phone field, phone verification panel, phone OTP handlers, phone confirmation requirement, and phone-specific user metadata from `auth-preview/index.html`.
- Registration/login/recovery remain email/password based. Email confirmation is still required.
- Added a client-side deny-by-default call to `public.current_access_context_v1()`. The preview will show the workspace only when the returned context confirms an active `platform_owner` grant or an active organization membership containing `dashboard.read`.
- The SQL function is stored as a draft at `supabase/drafts/current_access_context_v1.sql`; it has **not** been applied to Production. Until it is staged and deployed in a non-production project, the RPC call will fail and the preview deliberately keeps the dashboard closed.
- Live read-only checks confirmed 41 permission rows, 16 platform modules, zero active platform owners, zero organizations, and zero active organization memberships at review time.
- Existing private authorization helpers `private.is_org_member(uuid)` and `private.has_org_permission(uuid,text)` are present and derive access from active organization membership and role-permission links. No existing public RPC was found that returns the signed-in user's own platform role plus organization permission context, hence the new draft RPC.
- The current Owner Bootstrap draft remains unsafe/incomplete for use: it expects 40 permissions, enables five module keys (including a business module in place of core services), creates an organization Owner only, and does not grant `platform_owner`. It is not approved for Production execution.
- The client-side gate is only a navigation/workspace gate. Every business-data operation must continue to be enforced by RLS and permission-checking server RPCs; never rely on this UI gate as the security boundary.
- No Production SQL, Auth configuration, role, data, deployment, or `main` branch change was made in this follow-up.
