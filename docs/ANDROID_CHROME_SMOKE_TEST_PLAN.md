# Android Chrome Smoke Test Plan — Branch Preview V1

Project: MR RAHAMAN Business Ecosystem  
Branch: `feature/customer-access-v1`  
Status: Prepared; physical Android device execution is outstanding.

## Safety boundary

- Run only against an isolated non-production preview with disposable test accounts.
- Do not enter real customer, employee, payment, NID, or identity data.
- Do not use Production credentials or attempt a Production module change.
- Do not treat a mobile viewport emulator as proof of physical Android compatibility.

## Device matrix

- Android 13 or newer, current stable Chrome.
- Portrait: 360×800 or 393×873 CSS-pixel class.
- Landscape: rotate once during the session and verify no clipped controls.
- Test once on Wi-Fi and once on mobile data where available.

## Test accounts

Prepare three separate verified-email accounts in the isolated organization:

1. Requester: `branch.read`, `module.read`, `module.request`, `approval.read`.
2. Approver: `branch.read`, `module.read`, `approval.read`, `approval.approve`.
3. Applier: `branch.read`, `module.read`, `approval.read`, `module.manage`.

Also prepare a viewer with only `branch.read`.

## Execution checklist

- [ ] Sign in with a verified email; confirm the Branch Preview access gate resolves from database context.
- [ ] Sign in without an organization membership; confirm Branch Module remains blocked.
- [ ] As requester, submit an enable/disable request with a reason.
- [ ] Confirm requester cannot approve or reject their own request, even if their role also has `approval.approve`.
- [ ] As a different approver, approve the request; confirm the requester session does not gain Apply controls.
- [ ] As a separate applier, apply the approved request; confirm module state refreshes.
- [ ] As branch.read-only viewer, confirm no Request, Approve/Reject, or Apply controls appear.
- [ ] Refresh the page after each step; verify the displayed status comes from the database, not stale local UI state.
- [ ] Verify no horizontal scrolling, clipped buttons, overlapping dialogs, or unreadable text in portrait and landscape.
- [ ] Use Android Back and reload; confirm the session/access gate remains correct.
- [ ] Briefly disable connectivity, attempt a refresh, restore connectivity, and confirm errors fail closed without duplicate requests.
- [ ] Confirm browser console/network responses do not expose service-role keys or other secrets.

## Acceptance criteria

All role-separated workflow steps succeed; self-approval and unauthorized actions remain unavailable; database state survives refresh; no layout overflow or console errors; network failures do not bypass authorization.

Record Android version, Chrome version, device model, viewport/orientation, test account role, result, and sanitized screenshots. Do not record passwords, access tokens, or personal data.

## Current limitation

CI currently validates a 390×844 Playwright mobile viewport. This is useful responsive-layout coverage, but it is not a physical Android Chrome test. The Branch Preview is not published as a Production-facing app, so physical-device execution must wait until a safe isolated preview URL is available.
