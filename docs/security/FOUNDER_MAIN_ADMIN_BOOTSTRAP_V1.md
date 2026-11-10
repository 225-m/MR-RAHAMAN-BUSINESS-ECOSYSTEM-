# Founder & Main Admin Bootstrap — Security Design (V1)

Status: design draft only. No production database, auth, role, grant, or deployment changes are made by this document.

Repository: 225-m/MR-RAHAMAN-BUSINESS-ECOSYSTEM-
Base: feature/customer-access-v1
Working branch: feature/founder-owner-bootstrap-v1
Supabase project: pojhrvmuamdejlutxpng

## 1. Required identity

The first authorized account is to be recorded as:

- Designation: Project Founder
- Administrative title: Main Admin
- Platform role: platform_owner
- Scope: MR RAHAMAN Business Ecosystem only

The Founder designation is a durable historical identity record. It is distinct from the operational platform_owner role and from organization membership. It must never be inferred from editable user metadata, a display name, an email address supplied by the browser, or a client-side flag.

The Founder identity should remain in the audit/history record even if administrative access is later suspended through a formally authorized security process. The active platform_owner role controls privileged access; the Founder record preserves who founded the project. The application must not silently transfer or overwrite the Founder identity.

## 2. Verified read-only findings (10 Nov 2026)

- Supabase Auth currently contains one account.
- That account's email identity is verified.
- There are currently no active platform admin role rows.
- There is no existing platform_owner row.
- No organization membership for the first account was found in the prior read-only review.
- public.current_access_context_v1() is absent.
- public.platform_owner_grant_v1() and related Owner grant/revoke RPCs are absent.
- public.module_audit_logs already exists and is append-only; it is organization-scoped and suitable for the initial organization bootstrap event.
- public.platform_audit_logs is absent in Production, but the existing platform_owner_management_v1 draft defines a separate append-only platform audit table with actor, target, action, reason and before/after JSON. The V3 Founder bootstrap must be ordered after that draft.
- platform_admin_roles has a CHECK constraint allowing platform_owner, platform_admin, security_admin, support_admin.
- A partial unique index enforces at most one active platform_owner.
- RLS policy platform_admin_roles_deny_client_access denies direct anon/authenticated table access.
- Frontend auth-preview/index.html calls current_access_context_v1() and opens the workspace only when is_platform_owner=true or an active organization permission includes dashboard.read.
- The current frontend correctly fails closed while the access-context RPC is missing.

All findings above are read-only observations. Recheck them immediately before preparing a deployable migration.

## 3. Safe first-owner bootstrap

The first-owner grant must not be performed by frontend JavaScript or by an authenticated user's direct table insert.

Required flow:

1. User signs in through Supabase Auth.
2. A server-side Edge Function validates the request using a dedicated one-time bootstrap secret stored only in server-side environment secrets.
3. The Edge Function independently fetches the authenticated user's account from Supabase Auth Admin API and requires a verified email.
4. The target account is pinned by a pre-reviewed immutable Auth UUID and normalized email allowlist stored server-side. Do not accept target UUID/email from request JSON as authority.
5. The function invokes a tightly scoped, transactional database routine using server credentials. No service-role key or bootstrap secret may reach the browser.
6. The database routine acquires an advisory transaction lock, verifies that no active platform_owner and no prior founder bootstrap exists, verifies the target auth user, inserts the Founder identity and platform_owner role, and writes the audit event in the same transaction.
7. If any precondition or audit insert fails, the transaction rolls back in full.
8. Mark bootstrap as consumed atomically. Replays and concurrent requests must fail safely.
9. Disable/remove the bootstrap endpoint and rotate/delete the one-time secret after verified success.
10. Refresh the user's session/access context and confirm the database-derived is_platform_owner=true before opening the Admin Dashboard.

Do not create an organization membership until organization status, system role definitions, permission mappings, and organization bootstrap rules have been independently verified. Platform Owner access must not depend on a guessed organization role.

## 4. Founder identity data model

Before writing migration SQL, inspect existing schema conventions and choose a collision-free table name. Proposed logical record:

- founder_id (UUID primary key)
- user_id (UUID, FK to auth.users, restrictive delete behavior)
- designation_key (fixed value: project_founder)
- administrative_title (fixed value: main_admin)
- project_key (fixed value identifying MR RAHAMAN Business Ecosystem)
- designated_at (server timestamp)
- designated_by (nullable for the first bootstrap, or a controlled system actor)
- bootstrap_event_id (FK to the audit event, if supported)

Enforce exactly one founder record for this project with a unique constraint/index. Deny direct client writes and reads unless an explicit, minimal read policy is required. Do not put this authorization in user_metadata.

The platform_owner role remains in public.platform_admin_roles. The Founder record is not a substitute for role authorization.

## 5. Access context RPC

Implement public.current_access_context_v1() only after reviewing the existing permission helpers and all dependent grants.

