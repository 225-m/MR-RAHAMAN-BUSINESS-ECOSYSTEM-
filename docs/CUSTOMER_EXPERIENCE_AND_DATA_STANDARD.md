# Customer Experience & Personal Data Standard
## MR RAHAMAN Business Ecosystem — Customer Platform Blueprint
**Status:** Product/architecture blueprint; not a production change  
**Branch:** `feature/customer-access-v1`  
**Scope:** Customer self-service only. Platform Owner, organization members, employees, and branch permissions remain separate.

## 1. Product objective
Build a customer-facing service platform rather than a bare login screen. The customer should be able to understand the business relationship, manage their own account, complete a purchase or service request, track fulfilment, receive a receipt, seek help, raise a complaint, request a refund where applicable, and control personal data.

The platform must remain modular: features can be enabled by business line, country, legal basis, and operational readiness. Do not display a feature as available until its workflow, support process, database controls, and provider integration are actually working.

## 2. Customer journeys and capabilities

### A. Account and identity
- Sign up/sign in, verified email; phone OTP only after an SMS provider is configured and tested.
- Password reset, session/device list, sign out all sessions, account lock/risk alerts.
- Optional passkey / MFA roadmap; step-up authentication for sensitive actions.
- Customer profile: display name, preferred language, contact details, communication preferences.
- Account status, verification status, privacy notice version, consent receipts.
- No customer may self-assign employee, branch, organization, Admin, or Owner roles.

### B. Customer profile and address book
- Multiple delivery/service addresses, labels, recipient name and contact number.
- Default address, delivery instructions, area/postcode, optional map pin only when needed.
- Edit history for critical contact/address changes; confirm sensitive changes.
- Accessibility settings, Bangla/English preference, timezone/currency display.

### C. Product/service discovery
- Search, categories, filters, details, availability, transparent price and tax/fees.
- Product/service comparison where useful; stock/availability freshness.
- Saved items/favourites, recently viewed, recommendations only with appropriate privacy controls.
- Clear unavailable/out-of-stock and service-area messaging.

### D. Cart, order and fulfilment
- Cart, quantity changes, delivery/pickup options, order confirmation before payment.
- Order history, status timeline, estimated delivery window, shipment/fulfilment tracking.
- Cancel/edit within policy window; partial fulfilment and substitutions only with customer approval.
- Downloadable invoice/receipt, order reference, itemized price/tax/delivery/discount.
- Reorder and saved carts as optional later features.

### E. Payments and refunds
- Payment methods only when a verified provider integration is selected and enabled.
- Support local payment rails (e.g. provider-supported mobile financial services, bank/card) based on contracts and availability; do not hardcode a provider assumption.
- COD where business operations support it; payment state must be explicit (pending, authorized, paid, failed, refunded, partially refunded).
- Idempotent payment callbacks, reconciliation, signed webhook validation, duplicate-event protection.
- Store provider transaction references and masked method metadata only. Never store card PAN/CVV, PIN, wallet password, OTP, or secret credentials.
- Refund/chargeback status, reason, amount, timestamps and customer-visible progress.
- Hosted/tokenized checkout with a PCI-compliant provider; determine the applicable PCI DSS scope with the acquirer/provider before launch.

### F. Customer support and trust
- Help centre/FAQs, contact options, support ticket with category, priority, status and response history.
- Complaint/dispute, evidence attachment with file-type/size scanning controls, escalation and resolution.
- Return/replacement/refund request with policy and deadline shown before submission.
- Service notices, order updates and opt-in marketing separated from essential transactional messages.
- Customer feedback/ratings only with abuse and moderation controls.

### G. Loyalty and engagement (later, optional)
- Points/rewards, coupons, referral, membership tiers and wallet/credit only after accounting, fraud, expiry and legal rules are designed.
- No misleading scarcity, hidden fees, preselected marketing consent or dark patterns.
- Notification preferences by channel and category; transactional notices remain distinguishable from promotions.

