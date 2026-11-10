# Customer Identity Verification & Future KYC Architecture
## MR RAHAMAN Business Ecosystem

**Status:** Architecture proposal / future-ready design only  
**Branch:** `feature/customer-access-v1`  
**Production status:** Not deployed; no Production schema, provider, or biometric integration is enabled.

## 1. Product decision

A normal customer must be able to create an account after verifying **either**:
- an email address using a verification link/code; or
- a mobile phone number using an SMS OTP.

The customer chooses the available channel. The account is not considered contact-verified until the selected channel succeeds. If both channels are later added, each has its own independent verification status. Email verification must not silently mark the phone verified, and phone OTP must not silently mark the email verified.

Basic account registration must not require NID, passport, selfie, face scan, fingerprint, or other biometric data. KYC is a separate, purpose-limited future workflow and is requested only when a specific service, legal requirement, payment provider, or documented risk decision makes it necessary.

## 2. Verification levels and states

| Level | Meaning | Access |
|---|---|---|
| `contact_unverified` | Signup started; selected email/phone not verified | Verification and recovery screens only |
| `contact_verified` | At least one chosen contact method verified | Ordinary Customer Dashboard, subject to account status |
| `kyc_not_required` | No KYC requirement for current service | Ordinary customer services |
| `kyc_required` | A documented workflow requires KYC | Only the affected restricted transaction/service is paused |
| `kyc_pending` | Customer submitted consent and required evidence | Pending review; do not claim verified |
| `kyc_needs_review` | Automated checks are inconclusive or risk is elevated | Human review / further evidence |
| `kyc_verified` | Approved verification completed for a stated purpose and validity period | Only the approved purpose/scope |
| `kyc_rejected` | Verification failed with a customer-safe reason | Appeal/correction route where available |
| `kyc_expired` / `kyc_revoked` | Previously valid result expired or was revoked | Re-check only where necessary |

KYC status is not a platform role. Neither `kyc_verified` nor contact verification may grant Owner, Admin, employee, branch, organization membership, or business permissions.

## 3. Contact verification design

- Support email verification and phone OTP as separate methods.
- Store normalized email/phone, verification timestamp, provider/message reference, and status; do not store OTP values.
- OTPs must be short-lived, single-use, rate-limited, attempt-limited, and protected against enumeration and replay.
- Resending a code invalidates the previous code where supported.
- Changing an email or phone requires verification of the new value; high-risk changes may require step-up authentication.
- Account recovery must not bypass contact verification or authorization.
- SMS provider integration is not assumed. Select only after checking Bangladesh delivery coverage, pricing, sender-ID requirements, abuse controls, and provider terms. Keep the current free-tier preference; do not enable paid messaging without a separate explicit decision.
- Do not expose whether an arbitrary email/phone already has an account in public signup responses.

## 4. Future KYC methods

### Supported roadmap
- Bangladesh NID document verification.
- Passport document verification.
- Selfie/liveness or face-match verification only through a qualified provider and only where justified.
- Other biometric methods only after a separate legal, privacy, security, accessibility, and provider assessment.

### AI-assisted checks (not autonomous identity approval)
AI may assist with:
- document type and image quality checks;
- OCR extraction into a temporary review result;
- consistency checks between submitted fields and document text;
- tampering indicators and duplicate-submission signals;
- liveness/face-match provider result interpretation, if legally permitted and contractually supported;
- prioritizing cases for human review.

AI must not be the sole final decision-maker for identity approval or rejection. Low confidence, mismatch, suspected fraud, accessibility exception, or adverse decision must support human review and a correction/appeal path. Explain to the customer what is being checked and why. Do not infer sensitive traits or use face recognition for unrelated profiling.

## 5. Proposed future data domains (not a migration)

