# MR RAHAMAN Business Ecosystem — Branch Module Preview

এই Preview কেবল Supabase project `pojhrvmuamdejlutxpng`-এর জন্য। MUHAIMIN Dairy-এর সঙ্গে কোনো code, data, auth বা configuration শেয়ার করে না।

## Scope
- Email + phone verification ছাড়া UI বন্ধ থাকে।
- Active `organization_members` membership ছাড়া Organization/Branch data দেখায় না।
- Organization-scoped RPC ব্যবহার করে branch list/create/update/status, profile, contacts, operating hours, settings, staff access assign/revoke ও audit list।
- RLS-invoker `branch_dashboard_v1` view থেকে KPI summary (total/active/inactive/suspended, profile coverage, daily capacity, active contacts)।
- Branch name/code/phone search, status filter এবং বর্তমান filtered result-এর CSV export।
- GPS browser permission নিয়ে latitude/longitude capture এবং Google Maps link তৈরি করে।
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
- GPS browser geolocation ও Google Maps link যুক্ত; map tile/provider embed এখনো নেই.
- Staff assignment/revocation UI এবং RLS-নিয়ন্ত্রিত Active Organization Member search/selection যুক্ত হয়েছে। Member search-এর জন্য `member.read` permission লাগতে পারে; Auth user directory-তে কোনো fallback নেই। হাজিরা, বেতন এবং পূর্ণ Permission Matrix এখনো বাকি.
- Bangladesh administrative hierarchy selector এখনো নেই; Branch address-এ বর্তমানে manual text/JSON দেওয়া যায়।
- Branch target ও finance-এর জন্য dedicated target/financial tables পাওয়া যায়নি; তাই ওই ফিচারগুলো implement করা হয়নি এবং নতুন schema তৈরি করা হয়নি।
- Approval request/action tables আছে, কিন্তু Branch target/finance approval flow-এর জন্য যাচাইকৃত public RPC contract পাওয়া যায়নি; তাই approval integration এখনো pending।
- Branch KPI dashboard এবং filtered Branch CSV export আছে; এগুলো financial report নয়।
- Do not deploy or apply database changes from this preview without review.

## Static checks completed (2026-11-08)\n- Inline JavaScript syntax: PASS.\n- Duplicate HTML IDs: none.\n- Required branch RPC names and UI hooks present.\n- No service-role/secret key is embedded.\n\n## Manual test checklist
1. Unauthenticated visitor remains at the secure-access gate.
2. Unverified email or phone remains blocked.
3. Verified user without active organization membership remains blocked.
4. Active member with `branch.read` can list only authorized branches.
5. User without write permissions receives a database authorization error.
6. Authorized Owner/Admin creates, edits and changes status of a test branch in a non-production test organization.
7. Verify profile/contact/hours/settings writes and corresponding audit records.
8. Verify branch data cannot be read across organizations or branches.
9. Test revocation and confirm access is denied after token/session refresh.
