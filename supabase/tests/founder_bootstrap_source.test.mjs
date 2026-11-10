import { readFileSync } from "node:fs";
import test from "node:test";
import assert from "node:assert/strict";

const read = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const edge = read("../functions/owner-bootstrap/index.ts");
const config = read("../config.toml");
const bootstrap = read("../drafts/first_project_founder_main_admin_bootstrap_v1.sql");
const owner = read("../drafts/platform_owner_management_v1.sql");
const founder = read("../drafts/founder_access_context_extension_v1.sql");

test("Edge Function requires platform JWT verification", () => {
  assert.match(config, /\[functions\.owner-bootstrap\]\s*verify_jwt\s*=\s*true/);
});

test("Edge Function validates bearer token with Supabase Auth", () => {
  assert.match(edge, /auth\.getUser\(token\)/);
  assert.match(edge, /user\.id\s*!==\s*ALLOWED_USER_ID/);
  assert.match(edge, /user\.email_confirmed_at/);
});

test("Edge Function pins exact origin and does not wildcard CORS", () => {
  assert.match(edge, /origin\s*!==\s*ALLOWED_ORIGIN/);
  assert.doesNotMatch(edge, /Access-Control-Allow-Origin["']?\s*:\s*["']\*["']/);
});

test("service role secret is server-side and request body identity is never trusted", () => {
  assert.match(edge, /SUPABASE_SERVICE_ROLE_KEY/);
  assert.match(edge, /admin\.rpc\("bootstrap_first_project_founder_main_admin_v1"/);
  assert.doesNotMatch(edge, /req\.json\(/);
  assert.doesNotMatch(edge, /Deno\.env\.get\(["']SUPABASE_SERVICE_ROLE_KEY["']\).*console\./s);
});

test("database bootstrap is service-role-only, serialized, one-time and audited", () => {
  assert.match(bootstrap, /request\.jwt\.claim\.role/);
  assert.match(bootstrap, /service_role required/);
  assert.match(bootstrap, /pg_advisory_xact_lock/);
  assert.match(bootstrap, /First-founder bootstrap is closed/);
  assert.match(bootstrap, /platform_audit_logs/);
  assert.match(bootstrap, /module_audit_logs/);
  assert.match(bootstrap, /revoke all on function public\.bootstrap_first_project_founder_main_admin_v1/);
});

test("Founder title is not itself an authorization grant", () => {
  assert.match(founder, /v_is_platform_owner/);
  assert.match(founder, /is_platform_owner/);
  assert.match(founder, /is_project_founder/);
  assert.match(founder, /platform_title/);
});

test("last active Platform Owner cannot be revoked", () => {
  assert.match(owner, /Cannot revoke the last active Platform Owner/);
  assert.match(owner, /pg_advisory_xact_lock/);
});
