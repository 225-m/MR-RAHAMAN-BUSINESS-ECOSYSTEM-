# Main Owner permission decision — 2026-11-11

**Project:** MR RAHAMAN Business Ecosystem  
**Decision:** Approved by the founder in this conversation.

## Approved policy

1. The canonical Main Owner receives all 41 current organization-scoped permission grants in `role_permissions`.
2. Platform-level authority remains separate. This decision does not create, expand, or alter any row in `platform_admin_roles`.
3. A stored role-permission grant is not sufficient by itself to authorize runtime access.
4. The module-aware security gate is mandatory for every organization permission check, including Main Owner.
5. Effective access requires all of the following:
   - authenticated user and active organization membership;
   - active organization and active role;
   - explicit matching role-permission row;
   - permission mapped to a known, non-null module key;
   - platform registry module is active;
   - organization's corresponding module row exists and has status `active`.
6. Disabled, missing, inactive, NULL-mapped, or unknown module state must fail closed (deny), with no Owner bypass.
7. Module activation must follow the existing approved module-change workflow. Enabling a module must not silently grant its permissions to other roles or members.
8. Every grant/revoke remains subject to audit logging and permission revalidation.

## Required implementation gates

- Apply the module-aware guard only after reviewing all 18 database routines and 11 RLS policies that currently reference `private.has_org_permission`.
- Verify function owner, SECURITY DEFINER, empty `search_path`, schema privileges, and EXECUTE ACL remain correct.
- Test all 41 permission-to-module mappings and all 16 module registry entries.
- Run MODPERM-01 through MODPERM-16 and BOOT-01 through BOOT-20 in an isolated Supabase project with real test JWTs.
- Run Security Advisors and review branch, approval, audit, organization, and module workflows.
- Only then convert drafts into a numbered migration and seek separate explicit Production apply approval.

## Current safety state

This is a policy decision and repository documentation update only. It does not authorize an immediate Production database change. No SQL has been applied to the live Supabase project, no organization was created, and no role/permission/module/audit data was changed.
