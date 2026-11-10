# Customer Access v1 — Test Plan (DRAFT)

**Project:** MR RAHAMAN Business Ecosystem  
**Target branch:** feature/customer-access-v1  
**Status:** Design and source draft only. No Production SQL or deployment.

## Intended behavior
- Every confirmed Auth identity receives a self-owned customer profile.
- A Customer can sign in without a Platform Owner or organization membership.
- Customer UI is separate from the business dashboard.
- Customer has no role/permission grant, no organization membership, and no access to business tables.
- Existing Owner/organization access continues through the existing database authorization context.

## Database tests
1. Signup trigger creates one profile for a new Auth user.
2. Backfill creates profiles for existing Auth users without duplicates.
3. Anonymous access to profile table and access-context RPC is denied.
4. Authenticated Customer A reads only A's profile.
5. Customer A cannot read or modify Customer B's profile.
6. Customer can update only display_name; cannot insert, delete, change user_id, or edit timestamps.
7. A profile update refreshes updated_at.
8. Customer RPC returns is_customer=true, profile details, is_platform_owner=false and an empty organizations array when no membership exists.
9. An Owner or organization member still receives the existing Owner/member context; Customer status must not elevate permissions.
10. No authorization decision uses user_metadata.

## Frontend tests
1. Email-unverified user remains in verification flow.
2. Verified Customer with valid access context sees only Customer Dashboard.
3. Customer does not see Overview, Branch, Business Modules, Platform Services, Admin or Owner controls.
4. RPC missing, denied, malformed, or unavailable: fail closed; no business dashboard.
5. Owner with a valid Owner grant sees the existing business workspace, not the Customer-only view.
6. Organization member with dashboard.read sees the business workspace.
7. Customer A's profile is not displayed in another session.
8. Logout clears Customer and business views.

## Release gates
- Run SQL against a disposable local Supabase/Postgres environment.
- Run RLS negative tests and frontend JavaScript/HTML checks.
- Run Supabase Security Advisor after test deployment.
- Confirm Android Chrome login with a separate test account.
- Only then prepare a production migration/release. Do not enable broad grants or disable RLS.

## Rollback
Before customer data exists, rollback may remove the draft objects in the disposable environment. After signup/profile data exists, do not drop the table or delete customer rows; use a forward fix and preserve user data.
