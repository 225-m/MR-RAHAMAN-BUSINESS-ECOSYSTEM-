# First Platform Owner Bootstrap V2 — Security Review

Status: source and SQL draft only. No Owner has been bootstrapped and no Edge Function has been deployed by this work.

## Server-side allowlist

The Owner bootstrap Edge Function no longer embeds a user UUID or wildcard CORS origin in source. It requires two server environment values:

- OWNER_BOOTSTRAP_ALLOWED_USER_ID — the one verified Auth user UUID allowed to invoke the first-owner flow.
- OWNER_BOOTSTRAP_ALLOWED_ORIGIN — the exact browser origin allowed to call the Edge Function.

If either is missing or the request origin/user does not match, the function fails closed. It validates the bearer token with Supabase Auth and requires email_confirmed_at before using the server-side service-role client. The service-role key is read only from the Edge Function environment.

## Database RPC controls

The V2 SQL draft runs only after the Platform Owner Management V1 draft has created the append-only platform audit table. It:

- Requires service_role at the database RPC boundary.
- Requires an explicit non-null expected user ID and a verified Auth account.
- Uses a transaction-scoped advisory lock.
- Refuses to run if any organization, organization membership, or non-revoked platform_owner record already exists.
- Requires exactly 41 permissions and six matching core modules.
- Creates the initial organization Owner with the current permission catalogue, enables only the six required core modules, and creates the platform_owner record in the same transaction. It writes both the organization module audit event and the platform_owner.granted audit event atomically.
- Writes an audit record in the same transaction.

The database function no longer hardcodes the user UUID; the Edge Function's server-side allowlist supplies it. No browser client receives the service-role key.

## Retired V1

owner_bootstrap_v1_DO_NOT_APPLY.sql is now a non-executable tombstone. The obsolete V1 function definition has been removed from the current source.

## Release boundary

Do not set the allowlist environment variables, deploy this Edge Function, execute the V2 SQL, or create the first Platform Owner until the account identity is independently verified and a separate explicit bootstrap authorization is given. The current Production inventory has zero platform Owner rows, zero organizations and zero organization members; no bootstrap has been run.

## Post-bootstrap Owner administration

After the first bootstrap, use only the audited RPCs in supabase/drafts/platform_owner_management_v1.sql:

- platform_owner_grant_v1 — active Platform Owner transfers the single Owner slot to a different email-verified Auth user; paired revoke/grant audit events are written atomically.
- platform_owner_revoke_v1 — direct removal of the final active Owner is blocked; use the audited handover RPC.
- platform_owner_audit_list_v1 — active Platform Owner only.

Direct API-role access to platform_admin_roles and platform_audit_logs is revoked. Audit records are append-only and read through the Owner-only audit RPC.
