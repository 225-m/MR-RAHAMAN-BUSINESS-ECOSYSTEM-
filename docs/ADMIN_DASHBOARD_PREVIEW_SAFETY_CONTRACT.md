# Admin Dashboard Preview — Safety Contract

**Branch:** `feature/founder-owner-bootstrap-v1`

## Purpose
Provide a standalone, mobile-responsive, read-only visual preview of the intended MR RAHAMAN Business Ecosystem Admin workspace while Founder/Main Admin bootstrap and access verification remain incomplete.

## Route
`/admin-preview/`

## Explicit boundaries
- This page is static and does not initialize Supabase.
- It reads no Production or customer data.
- It performs no writes, role grants/revocations, approvals, module changes, or audit mutations.
- It does not authenticate a user and must never be described as actual Admin access.
- Real Admin Dashboard remains gated by `current_access_context_v1` and explicit active role/permission checks.
- Email verification alone is not authorization.
- Founder designation and active Platform Owner role remain distinct.

## Release conditions
1. Isolated Local/Staging migration execution.
2. Positive and negative SQL/RPC tests, including replay/concurrency and unauthorized caller cases.
3. Browser and Android Auth/Access verification with dedicated test identities.
4. Review of all 41 permission keys and 16 module mappings.
5. Security Advisor and rollback review.
6. Separate explicit Production release decision. No Production writes are authorized by this preview.
