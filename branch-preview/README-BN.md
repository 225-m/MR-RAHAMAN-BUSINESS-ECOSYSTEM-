# MR RAHAMAN Business Ecosystem — Branch Module Preview

এই Preview কেবল Supabase project `pojhrvmuamdejlutxpng`-এর জন্য। MUHAIMIN Dairy-এর সঙ্গে কোনো code, data, auth বা configuration শেয়ার করে না।

## Scope
- Email verification এবং database-backed `current_access_context_v1()` থেকে `branch.read` permission যাচাই না হলে UI বন্ধ থাকে। Phone OTP v1-এ ব্যবহৃত হয় না।
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
2. Unverified email remains blocked; phone verification is not part of v1.
3. Verified user without active organization membership remains blocked.
4. Active member with `branch.read` can list only authorized branches.
5. User without write permissions receives a database authorization error.
6. Authorized Owner/Admin creates, edits and changes status of a test branch in a non-production test organization.
7. Verify profile/contact/hours/settings writes and corresponding audit records.
8. Verify branch data cannot be read across organizations or branches.
9. Test revocation and confirm access is denied after token/session refresh.


## সর্বশেষ উন্নয়ন — Bangladesh Location, Target & Finance

### বাস্তবে Development Branch-এ যোগ হয়েছে
- Offline cascading Bangladesh address selector: বিভাগ → জেলা → উপজেলা।
- Dataset: ৮ বিভাগ, ৬৪ জেলা, ৪৯৫ উপজেলা; Bangla + English নাম।
- ইউনিয়ন/ওয়ার্ড/পৌরসভা, এলাকা, পোস্ট কোড ও বিস্তারিত ঠিকানা ঐচ্ছিকভাবে হাতে লেখা যায়।
- Address বিদ্যমান `branches.address` JSONB-তেই সংরক্ষিত হয়; নতুন Production table প্রয়োজন হয়নি।
- পুরোনো string/JSON address edit করার সময় অজানা key-সহ তথ্য সংরক্ষণের চেষ্টা করা হয়; parent location বদলালে child selection reset হয়।
- Dataset source ও CC BY 4.0 attribution bundled JSON-এর ভিতরে আছে।

### Architecture / Draft / Test Plan
- [Location, Target & Finance Architecture](./ARCHITECTURE-LOCATION-TARGET-FINANCE.md)
- [Target & Finance SQL Draft — Production-এ Apply করা হয়নি](./migrations/branch-target-finance-draft.sql)
- [Location, Target & Finance Test Plan](./tests/LOCATION-TARGET-FINANCE-TEST-PLAN.md)
- [Bangladesh location dataset attribution](./data/bangladesh-admin-hierarchy.json)

### Schema review-এর ফল
- বর্তমান Schema-তে dedicated branch target বা finance transaction/ledger table নেই।
- `approval_requests` ও `approval_actions` আছে; তবে Branch Target/Finance-এর জন্য mutation RPC contract এখনো যাচাই হয়নি।
- `branch.target.read` এবং `branch.target.manage` permission এখনো registry-তে নেই; architecture-এ প্রস্তাব হিসেবে রাখা হয়েছে, role-এ grant করা হয়নি।
- Finance-এর জন্য existing `finance.read` ও `finance.manage` পাওয়া গেছে।
- Financial draft প্রথম পর্যায়ে operational cash/income/expense register প্রস্তাব করে; এটি double-entry general ledger নয়।

### সীমাবদ্ধতা ও release gate
- ইউনিয়ন/ওয়ার্ডের পূর্ণ যাচাইকৃত তালিকা bundled হয়নি; হাতে লিখতে হবে।
- Target/Finance schema, RPC, approval integration এখনো তৈরি হয়নি।
- SQL ফাইলটি Draft; এতে শেষে ROLLBACK আছে এবং Production-এ চালানো যাবে না।
- কোনো Production DB পরিবর্তন, Migration Apply, Merge বা Deployment হয়নি।
- বাস্তব Owner Account ও Active Organization Member দিয়ে Live Functional Test এখনো বাকি।