Create only when the relevant workflow is approved and fully designed:
- `customer_contacts`: user_id, channel, normalized_value, is_primary, verified_at, status; uniqueness and ownership rules.
- `customer_verification_challenges`: challenge reference, channel, expiry, attempt count, consumed_at, provider reference; never persist plaintext OTP.
- `customer_kyc_cases`: user_id, purpose, legal_basis, provider, status, opened_at, decided_at, valid_until, reviewer reference.
- `customer_kyc_documents`: case_id, document_type, private object reference, checksum, expiry, retention/deletion status; no public URLs.
- `customer_kyc_checks`: check type, provider reference, result code, confidence band, performed_at, model/provider version; avoid storing raw biometric templates.
- `customer_kyc_reviews`: reviewer, decision, reason code, timestamp, appeal/review state.
- `customer_consent_records`: purpose, notice version, consent choice, timestamp, withdrawal timestamp and source.
- `customer_verification_audit_logs`: actor, action, case reference, timestamp and minimal evidence metadata.

Use UUID ownership references, explicit status constraints, least-privilege grants, RLS on exposed tables, private storage, short-lived access, retention schedules, and audited staff access. Keep sensitive KYC data out of Auth user metadata, general customer profile rows, analytics events, URLs, and application logs.

## 6. Privacy, security and governance gates

Before enabling any KYC method:
1. Document the exact business purpose and whether KYC is legally/provider-required; obtain Bangladesh legal advice on applicable law and cross-border processing.
2. Complete a privacy impact assessment and data-flow map, including subprocessors, hosting region, retention, deletion, breach handling, and customer rights.
3. Obtain specific, informed consent where required; do not bundle KYC consent with marketing consent or ordinary account terms.
4. Prefer a qualified verification provider and store a minimal signed result/reference rather than raw document/biometric data where feasible.
5. If raw documents must be retained, use a dedicated private bucket, encryption, strict staff-only access, malware scanning, access audit, and automatic retention/deletion controls.
6. Never store biometric templates unless a documented lawful and technically necessary basis exists; do not build a home-grown biometric matching system.
7. Define human review, customer notification, correction, appeal, false-positive handling, and service fallback.
8. Test cross-customer isolation, privilege boundaries, data export/deletion, provider outage, replay, rate limiting, and incident response.

This document is an engineering proposal, not legal advice or a claim of compliance/certification.

## 7. Authorization boundary

- Contact-verified Customer: self-service Customer features only.
- KYC-verified Customer: only the specific service/purpose for which verification is valid.
- KYC must never be used as a shortcut to platform roles or organization membership.
- Authorization continues to come from trusted database roles and permissions, not user-editable metadata, AI output, client-side flags, or KYC status.
- Existing Owner and organization-member access must remain unchanged.
- Any missing/failed access-context RPC must fail closed.

## 8. Rollout sequence

1. **Now — design only:** keep the current Customer Access v1 safe; document email-or-phone requirement and future KYC interfaces. No paid provider and no Production change.
2. **Contact verification release:** test verified email flow and separately integrate phone OTP only after provider selection, cost review, and explicit approval.
3. **KYC discovery:** identify the exact transaction/service that requires KYC, legal basis, provider options, costs, and data residency.
4. **KYC sandbox:** build provider adapter and disposable test cases; no real customer identity documents.
5. **Limited pilot:** only after security/legal review, explicit approval, customer notice, support workflow, retention and incident process.
6. **Production launch:** separate approval for migration, provider contract/charges, deployment, and real-data activation.

## 9. Acceptance criteria

- A customer can register using either verified email or verified phone, once each channel's implementation is actually enabled.
- Unverified contact cannot enter protected Customer features.
- Verifying one contact never verifies another.
- Basic signup never requests government ID or biometrics.
- KYC is purpose-specific, optional unless a documented requirement applies, and separate from account registration.
- AI is assistive; uncertain/adverse outcomes can be reviewed by a human.
- No KYC state can grant Owner/Admin/employee/business access.
- Customer A cannot read Customer B's contact, document, case, or verification result.
- OTPs, document contents, biometric data, tokens and secrets never appear in logs.
- Provider, legal, cost, privacy, security and Android real-device tests pass before release.

