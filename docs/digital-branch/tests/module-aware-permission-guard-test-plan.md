# Module-aware permission guard — isolated regression tests

**Status:** Test specification only. No database change or test execution has occurred.

## Expected behavior

| ID | Setup | Expected |
|---|---|---|
| MODPERM-01 | Active member + active role + granted permission + platform module active + org module active | Allow |
| MODPERM-02 | Same grant, but org module status is `disabled` | Deny |
| MODPERM-03 | Same grant, but org module row is missing | Deny |
| MODPERM-04 | Same grant, but platform registry module is inactive | Deny |
| MODPERM-05 | Permission has NULL `module_key` | Deny (fail closed) |
| MODPERM-06 | Permission maps to a non-existent module key | Deny |
| MODPERM-07 | Org module is active but role-permission row is absent | Deny |
| MODPERM-08 | Role is inactive | Deny |
| MODPERM-09 | Member is suspended/removed | Deny |
| MODPERM-10 | Organization is suspended/closed | Deny |
| MODPERM-11 | Module is disabled then re-enabled; permission grant remains | Deny while disabled, allow after approved re-enable |
| MODPERM-12 | One user has access to Org A but not Org B | No cross-organization permission leakage |

## Required impact review

- Enumerate every RLS policy and RPC that calls `private.has_org_permission`.
- Confirm all 41 current permission keys have non-NULL `module_key` values.
- Confirm core modules are seeded active before any member-facing permission check.
- Confirm optional modules remain denied until organization module activation is approved.
- Confirm a module activation flow does not itself create role-permission grants.
- Verify function owner, SECURITY DEFINER, empty search_path, schema USAGE and EXECUTE ACL remain unchanged.
- Run Supabase Security Advisors after applying only in an isolated test project.

## Important limitation

This candidate deliberately treats NULL/unmapped module permissions as denied. If the product requires platform-scoped permissions without a module, those must use a separate, explicit authorization path rather than silently bypassing the module gate.
