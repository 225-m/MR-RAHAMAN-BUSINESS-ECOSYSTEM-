# Founder / Main Admin V1 — Release Gate and Test Matrix

Status: **Draft / staging preparation only. Production remains unchanged.**

Repository: `225-m/MR-RAHAMAN-BUSINESS-ECOSYSTEM-`
Branch: `feature/founder-owner-bootstrap-v1`
Supabase project: `pojhrvmuamdejlutxpng`

## 1. Required deployment order (isolated staging first)

1. Reconfirm the schema and migration history against the target environment.
2. Apply and test `platform_owner_management_v1.sql` in isolated staging.
3. Apply and test `customer_access_v1.sql` in isolated staging.
4. Apply `first_project_founder_main_admin_bootstrap_v1.sql` in isolated staging only.
5. Apply `founder_access_context_extension_v1.sql` in isolated staging.
6. Configure the one-time Edge Function secrets server-side:
   - `OWNER_BOOTSTRAP_ALLOWED_USER_ID`: independently verified Auth UUID
   - `OWNER_BOOTSTRAP_ALLOWED_ORIGIN`: exact allowed origin
   - `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`
7. Deploy Edge Function only to staging with JWT verification enabled.
8. Execute all positive and negative tests below; inspect database rows and both audit streams.
9. Disable the bootstrap endpoint and rotate/remove the one-time secrets.
10. Only after review and a separately scheduled release should Production migrations be considered.

Do not run these draft files using the Production SQL editor, `apply_migration`, or an Edge Function deployment.

## 2. Confirmed schema compatibility

Read-only Production inspection on 10 Nov 2026 confirmed:

- `organizations`: organization_key, name, legal_name, status, timezone, currency_code, created_by.
- `app_roles`: organization_id, role_key, role_name, description, is_system, is_active.
- `role_permissions`: organization_id, role_id, permission_id; FK keeps role and organization aligned; unique (role_id, permission_id).
- `organization_members`: organization_id, user_id, role_id, member_status, invited_by, joined_at; active requires role_id.
- `organization_modules`: organization_id, module_id, status, installed_version, configuration, enabled_at, enabled_by.
- `platform_modules`: module_key, current_version, is_core, is_active.
- `module_audit_logs` is append-only and organization-scoped. Its INSERT path and platform event behavior must be tested under the bootstrap transaction.
- RLS is enabled on all six organization/role/audit tables inspected.
- Direct client access to `platform_admin_roles` is denied by RLS.

## 3. Critical release blockers

### A. Last active Platform Owner protection

The first version of `platform_owner_revoke_v1` could revoke the only active Owner, contradicting the required lockout protection. The draft has now been patched to reject revocation of the final active Owner. Ownership must be transferred through the audited transfer path instead. Re-test this in staging.

### B. Single active Platform Owner model

The current partial unique index permits at most one active `platform_owner`. The current `platform_owner_grant_v1` therefore transfers the existing Owner slot rather than creating a second concurrent Owner. The UI and product language must say **Transfer Platform Ownership**, not imply multi-owner grants. Do not change the unique index without a separate governance design and review.

### C. Bootstrap identity pinning

The Edge Function must fetch the Auth user from the supplied bearer token, compare the verified user UUID to the server-side allowlist, and never accept an identity from request JSON. The service-role key and allowlist must remain server-side. Verify that the Edge Function's exact origin check and JWT verification setting are active before deployment.

### D. Audit path

The Founder bootstrap requires `public.platform_audit_logs` from the Owner Management draft and writes the organization bootstrap event to `public.module_audit_logs`. Both inserts must succeed in the same database transaction as Founder, Owner, organization, role, permission, membership, and core-module creation. Any audit failure must roll back every write.

### F. Edge Function JWT and Auth confirmation configuration

The repository now explicitly sets `[functions.owner-bootstrap] verify_jwt = true` in `supabase/config.toml`. This is source configuration only and has not been deployed. The same setting must be confirmed in the staging deployment. The local Auth config currently has `enable_confirmations = false`; staging must enable email confirmations or use a deliberately verified test identity so the unverified-account negative test is meaningful. Do not assume local config proves the hosted project's Auth settings.

### G. Supabase Security Advisor

The latest read-only Security Advisor reports one warning: **Leaked Password Protection Disabled**. This is not a Founder bootstrap blocker, but should be enabled in Supabase Auth password security settings before public customer onboarding. No Auth setting was changed during this work.