## 10. Explicit non-goals

- No immediate NID/passport/biometric collection.
- No AI-only final KYC decisions.
- No SMS provider activation or paid resource creation as part of this draft.
- No production database migration, Edge Function deployment, Pages deployment, PR merge, or live KYC enablement.


## 11. Admin-controlled feature lifecycle — default OFF until app completion

### Product decision
Prepare the architecture and code paths for contact verification enhancements and future KYC, but keep these services **disabled by default** while the complete main application is still being finished. The Admin must be able to manage availability later from the main application's Admin profile/settings area, without a code change for ordinary enable/disable operations.

### Admin settings and feature controls
Provide a dedicated **Customer Verification & KYC** section under the authorized Main App Admin settings/profile settings. It should expose separate controls, not one ambiguous switch:
- Email verification requirement / email verification channel.
- Phone OTP verification channel.
- NID verification.
- Passport verification.
- Biometric/liveness verification.
- AI-assisted document review.
- Overall Customer Verification/KYC master availability switch.

Initial configuration:
- Master availability: OFF.
- Phone OTP: OFF until a provider is selected, configured, cost-approved, and tested.
- NID / Passport / Biometric: OFF.
- AI-assisted KYC: OFF.
- No KYC provider credentials or paid resources are provisioned by this architecture draft.

Email confirmation behavior required by the existing Auth security design must not be weakened merely because the optional KYC feature family is disabled. The setting controls the customer verification product workflow; it must not silently turn off baseline authentication protections.

### Authorization and enforcement
- Only a trusted, active Platform Owner or explicitly authorized Admin with a dedicated permission such as `customer_verification.settings.manage` may change these settings.
- A normal Customer, employee without the dedicated permission, or client-side browser state must never be able to enable a feature.
- Store settings in a database-backed, server-authoritative configuration (for example, a dedicated feature-settings table or existing feature-flag service after its schema is reviewed). Do not trust localStorage, user metadata, URL parameters, or frontend-only switches.
- Every change records actor, previous value, new value, timestamp, reason/change note, and affected feature in an append-only audit trail.
- Enforce feature state in the backend/API/Edge Function and relevant database workflows as well as the UI. Hiding a button is not access control.
- Fail closed: if the setting cannot be read, treat the feature as OFF.
- Apply independent feature flags and dependency checks. Turning on AI review must not automatically turn on document collection, biometrics, or external provider billing.
- A feature may be enabled only when its release checklist is complete: provider configured where applicable, legal/privacy/security review approved, secrets stored securely, tests passed, support and incident process ready, and an explicit activation record exists.
- For any paid SMS/KYC provider or billable infrastructure, require a separate cost disclosure and explicit approval before provisioning or activation.

### Admin experience and safety
- Show clear states: Disabled, Prepared, Requires Setup, Testing, Ready to Enable, Enabled, Suspended.
- Show why a control is unavailable when prerequisites are missing.
- Require confirmation and a reason when enabling sensitive KYC/biometric workflows; require step-up authentication for high-impact changes.
- Support emergency suspension independently of normal feature enablement.
- Display activation history and who changed each setting.
- Do not expose provider secrets, raw identity documents, biometric data, or internal risk signals in Admin profile settings.
- Admin controls configuration; access to actual KYC documents/cases must be a separate least-privilege permission with its own audit trail.

### Rollout rule
Until the complete app is declared ready and the release gates pass, all future verification/KYC services remain OFF. The architecture, database design, tests, UI settings design, and provider adapters may be prepared in non-production branches and disposable environments. No Production activation, provider subscription, paid resource, real document collection, or biometric processing occurs without separate explicit approval.