### H. Privacy and account control
- Customer can view/download their profile and available personal data, update inaccurate details, withdraw optional consent, request correction/deletion, and close account.
- Explain lawful retention exceptions (e.g. financial, tax, dispute, fraud-prevention records) and retain only what is necessary.
- Data-processing purposes, recipients/processors, cross-border transfers, retention periods and contact channel must be documented.
- Privacy requests need identity verification proportionate to risk, case tracking, deadline monitoring and audit evidence.
- Do not promise immediate deletion where law or an active dispute requires retention; restrict retained records and document the reason.

## 3. Customer documents and verification — risk-based, not blanket KYC

| Level | When appropriate | Customer information/documents |
|---|---|---|
| Basic account | Ordinary browsing and low-risk customer account | Verified email OR verified phone (depending on login design), display name; no government ID required |
| Delivery/service | An order requires fulfilment | Recipient name, phone, delivery/service address and instructions; collect only what fulfilment needs |
| Refund/payment investigation | A specific transaction needs review | Order/payment reference and limited evidence; use provider references, never request PIN/OTP/CVV |
| Regulated/high-risk transaction | Only where law, provider/acquirer, product category or documented fraud risk requires it | The exact identity/business documents required by that rule, purpose, legal basis, verification result, expiry and access controls |
| Business customer | A business account/contract/credit facility is requested | Legal business name, registration/tax documents and authorized representative evidence only when contract/compliance requires it |

**Prohibited default collection:** NID/passport scans, selfie/biometrics, bank statements, card images, family details, contact lists, and precise location history must not be required for an ordinary customer account. If a future regulated workflow needs any of these, it requires a separate legal/privacy/security review, explicit purpose, restricted storage, retention schedule and user-facing explanation. Prefer verification by a qualified provider and store a minimal verification result/reference instead of raw documents.

## 4. Data model — proposed domains, not a migration
Keep the current `customer_profiles` table minimal. Introduce future tables only when the corresponding feature is approved and fully designed:
- `customer_contacts`: verified email/phone and verification timestamps.
- `customer_addresses`: address book, ownership, soft-delete and default selection.
- `customer_consents`: purpose, notice version, choice, timestamp, source, withdrawal.
- `customer_privacy_requests`: request type, status, deadlines, resolution and evidence.
- `customer_documents`: only for an approved regulated workflow; private storage bucket, metadata, checksum, expiry, access audit, retention/deletion state. Never public URLs.
- `customer_orders`, `customer_order_items`, `customer_order_events`: immutable commercial history and state transitions.
- `customer_payments`, `customer_refunds`: provider references, amounts, currency, idempotency keys, status and reconciliation.
- `customer_support_tickets`, `customer_ticket_messages`, `customer_attachments`: ownership and staff access separation.
- `customer_notifications`, `customer_notification_preferences`: delivery outcome and consent category.
- `customer_audit_events`: security-relevant account and privacy actions, without copying secrets or unnecessary sensitive payloads.

Use UUID foreign keys, UTC timestamps, explicit BDT currency initially (multi-currency-ready), status constraints, idempotency for financial operations, unique provider event IDs, and indexes for customer ownership/status/date. Avoid storing derived authorization in user-editable metadata.

## 5. Security and privacy controls
- RLS on every exposed customer table; policies bind rows to `auth.uid()` and verify both `USING` and `WITH CHECK` for updates.
- Deny customer access to another customer's rows, staff notes, internal fraud signals, provider secrets, and organization records.
- Keep Owner/Admin/employee authorization database-driven and independent from customer profile or user metadata.
- Private storage buckets; signed short-lived URLs; upload allowlist, size limits, malware scanning/quarantine and ownership checks.
- Step-up auth for changing login credentials, changing payout/refund destinations, closing account, or viewing especially sensitive records.
- Rate limits, bot/abuse controls, secure headers, dependency pinning, secret scanning, backup/restore drills, incident response and breach notification playbook.
- Audit grant/revoke, account recovery, contact verification, document access, privacy request, payment/refund and privileged staff access.
- Do not put secrets, OTPs, access tokens, full payment details or document contents in logs.
- Fail closed if access-context RPC fails; do not show the business dashboard or customer data on an authorization error.

