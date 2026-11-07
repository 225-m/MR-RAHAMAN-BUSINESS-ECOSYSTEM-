# First Owner Bootstrap — Draft

Target project: MR RAHAMAN Business Ecosystem (pojhrvmuamdejlutxpng).
Target branch: feature/branch-module-v1.

Files:
- supabase/migrations/202611080001_owner_bootstrap_v1.sql
- supabase/functions/owner-bootstrap/index.ts
- supabase/tests/OWNER-BOOTSTRAP-TEST-PLAN.md

Security:
- Edge Function validates a real Supabase JWT and the exact allowlisted Auth UUID.
- Service-role key is used only server-side; never embedded in Android/web client.
- Database RPC execute permission is restricted to service_role.
- One-time guard, advisory transaction lock, verified email check.
- Requires exactly 40 live permissions; otherwise aborts.
- Creates organization Owner, links all current permissions, enables five core
  modules and appends an audit event atomically.
- Does not grant platform_owner and does not create a sample branch.

Current status:
- Source drafts only on feature/branch-module-v1.
- Not deployed; no Production migration applied; no Owner data created.
- Real JWT/Owner test requires an isolated test project or an approved migration window.