### Acceptance criteria
1. All new verification/KYC feature flags default to OFF, including after a fresh install or migration.
2. Disabled features are unavailable through UI, API, RPC, Edge Functions, and direct database paths.
3. Only the trusted authorized Admin can change settings; Customer and unauthorized staff attempts are denied and audited where safe.
4. Admin can enable/disable each feature independently after readiness gates pass.
5. Missing configuration, failed provider health checks, or failed authorization leaves the feature OFF.
6. Changes are audited with actor, timestamp, old/new state, and reason.
7. Emergency suspension takes effect server-side without waiting for a frontend refresh.
8. Turning on one feature cannot implicitly activate another or incur an unapproved provider charge.
9. Baseline email confirmation/authentication security is not weakened by the KYC master switch.
10. The initial production configuration remains OFF until a separate release approval.

## 12. Future payment-card capability — tokenized provider model only

Payment-card support is part of the long-term Customer Platform architecture, but this does **not** authorize card collection or storage now.

### Design boundary
- Use a payment provider/acquirer that supports hosted checkout or provider-hosted/tokenized card fields. Prefer redirect/hosted checkout so the MR RAHAMAN application does not receive raw card data.
- The application may retain only the provider-issued customer/payment-method token or reference where permitted, masked display metadata (for example, brand and last four digits), provider transaction IDs, currency, amount, status, and timestamps.
- Never store or log full PAN/card number, CVV/CVC/CID, PIN, OTP, magnetic-stripe data, track data, card images, card passwords, or raw authentication credentials.
- Never build a home-grown card vault or collect card details in ordinary Customer profile forms.
- Tokenization does not automatically remove PCI DSS obligations. Confirm the exact PCI DSS scope and responsibilities with the acquirer/provider and qualified assessor before enabling card payments.
- Use signed webhooks, signature verification, idempotency keys, replay protection, reconciliation, refund/chargeback workflows, and provider outage handling.
- A provider token must be scoped to the correct customer and provider account; do not expose it to another customer or organization. Do not treat a token as a card number or as proof of payment.

### Future data model (design only)
If card-on-file is later justified and supported, keep a provider-owned reference record such as:
- `customer_payment_methods`: customer_id, organization_id where applicable, provider_key, provider_customer_ref, provider_payment_method_ref (encrypted or protected as required), brand, last4, expiry_month/year only if provider returns and policy permits, status, created_at, revoked_at.
- `customer_payment_transactions`: order_id, customer_id, organization_id, provider_key, provider_transaction_ref, amount, currency, status, idempotency reference, created_at, settled_at.
- `customer_payment_events`: provider event ID, event type, signature verification result, received_at, processed_at, processing status; no raw card data or unnecessary payload retention.

The exact schema, encryption/key management, retention, cross-organization boundaries, and provider contract must be reviewed before implementation. Organization-specific payment credentials and settlement accounts must never be shared implicitly between businesses.

### Admin lifecycle and activation gates
Add payment-card capability as an independent feature under the Admin's future **Customer Payments** settings; it must not be implicitly enabled by the KYC master switch. Initial state is OFF. Enablement requires:
1. Provider/acquirer selection and contract review.
2. Fee disclosure and explicit cost approval.
3. Sandbox integration and provider certification/testing.
4. PCI DSS scope confirmation and security review.
5. Signed webhook, idempotency, reconciliation, refund and chargeback tests.
6. Customer-facing terms, refund policy, privacy notice and support process.
7. Explicit activation record by an authorized Platform Owner/Admin with the dedicated payment-settings permission.

No payment provider, subscription, billable resource, real card collection, or Production payment activation is part of this architecture draft.

## 13. Global no-collection rule until separately approved

Until the relevant feature is explicitly enabled after its readiness gates:
- Do not ask Customers to submit NID, Passport, selfie, biometric sample, or card details.
- Do not create real KYC cases or retain identity documents/biometric material.
- Do not provision provider integrations or collect provider credentials in the client.
- Do not create payment-card records from manually entered card data.
- Keep future UI routes unavailable or clearly marked as not yet available; a design placeholder must not accept uploads or sensitive input.
- Test only with synthetic fixtures and provider sandbox test values, never real customer identity or card data.
