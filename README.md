# MR RAHAMAN Business Ecosystem

A modular, security-first business platform foundation designed for multi-organization and multi-branch operations.

## Brand identity

The canonical brand mark is maintained at `assets/brand/mr-rahaman-business-ecosystem.svg`.
The authentication preview uses this shared asset rather than embedding a duplicate logo.

## Current repository structure

- `auth-preview/` — authentication and restricted customer-access preview.
- `branch-preview/` — branch architecture and UI preview.
- `docs/` — architecture, security, privacy, governance and reconciliation records.
- `supabase/drafts/` — reviewed migration drafts; not automatically deployable.
- `supabase/tests/` — isolated integration-test plans and fixtures.
- `supabase/functions/` — Edge Function source drafts.
- `assets/brand/` — canonical brand assets.

## Security and release boundaries

- Customer access is separate from Owner, Platform Admin, organization roles and employee access.
- Email verification is the baseline; phone OTP, NID, Passport, biometrics and AI-assisted KYC remain disabled until separately reviewed and explicitly enabled.
- Browser code must never contain Supabase service-role keys or provider secrets.
- SQL under `supabase/drafts/` is not a production migration.
- No Production database changes, role grants, Edge Function deployment, or public release are authorized by this repository README.
- All release candidates require static checks, isolated PostgreSQL tests, security review, backup/rollback readiness and explicit release approval.

## Development principle

Build and verify each capability in an isolated feature branch, preserve existing work, and merge only after review. Never mix this repository with the separate Muhaimin Dairy project.
