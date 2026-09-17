import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...cors, "Content-Type": "application/json" },
});

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return json({ error: "Sign in required" }, 401);

  const userClient = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
  });
  const adminClient = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: authData, error: authError } = await userClient.auth.getUser();
  if (authError || !authData.user) return json({ error: "Invalid session" }, 401);

  const body = await req.json().catch(() => ({}));
  const provider = String(body.provider || "").toLowerCase();
  if (!['mogul', 'labelcaster'].includes(provider)) return json({ error: "Unsupported provider" }, 400);

  const prefix = provider === "mogul" ? "MOGUL" : "LABELCASTER";
  const apiBase = Deno.env.get(`${prefix}_API_BASE_URL`);
  const apiToken = Deno.env.get(`${prefix}_API_TOKEN`);
  const status = apiBase && apiToken ? "authorization_required" : "credentials_required";

  await adminClient.from("artist_provider_connections").upsert({
    artist_id: authData.user.id,
    provider,
    status,
    last_error: apiBase && apiToken ? "Official endpoint mapping has not been approved." : "Official partner credentials have not been configured.",
    updated_at: new Date().toISOString(),
  }, { onConflict: "artist_id,provider" });

  return json({
    provider,
    status,
    connected: false,
    next_action: apiBase && apiToken
      ? "Approve the official API field mapping and sandbox test."
      : "Add official partner API or export credentials to the secure function environment.",
  });
});
