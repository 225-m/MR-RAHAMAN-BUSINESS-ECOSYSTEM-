# Platform Branding & Overview — v1

## Scope
- Uses the approved MR RAHAMAN brand artwork as the visual reference.
- Adds a small web-optimized SVG logo at `assets/mr-rahaman-logo.svg`.
- Stores only public brand metadata in `public.platform_branding`; the binary/image is a versioned static asset, not embedded in a database row.
- Exposes metadata through `public.get_platform_branding_v1()`, a read-only `SECURITY INVOKER` RPC with an empty search path.
- Public/anonymous and authenticated clients can read the active logo metadata. Client writes are denied; changes are migration-controlled.
- Authentication Preview and Branch Preview use a local SVG fallback, then request the current logo URL through the RPC. Only HTTPS raw.githubusercontent.com image URLs are accepted.

## Database security
- RLS enabled on `public.platform_branding`.
- SELECT only for `anon` and `authenticated`, filtered to active records.
- No client INSERT, UPDATE, or DELETE grants.
- RPC execute granted only to `anon` and `authenticated`; no write operations.
- The database stores a URL and alt text, not image bytes. This avoids oversized binary rows and keeps asset versioning in source control.

## Founder access presentation
- Authentication Preview displays an access summary from `current_access_context_v1()`.
- Only `is_platform_owner=true` or an organization containing `dashboard.read` can open the workspace.
- Email verification alone does not open business views.
- Organization and branch records are not created by this feature.

## Remaining gates
- This is a development branch; do not merge or deploy without review.
- Real browser/Android login testing is still required.
- Phone OTP is not configured/verified.
- Branch write RPCs remain disabled until independent approval + apply flow is complete.
- No business data was created or changed by this feature.
