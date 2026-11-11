# Module-aware permission guard — isolated regression tests

**Policy decision (2026-11-11):** Main Owner retains all 41 current organization-scoped role-permission grants. Runtime access is still gated by module state. A permission is effective only if its mapped platform module is active AND the corresponding organization module row is active. Disabled, missing, or platform-inactive module means deny, including for Owner.

**Status:** Test specification only. No database change or test execution has occurred.

## Expected behavior

| ID | Setup | Expected |
|---|---|---|
| MODPERM-01 | Active member + active role + granted permission + platform module active + org module active | Allow |
| MODPERM-02 | Owner has all 41 grants, but target org module status is `disabled` | Deny |
| MODPERM-03 | Same Owner grant, but target org module row is missing | Deny |
| MODPERM-04 | Same Owner grant, but platform registry module is inactive | Deny |
| MODPERM-05 | Permission has NULL `module_key` | Deny (fail closed) |
| MODPERM-06 | Permission maps to a non-existent module key | Deny |
| MODPERM-07 | Org module is active but role-permission row is absent | Deny |
| MODPERM-08 | Role is inactive | Deny |
| MODPERM-09 | Member is suspended/removed | Deny |
| MODPERM-10 | Organization is suspended/closed | Deny |
| MODPERM-11 | Module is disabled then re-enabled; Owner grant remains | Deny while disabled; allow only after approved re-enable |
| MODPERM-12 | One user has access to Org A but not Org B | No cross-organization permission leakage |
| MODPERM-13 | Every one of the 41 keys is mapped to exactly one known module | Pass catalog integrity; any missing/unknown mapping blocks release |
| MODPERM-14 | Optional module activated without role-permission grant for another member | No permission gain for that member |
| MODPERM-15 | Owner's permission row exists for disabled module | Still deny at runtime |
| MODPERM-16 | Module is platform-disabled after org activation | Deny immediately on next authorization check |

## Required impact review

- Enumerate every RLS policy and RPC that calls `private.has_org_permission`.
- Confirm all 41 current permission keys have non-NULL `module_key` values and each key maps to a known registry module.
- Confirm core modules are seeded active before any member-facing permission check.
- Confirm optional modules remain denied until organization module activation is approved.
- Confirm module activation does not itself create role-permission grants for non-owner members.
- Confirm no Owner-specific bypass exists in RLS, RPC, helper, or frontend checks.
- Verify function owner remains `postgres`, SECURITY DEFINER remains true, `search_path` remains empty, and EXECUTE ACL remains restricted to `authenticated` (plus owner).
- Regression-test all 18 routines and 11 RLS policies identified in the live blast-radius scan, including branch and approval flows.
- Run Supabase Security Advisors after applying only in an isolated test project.

## Important limitation

This candidate deliberately treats NULL/unmapped module permissions as denied. Platform-scoped permissions without a module must use a separate, explicit authorization path rather than silently bypassing the module gate.