## 6. Accessibility, localization and usability
- Target WCAG 2.2 AA as the product acceptance target: keyboard operation, visible focus, labels, contrast, screen-reader names, scalable text, error identification and accessible authentication.
- Bangla-first and English option; correct Bangla Unicode rendering, readable numerals/date formats, clear currency formatting, responsive Android-first layouts.
- Low-bandwidth experience, small payloads, retry-safe forms, clear offline/error states and no duplicate order/payment on retry.
- Plain-language policies, itemized pricing, delivery/refund timelines and customer support contact visible at the relevant decision point.

## 7. Standards and legal mapping
This is an engineering target, not a claim of certification or legal compliance:
- Bangladesh Personal Data Protection Act, 2026: obtain a Bangladesh legal review of applicability, lawful processing, notice/consent, rights, retention, processors and cross-border transfer before production handling of customer personal data.
- GDPR principles as a privacy-by-design benchmark where applicable: purpose limitation, data minimisation, transparency, accuracy, storage limitation and security.
- OWASP ASVS 5.0.0 stable: use versioned security requirements as a test checklist for authentication, access control, input validation, file handling, logging and API security.
- WCAG 2.2 AA: accessibility acceptance target.
- PCI DSS v4.0.1: confirm scope with payment acquirer/provider; outsource card capture to hosted/tokenized payment pages and never store sensitive authentication data.
- ISO/IEC 27001: use the information-security management principles as a governance roadmap; do not claim certification without a formal audit.

Official references:
- Bangladesh Personal Data Protection Act, 2026: https://bdlaws.minlaw.gov.bd/act-details-1692.html?lang=en
- ICT Division law listing: https://ictd.gov.bd/pages/laws
- European Commission GDPR principles: https://commission.europa.eu/law/law-topic/data-protection/information-business-and-organisations/principles-gdpr_en
- W3C WCAG overview: https://www.w3.org/WAI/standards-guidelines/wcag/
- OWASP ASVS 5.0.0: https://asvs.owasp.org/
- PCI SSC PCI DSS: https://www.pcisecuritystandards.org/standards/pci-dss/

## 8. Delivery roadmap and acceptance gates

### Phase 0 — blueprint and legal/product decisions
- Confirm which products/services are sold through this ecosystem and whether customers transact, book, pay, or only view information.
- Map actual customer data fields and purposes; approve privacy notice, terms, returns/refunds and retention.
- Keep this document as the requirements baseline; no production schema changes in this phase.

### Phase 1 — safe customer account
- Minimal profile, verified login, own-profile update, sign out/session controls, customer-only dashboard.
- Tests: verified/unverified user, customer A/B isolation, anonymous denial, owner/member unaffected, RPC outage fail-closed, Android small-screen and accessibility smoke test.

### Phase 2 — support and privacy centre
- Support tickets, help content, notification preferences, privacy request workflow, export/correction/deletion handling.
- Tests: ownership, staff access, attachment security, consent withdrawal, audit trail and retention.

### Phase 3 — commerce and fulfilment (only if the business model requires it)
- Catalog, cart, order, address book, status timeline, invoice, cancellation/returns.
- Tests: price integrity, stock races, idempotency, partial fulfilment, customer authorization and reconciliation.

### Phase 4 — payment provider and advanced services
- Provider selection, sandbox certification, signed webhooks, refunds, reconciliation, fraud/risk and loyalty only after accounting controls.
- Tests: duplicate callback, timeout, failed payment, refund, chargeback, provider outage and no sensitive card data stored.

### Release gates
1. Draft SQL rollback tested in disposable PostgreSQL; rollback must not delete customer data after launch.
2. Verify existing Owner and organization-member paths remain unchanged and Owner cannot be locked out.
3. RLS, grants, function privileges, Storage policies, security advisors and automated integration tests pass.
4. Edge Function and Pages deployment paths are explicitly reviewed; no unrelated workflow broadening.
5. Production migration and deployment are separate approval gates; take a backup/restore point and verify rollback path before any production change.
6. Android real-device customer login and customer A/B isolation test must pass before calling the feature live.

## 9. Explicit non-goals for the first release
- No automatic NID/passport collection.
- No customer ability to create or grant roles.
- No direct card data storage or home-grown payment processing.
- No customer access to Owner/Admin/branch dashboards.
- No unsupported claims of ISO, PCI, GDPR, WCAG or legal certification.
- No paid infrastructure or paid add-ons without a separate explicit decision.
