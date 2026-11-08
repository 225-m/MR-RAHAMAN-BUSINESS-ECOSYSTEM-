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