Expected result must include at least:
- is_platform_owner: boolean derived from a current, non-revoked, non-expired platform_owner role
- organizations: only active memberships with active organization and role
- each organization's permissions derived from trusted database role_permissions
- is_customer/customer_profile only if the customer model is verified and kept separate from admin access

The function must:
- derive identity from auth.uid(), never from caller-supplied user_id;
- reject anon/no-session calls;
- use a fixed safe search_path;
- qualify object names;
- expose only the minimum needed fields;
- have EXECUTE revoked from PUBLIC and anon, and granted only to authenticated where appropriate;
- never trust raw_user_meta_data for roles or permissions.

Review SECURITY DEFINER necessity carefully. If used, use a non-exposed private implementation and a narrow public wrapper, with explicit auth.uid() checks and least-privilege grants.

## 6. Audit requirements

Use the dedicated public.platform_audit_logs table defined by platform_owner_management_v1 for platform_owner.granted, with the Founder designation ID and Main Admin title in new_values. Also write the organization bootstrap event to public.module_audit_logs with the new organization_id. Both inserts and the Founder/Owner/org records must commit or roll back together. Record at minimum:
- event type (founder.designated / platform_owner.granted)
- target user UUID
- actor/system actor
- timestamp
- request/correlation ID
- reason and bootstrap version
- outcome

Audit insert and role/founder insert must be atomic. Audit history must be append-only to application roles; prevent clients from updating/deleting it. Never store passwords, API keys, bootstrap secrets, or access tokens in audit payloads.

## 7. Safety invariants

- No employee/admin/customer can self-promote.
- No client-side request can create or modify platform_owner.
- Only the approved one-time bootstrap identity can receive the first Founder + Main Admin designation.
- At most one active platform_owner, consistent with the existing unique index.
- Prevent accidental lockout of the last active Owner.
- Every grant/revoke is audited.
- Role changes trigger permission revalidation.
- Founder identity is durable and cannot be silently reassigned.
- Fail closed if the access-context RPC, role row, permission map, or audit path is missing.
- Do not change unrelated module lifecycle RPCs in this workstream.

## 8. Required tests before any production deployment

1. Verified allowlisted account succeeds exactly once.
2. Unverified account is rejected.
3. Wrong UUID/email is rejected even if supplied in request body.
4. Any authenticated non-allowlisted account is rejected.
5. Repeated bootstrap is rejected without duplicate rows.
6. Two concurrent bootstrap attempts produce one success only.
7. Failure during audit insert rolls back both Founder and Owner inserts.
8. Browser cannot read/write platform_admin_roles or Founder table directly.
9. An employee/customer cannot invoke the bootstrap or grant/revoke RPC.
10. Expired/revoked Owner role does not grant access.
11. Current Owner receives is_platform_owner=true and Admin Dashboard access after session refresh.
12. Ordinary verified customer remains in customer-only access and cannot see Admin Dashboard.
13. Last active Owner cannot be revoked by ordinary admin paths.
14. Founder designation remains historically visible after an authorized role suspension.
15. Browser and Android tests verify the same access decisions.

## 9. Current blockers before a deployable SQL migration

- The existing module_audit_logs is append-only and can record the organization bootstrap. The separate platform_audit_logs table must be created by the reviewed Platform Owner Management draft before the Founder bootstrap is run.
- Existing repository drafts include a customer-aware private.current_access_context_v1() and public SECURITY INVOKER wrapper. A separate Founder extension draft now adds is_project_founder and platform_title without replacing the customer contract.
- current_access_context_v1() and platform_owner grant/revoke RPCs are absent.
- Organization system role keys and exact role_permissions schema/constraints still need full inspection.
- Need inspect all RLS policies, table grants, function EXECUTE grants, and helper-function definitions.
- Need confirm the exact Auth UUID server-side and pin it in the one-time deployment configuration; never hardcode it in public source.
- Need write and run local/test-project migration and negative security tests before production.

## 10. Implementation artifacts created on feature/founder-owner-bootstrap-v1

- supabase/drafts/first_project_founder_main_admin_bootstrap_v1.sql — creates a private, append-only Founder designation and a one-time service_role-only bootstrap RPC that creates Founder + Main Admin + platform_owner + organization Owner atomically.
- supabase/drafts/founder_access_context_extension_v1.sql — extends the existing customer-aware access context with is_project_founder and platform_title.
- supabase/functions/owner-bootstrap/index.ts — updated to call the new V1 RPC; still requires server-side allowlist secrets and is not deployed.
- auth-preview/index.html and supabase/functions/auth-preview/index.ts — UI source and generated Edge Function source now display the database-verified Founder/Main Admin title when the access context returns it.

These are source-branch drafts only. The earlier V2 draft remains unchanged for traceability and must not be used for the new Founder designation.

## 11. Release boundary

This branch contains a design document only. Do not apply a migration to production, grant roles, change RLS, deploy a bootstrap Edge Function, or open the Dashboard until the migration, rollback, and tests are reviewed and pass. Production changes require a separately reviewed release step.
