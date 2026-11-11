-- MR RAHAMAN Business Ecosystem: public read-only branding metadata.
-- The optimized logo SVG is versioned in assets/; this row stores its public URL.
begin;
create table if not exists public.platform_branding (
  brand_key text primary key check (brand_key = 'primary'),
  display_name text not null check (length(btrim(display_name)) between 2 and 120),
  logo_url text not null check (logo_url ~ '^https://'),
  logo_alt text not null check (length(btrim(logo_alt)) between 2 and 240),
  is_active boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.platform_branding enable row level security;
revoke all on table public.platform_branding from public, anon, authenticated;
grant select on table public.platform_branding to anon, authenticated;
drop policy if exists platform_branding_public_read on public.platform_branding;
create policy platform_branding_public_read on public.platform_branding
  for select to anon, authenticated using (is_active = true);
insert into public.platform_branding (brand_key, display_name, logo_url, logo_alt, is_active)
values ('primary', 'MR RAHAMAN Business Ecosystem',
 'https://raw.githubusercontent.com/225-m/MR-RAHAMAN-BUSINESS-ECOSYSTEM-/feature/platform-branding-overview-v1/assets/mr-rahaman-logo.svg',
 'MR RAHAMAN Business Ecosystem logo', true)
on conflict (brand_key) do update set
 display_name = excluded.display_name, logo_url = excluded.logo_url,
 logo_alt = excluded.logo_alt, is_active = excluded.is_active, updated_at = now();
create or replace function public.get_platform_branding_v1()
returns jsonb language sql stable security invoker set search_path = ''
as $function$
 select pg_catalog.jsonb_build_object('brand_key', b.brand_key,
  'display_name', b.display_name, 'logo_url', b.logo_url, 'logo_alt', b.logo_alt)
 from public.platform_branding b
 where b.brand_key = 'primary' and b.is_active = true limit 1;
$function$;
revoke all on function public.get_platform_branding_v1() from public, anon, authenticated, service_role;
grant execute on function public.get_platform_branding_v1() to anon, authenticated;
comment on table public.platform_branding is
 'Public, read-only platform brand assets and display metadata. Writes are migration-controlled.';
comment on function public.get_platform_branding_v1() is
 'Returns the active public brand identity. SECURITY INVOKER; reads only an RLS-filtered branding row.';
commit;