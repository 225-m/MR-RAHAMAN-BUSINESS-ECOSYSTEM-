import { createClient } from "npm:@supabase/supabase-js@2";

const URL = Deno.env.get("SUPABASE_URL") ?? "";
const ANON = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
// Set only in Supabase Edge Function secrets after staging review. Never commit the value.
const ALLOWED_USER_ID = Deno.env.get("OWNER_BOOTSTRAP_ALLOWED_USER_ID") ?? "";
// Exact trusted browser origin; no wildcard CORS. Never commit the value.
const ALLOWED_ORIGIN = Deno.env.get("OWNER_BOOTSTRAP_ALLOWED_ORIGIN") ?? "";

function responseHeaders(origin: string) {
  return {
    "Access-Control-Allow-Origin": origin === ALLOWED_ORIGIN && ALLOWED_ORIGIN ? ALLOWED_ORIGIN : "null",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
    "Content-Type": "application/json",
  };
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin") ?? "";
  const headers = responseHeaders(origin);

  if (!ALLOWED_ORIGIN || origin !== ALLOWED_ORIGIN) {
    return new Response(JSON.stringify({ error: "Bootstrap origin is not allowlisted" }), { status: 403, headers });
  }
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return new Response(JSON.stringify({ error: "POST required" }), { status: 405, headers });

  if (!ALLOWED_USER_ID || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(ALLOWED_USER_ID)) {
    return new Response(JSON.stringify({ error: "Bootstrap allowlist is not configured" }), { status: 503, headers });
  }
  if (!URL || !ANON || !SERVICE) {
    return new Response(JSON.stringify({ error: "Bootstrap service configuration is incomplete" }), { status: 503, headers });
  }

  try {
    const authorization = req.headers.get("Authorization") ?? "";
    const token = authorization.replace(/^Bearer\s+/i, "");
    if (!token || token === authorization)
      return new Response(JSON.stringify({ error: "Authenticated user token required" }), { status: 401, headers });

    const userClient = createClient(URL, ANON, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: { user }, error: authError } = await userClient.auth.getUser(token);
    if (authError || !user || user.id !== ALLOWED_USER_ID || !user.email_confirmed_at)
      return new Response(JSON.stringify({ error: "Not authorized for first-owner bootstrap" }), { status: 403, headers });

    const admin = createClient(URL, SERVICE, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data, error } = await admin.rpc("bootstrap_first_project_founder_main_admin_v1", { p_expected_user_id: ALLOWED_USER_ID });
    if (error) return new Response(JSON.stringify({ error: "Bootstrap preconditions failed" }), { status: 409, headers });
    return new Response(JSON.stringify(data), { status: 200, headers });
  } catch {
    return new Response(JSON.stringify({ error: "Bootstrap request failed safely" }), { status: 500, headers });
  }
});
