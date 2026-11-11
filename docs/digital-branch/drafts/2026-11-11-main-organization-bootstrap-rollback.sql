-- DRAFT ROLLBACK — function definitions only; does NOT delete organization data.
-- Run only if the companion migration was applied and after explicit approval.
begin;
drop function if exists public.bootstrap_primary_organization_v1();
drop function if exists private.bootstrap_primary_organization_v1();
commit;

-- Deliberately do not delete organizations, memberships, roles, permissions,
-- module rows, or append-only audit records. A data rollback requires a separately
-- reviewed recovery plan and an explicit approval.