### E. Full Owner permission mapping

The bootstrap currently grants all 41 existing permissions to the initial organization Owner role. Before staging execution, verify that all 41 permission keys are intentionally assigned to the Owner role, and confirm module-to-permission mapping. Do not infer that a count of 41 alone proves semantic correctness.

### F. Current access context

The Founder extension replaces the private implementation of `current_access_context_v1` while preserving the customer response contract. Compare it line-by-line with the Customer Access V1 function before staging. Confirm the public wrapper remains SECURITY INVOKER and that no client can directly read the private Founder table.

## 4. Staging test matrix

| ID | Scenario | Expected result |
|---|---|---|
| FND-01 | Allowlisted, verified Auth UUID calls bootstrap once | One Founder, one active platform_owner, one active organization Owner |
| FND-02 | Same account repeats bootstrap | Rejected; no duplicate rows |
| FND-03 | Unverified account | Rejected |
| FND-04 | Different verified account | Rejected by Edge Function allowlist |
| FND-05 | Request body attempts to override user UUID | Ignored; token identity and server allowlist decide |
| FND-06 | Authenticated client calls bootstrap RPC directly | Permission denied |
| FND-07 | Anonymous caller invokes bootstrap | Permission denied |
| FND-08 | Two concurrent bootstrap calls | Exactly one succeeds |
| FND-09 | Platform audit insert is forced to fail in staging | Entire transaction rolls back |
| FND-10 | Module audit insert is forced to fail in staging | Entire transaction rolls back |
| FND-11 | Client reads/writes private Founder table | Denied |
| FND-12 | Founder record exists but Owner role is revoked/expired | Founder title may remain historical; Admin dashboard access denied |
| FND-13 | Active Owner transfers to another verified account | Old Owner loses access; new Owner receives access; two audit events |
| FND-14 | Sole active Owner attempts revoke | Rejected; active Owner count remains one |
| FND-15 | Customer-only account requests workspace | Customer-only access; Admin dashboard denied |
| FND-16 | Suspended member / inactive role / inactive organization | Excluded from organization access context |
| FND-17 | Browser and Android use same signed-in identity | Same database-derived authorization outcome |
| FND-18 | Bootstrap Edge Function called from unapproved origin | Rejected |
| FND-19 | Bootstrap secret/Service Role key absent | Function fails closed |
| FND-20 | After successful bootstrap, endpoint and one-time secret removed | Further bootstrap attempts impossible |

## 5. Read-only preflight SQL

Run only in the intended staging database after applying the draft migrations:

```sql
select
  (select count(*) from private.platform_founder_designations
   where project_key = 'mr-rahaman-business-ecosystem') as founder_count,
  (select count(*) from public.platform_admin_roles
   where role_key = 'platform_owner'
     and revoked_at is null
     and (expires_at is null or expires_at > now())) as active_platform_owner_count,
  (select count(*) from public.organizations
   where organization_key = 'mr-rahaman-business-ecosystem') as organization_count,
  (select count(*) from public.organization_members m
   join public.organizations o on o.id = m.organization_id
   where o.organization_key = 'mr-rahaman-business-ecosystem'
     and m.member_status = 'active') as active_membership_count,
  (select count(*) from public.platform_audit_logs
   where action = 'platform_owner.granted') as owner_grant_audit_count;
```

Expected after successful staging bootstrap: founder_count=1, active_platform_owner_count=1, organization_count=1, active_membership_count=1, owner_grant_audit_count=1. Also verify exactly 41 role_permissions rows for the Owner role, six core modules enabled, and one matching module_audit_logs event.

## 6. Rollback policy

- Before the first successful bootstrap: stop the staging function, revoke EXECUTE on the bootstrap RPC, and remove the unconsumed staging bootstrap function/configuration as part of a reviewed rollback.
- If a staging attempt fails: transaction atomicity must leave no partial Founder/Owner/organization records.
- After a successful bootstrap: do **not** delete the Founder designation or erase audit history. Revoke/transfer access only through audited, guarded RPCs. A mistaken designation requires a separately reviewed exceptional correction that preserves the original audit trail.
- Production rollback must be separately reviewed against live dependencies; never use a generic `DROP TABLE` rollback after real data exists.

## 7. Current Production boundary

Latest read-only checks found no active Platform Owner, no organization, no organization membership, no access-context RPC, and no platform Owner RPCs. No Production migration, role grant, RLS change, or deployment has been made. Browser/Android authorization test has not been completed.
