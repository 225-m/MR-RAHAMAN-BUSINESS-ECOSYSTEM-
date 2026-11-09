# Last Active Owner Guard V1

Status: draft SQL and disposable PostgreSQL tests added on the feature branch. Not applied to Production.

## Protected identities

- Platform Owner: active row in public.platform_admin_roles with role_key = platform_owner, revoked_at IS NULL, and expires_at NULL or in the future.
- Organization Owner: active organization_members row assigned to an active app_roles row with role_key = owner, within an active organization.

## Database protections in the draft

- Prevent revoking, expiring, demoting, or deleting the final active Platform Owner.
- Prevent disabling, renaming, or deleting the final active organization Owner role when it has active members.
- Prevent suspending, removing, or demoting the final active organization Owner membership.
- Serialize concurrent owner-loss attempts with transaction-scoped advisory locks.
- Use private SECURITY DEFINER trigger functions with an empty search_path and revoke direct API execution.
- Keep direct browser table writes unavailable; triggers are defense in depth, not a grant of authority.

## Permission floor

An active organization Owner role must have all of the following governance permissions:

- member.invite
- member.manage
- role.manage
- organization.update
- branch.manage
- approval.approve
- module.manage
- audit.read
- permission.read

The draft rejects assigning an active member to an incomplete Owner role, rejects disabling/renaming the last complete Owner role, and blocks removal or replacement of a required permission mapping from the last active complete Owner role. The trigger re-checks the permission floor under the same organization-scoped advisory lock used by Owner membership changes.

The 14 recovered migrations contain no organization Owner seed because Production currently has no organizations or members. The V2 first-owner bootstrap draft defines role_key = owner and the Owner guard uses that same canonical V1 key; future role seeds must preserve this contract. The expanded disposable PostgreSQL permission-floor suite passed in GitHub Actions Run #205 (static-auth-check). The draft remains unapplied to Production.

## Disposable tests

The new fixture and integration test cover:

- Last Platform Owner revoke, expiry, demotion and delete blocking.
- Normal revocation of one of multiple Platform Owners.
- Last organization Owner membership suspension, demotion and delete blocking.
- Last Owner role deactivation blocking.\n- Incomplete Owner role assignment denial.\n- Removal of a required permission from the final complete Owner role blocked.\n\nVerification: [GitHub Actions Run #205](https://github.com/225-m/MR-RAHAMAN-BUSINESS-ECOSYSTEM-/actions/runs/42547283643).
- Normal removal of a non-Owner member.

CI runs these tests in a separate disposable PostgreSQL database. Passing tests do not deploy the draft or modify Production.
