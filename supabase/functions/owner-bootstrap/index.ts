import { createClient } from "npm:@supabase/supabase-js@2";

const URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ALLOWED_USER_ID = "d1b98876-7803-469d-9228-545ab8f8b3d4";
const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return new Response(JSON.stringify({error:"POST required"}), {status:405,headers});

  try {
    const authorization = req.headers.get("Authorization") ?? "";
    const token = authorization.replace(/^Bearer\\s+/i, "");
    if (!token || token === authorization)
      return new Response(JSON.stringify({error:"Authenticated user token required"}), {status:401,headers});

    const userClient = createClient(URL, ANON, {auth:{persistSession:false,autoRefreshToken:false}});
    const {data:{user},error:authError} = await userClient.auth.getUser(token);
    if (authError || !user || user.id !== ALLOWED_USER_ID || !user.email_confirmed_at)
      return new Response(JSON.stringify({error:"Not authorized for first-owner bootstrap"}), {status:403,headers});

    const admin = createClient(URL, SERVICE, {auth:{persistSession:false,autoRefreshToken:false}});
    const {data,error} = await admin.rpc("bootstrap_first_owner_v1",{p_expected_user_id:ALLOWED_USER_ID});
    if (error) return new Response(JSON.stringify({error:error.message}),{status:409,headers});
    return new Response(JSON.stringify(data),{status:200,headers});
  } catch {
    return new Response(JSON.stringify({error:"Bootstrap request failed safely"}),{status:500,headers});
  }
});
