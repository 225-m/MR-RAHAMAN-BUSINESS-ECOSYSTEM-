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

## Important limitation before release

The current V1 draft protects Owner role assignments and activation state. It does not yet prevent an administrator from removing critical role_permissions mappings from an otherwise active Owner role. That is a separate release blocker: the Owner permission floor must be specified and tested before this guard can be called complete. The canonical organization Owner key is set to owner in this draft and must be confirmed against the final role catalogue before Production use.

## Disposable tests

The new fixture and integration test cover:

- Last Platform Owner revoke, expiry, demotion and delete blocking.
- Normal revocation of one of multiple Platform Owners.
- Last organization Owner membership suspension, demotion and delete blocking.
- Last Owner role deactivation blocking.
- Normal removal of a non-Owner member.

CI runs these tests in a separate disposable PostgreSQL database. Passing tests do not deploy the draft or modify Production.
