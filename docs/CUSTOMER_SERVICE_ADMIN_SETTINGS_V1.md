# Customer Service Admin Settings v1 — Architecture & Security Contract

**Project:** MR RAHAMAN Business Ecosystem  
**Branch:** `feature/customer-access-v1`  
**Status:** Draft implementation and disposable-test specification only  
**Production:** Not applied, not deployed, all optional services remain OFF

## 1. Purpose

Prepare one server-authoritative Admin settings system for future Customer verification and payment capabilities. This avoids rebuilding settings, permission checks, feature lifecycle, and audit behavior when the wider multi-organization application is ready.

This is a platform-level control plane. It is deliberately separate from organization-scoped employee/branch permissions and from customer profile data.

## 2. Platform authorization boundary

The existing 41 permission catalogue entries are organization-scoped through `organization_members`, `app_roles`, and `role_permissions`. They must not be reused to authorize global Customer verification or payment settings.

The proposed platform permission catalogue is private and separate:
- `customer_verification.settings.manage`
- `customer_payment.settings.manage`

Authorization rules:
- An active, unexpired, non-revoked `platform_owner` grant is authorized.
- An active, unexpired, non-revoked `platform_admin` grant is authorized through explicit platform-role permission mappings.
- `security_admin`, `support_admin`, organization Owner, branch manager, employee, and Customer receive no settings permission by default.
- Platform role assignments and permission mappings are not writable by browser clients.
- A KYC case/document reviewer permission must be designed separately; permission to turn a feature on never implies access to customer identity evidence.
- Existing organization permission catalogue and its 41 entries remain unchanged.

## 3. Feature inventory and initial state

| Feature key | Purpose | Initial state |
|---|---|---|
| `customer_verification.master` | Master availability gate for verification features | OFF |
| `customer_verification.phone_otp` | Phone OTP channel | OFF |
| `customer_verification.nid` | NID verification | OFF |
| `customer_verification.passport` | Passport verification | OFF |
| `customer_verification.biometric` | Biometric/liveness workflow | OFF |
| `customer_verification.ai_review` | AI-assisted document review | OFF |
| `customer_payment.card_payments` | Provider-hosted/tokenized card payments | OFF |

Baseline Supabase Auth email confirmation is not a feature flag and cannot be disabled through this settings system. No optional KYC setting may weaken baseline authentication.

The payment-card setting is independent of the verification master switch. Enabling AI review does not enable document upload, biometric processing, or provider billing.

## 4. Readiness and activation

Each feature has a server-controlled `readiness_status`:
- `prepared`
- `requires_setup`
- `testing`
- `ready_to_enable`
- `suspended`

New features start with `is_enabled=false` and `readiness_status='prepared'`. Admin cannot self-certify a feature as ready. The readiness transition must be performed only through a separately reviewed release/governance operation after provider, legal, privacy, security, cost, support, and test gates pass.

The Admin toggle RPC refuses enablement unless readiness is `ready_to_enable`. Verification child features additionally require the verification master switch to be ON. Turning the master OFF immediately disables all verification child features in the same transaction and writes an audit row for every changed feature. Payment card remains independent.

If configuration cannot be read or authorization fails, the backend must treat the service as OFF. UI visibility is never the security boundary.

## 5. Storage, RPC and audit

Draft objects are placed in the non-exposed `private` schema:
- `platform_permissions`
- `platform_role_permissions`
- `customer_service_feature_settings`
- `customer_service_feature_audit`

The only client-facing operations are narrow public SECURITY INVOKER wrappers that call private SECURITY DEFINER functions with pinned empty search paths. The internal functions verify `auth.uid()`, active platform role, expiry/revocation and dedicated permission on every call.

No direct browser grants are provided on private settings, platform permission mappings, or audit tables. Audit records are append-only and record actor, feature key, old/new enabled state, reason, and timestamp. No secrets or customer documents belong in these rows.

## 6. Customer data and provider separation

This settings layer stores feature availability only. It does not create or collect:
- NID or Passport images/numbers;
- selfie, face template, fingerprint, or other biometric material;
- payment card PAN, CVV/CVC, PIN, OTP, or card image;
- SMS/KYC/payment provider credentials;
- real KYC cases or payment instruments.

Future card payments must use a qualified provider's hosted checkout/tokenization. Store provider references and masked metadata only, subject to provider terms and PCI DSS scope confirmation. Do not build a home-grown card vault.

## 7. Admin UI contract (future implementation)

The main app's protected Admin profile/settings area should show separate sections:
- Customer Verification & KYC
- Customer Payments

Each row shows feature name, OFF/ON, readiness state, why unavailable, last changed time, and activation history. Enabling sensitive KYC/biometric features requires a confirmation and reason; high-impact activation requires step-up authentication. Emergency master suspension must be available to an authorized actor.

Do not show secrets, raw documents, biometric data, internal risk scores, or provider credentials in the settings page.

## 8. Required tests

The disposable PostgreSQL integration test must prove:
1. All seven features are inserted OFF and prepared.
2. Anonymous, ordinary Customer, expired Admin, Support Admin, and unauthorized staff cannot read or change settings.
3. Only active authorized Platform Admin and Platform Owner can use the settings RPC.
4. Readiness gates block enablement before approval.
5. Verification child switches cannot be enabled while master is OFF.
6. Master OFF atomically disables all verification children and audits each change.
7. Payment card setting remains independent.
8. Direct browser access to private tables is denied.
9. Audit rows cannot be updated or deleted.
10. Existing customer profile/owner/organization access tests remain intact.

## 9. Change-control

This work is a branch-only draft. It must be tested in disposable PostgreSQL. Do not apply it to the live Supabase project, merge the pull request, deploy the app, create paid resources, configure a paid provider, or collect real customer data without separate explicit approval.
