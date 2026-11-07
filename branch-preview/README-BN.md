# MR RAHAMAN Business Ecosystem — Branch Module Preview

এই Preview কেবল Supabase project `pojhrvmuamdejlutxpng`-এর জন্য। MUHAIMIN Dairy-এর সঙ্গে কোনো code, data, auth বা configuration শেয়ার করে না।

## Scope
- Email + phone verification ছাড়া UI বন্ধ থাকে।
- Active `organization_members` membership ছাড়া Organization/Branch data দেখায় না।
- Organization-scoped RPC ব্যবহার করে branch list/create/update/status, profile, contacts, operating hours, settings ও audit list।
- Frontend-এ কোনো `service_role` বা secret key নেই।
- কোনো Organization, Owner, Branch বা Staff record নিজে থেকে bootstrap/seed করে না।
- Database schema/migrations পরিবর্তন করে না।

## Existing backend contracts
- `branch_list_v1`
- `branch_create`
- `branch_update`
- `branch_set_status`
- `branch_detail_v1`
- `branch_upsert_profile`
- `branch_add_contact`
- `branch_set_operating_hours`
- `branch_set_setting`
- `branch_audit_list_v1`

All writes must be authorized by the existing database functions and RLS. UI visibility is not an authorization boundary.

## Current verified environment (read-only inspection, 2026-11-08)
- Supabase project status: ACTIVE_HEALTHY; PostgreSQL 17.
- Existing migration history includes 14 migrations, including the Branch Module backend set.
- Branch-related tables and RPC functions already exist; branch data and organization membership counts were zero at inspection.
- Therefore real Owner/Staff end-to-end tests cannot pass until a trusted Owner bootstrap and active membership are provisioned through the approved security workflow.

## Known limitations before live testing
- No live Organization/Owner/Branch data is seeded.
- Branch create/edit/status/profile/contact/hour/settings RPCs are wired but have not been exercised by an authorized real account.
- GPS coordinates are captured manually; browser geolocation permission and map provider are not yet integrated.
- Staff assignment/revocation and full permission-management UI are a follow-up slice; backend functions exist but the UI does not expose them yet.
- Bangladesh administrative hierarchy selector, report dashboard, exports and automated notifications are not yet implemented.
- Do not deploy or apply database changes from this preview without review.

## Manual test checklist
1. Unauthenticated visitor remains at the secure-access gate.
2. Unverified email or phone remains blocked.
3. Verified user without active organization membership remains blocked.
4. Active member with `branch.read` can list only authorized branches.
5. User without write permissions receives a database authorization error.
6. Authorized Owner/Admin creates, edits and changes status of a test branch in a non-production test organization.
7. Verify profile/contact/hours/settings writes and corresponding audit records.
8. Verify branch data cannot be read across organizations or branches.
9. Test revocation and confirm access is denied after token/session refresh.
