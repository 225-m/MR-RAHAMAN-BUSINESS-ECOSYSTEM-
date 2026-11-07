# Branch Module — Verification Plan

## A. Bangladesh location selector
- [ ] Dataset JSON parses and has 8 divisions, 64 districts, 495 upazilas.
- [ ] Division selection populates only its districts.
- [ ] District selection populates only its upazilas.
- [ ] Changing division clears stale district and upazila.
- [ ] Changing district clears stale upazila.
- [ ] Edit existing structured address restores the hierarchy.
- [ ] Edit legacy string address preserves it as full_address.
- [ ] Edit legacy JSON address preserves unknown keys.
- [ ] Union/ward/area/postal fields remain optional.
- [ ] Offline load works from bundled relative JSON path.
- [ ] HTML escaping prevents location names from becoming markup.
- [ ] No Supabase schema write is required for address selector.

## B. Target module (future; requires migration and Owner test account)
- [ ] Member without branch.target.read cannot read targets.
- [ ] Member without branch.target.manage cannot create/change targets.
- [ ] Cross-organization branch_id + organization_id pair is rejected by FK.
- [ ] Negative target rejected; end date before start date rejected.
- [ ] Pending target cannot be edited silently.
- [ ] Requester cannot approve own target.
- [ ] Approval action and target status transition are atomic.
- [ ] Every grant/change/approval/rejection is audited.
- [ ] Duplicate/overlapping active target policy is enforced.

## C. Financial entries/report (future; requires migration and Owner test account)
- [ ] Member without finance.read cannot read branch financial entries/report.
- [ ] Member without finance.manage cannot create/post/void/reverse entries.
- [ ] Amount <= 0 rejected; invalid currency code rejected.
- [ ] Only posted entries appear in reports.
- [ ] Pending/draft/rejected/void entries excluded from totals.
- [ ] Posted entries cannot be edited or deleted.
- [ ] Reversal is a new entry with source reference and audit trail.
- [ ] Branch/org composite FK blocks cross-org references.
- [ ] Report totals reconcile with posted income/expense entries.
- [ ] Date range, branch filter and currency grouping verified.
- [ ] Requester cannot approve their own finance request.

## D. Release gates
- [ ] SQL migration and rollback reviewed.
- [ ] Supabase security/performance advisors reviewed after schema implementation.
- [ ] Role/permission mapping reviewed by trusted Owner.
- [ ] Real Owner + active organization member JWT E2E tests completed.
- [ ] No Production migration or deployment before explicit release approval.
