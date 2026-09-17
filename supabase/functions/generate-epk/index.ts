import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const escapeHtml = (value: unknown) => String(value ?? "")
  .replaceAll("&", "&amp;")
  .replaceAll("<", "&lt;")
  .replaceAll(">", "&gt;")
  .replaceAll('"', "&quot;")
  .replaceAll("'", "&#039;");

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...cors, "Content-Type": "application/json" },
});

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return json({ error: "Sign in required" }, 401);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const userClient = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } } });
  const adminClient = createClient(url, serviceKey);
  const { data: authData, error: authError } = await userClient.auth.getUser();
  if (authError || !authData.user) return json({ error: "Invalid session" }, 401);

  const artistId = authData.user.id;
  const { data: profile, error: profileError } = await userClient
    .from("artist_profiles")
    .select("id,odiin_artist_id,artist_name,legal_name,bio,genres,city,state_region,booking_email,website_url,social_links,avatar_path,pro_name,ipi_cae")
    .eq("id", artistId)
    .single();
  if (profileError || !profile) return json({ error: "Artist profile not found" }, 404);

  const { data: releases, error: releasesError } = await userClient
    .from("releases")
    .select("id,title,release_type,release_date,status,artwork_path,upc")
    .eq("artist_id", artistId)
    .eq("is_sandbox", false)
    .order("release_date", { ascending: false, nullsFirst: false });
  if (releasesError) return json({ error: "Unable to load catalog" }, 500);

  let avatarUrl = "";
  if (profile.avatar_path) {
    const { data } = await adminClient.storage.from("artist-media").createSignedUrl(profile.avatar_path, 604800);
    avatarUrl = data?.signedUrl ?? "";
  }

  const { count } = await adminClient.from("epks").select("id", { count: "exact", head: true }).eq("artist_id", artistId);
  const version = (count ?? 0) + 1;
  const { data: epk, error: epkError } = await adminClient.from("epks").insert({
    artist_id: artistId,
    version,
    status: "processing",
    profile_snapshot: { ...profile, releases: releases ?? [] },
  }).select("id").single();
  if (epkError || !epk) return json({ error: "Unable to start EPK" }, 500);

  const releaseCards = (releases ?? []).map((release) => `
    <article><h3>${escapeHtml(release.title)}</h3><p>${escapeHtml(release.release_type)} · ${escapeHtml(release.release_date || "Date pending")}</p><small>${escapeHtml(release.status)}</small></article>
  `).join("") || "<p>Catalog details are available upon request.</p>";
  const location = [profile.city, profile.state_region].filter(Boolean).map(escapeHtml).join(", ");
  const genres = Array.isArray(profile.genres) ? profile.genres.map(escapeHtml).join(" · ") : "";
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHtml(profile.artist_name)} — Electronic Press Kit</title><style>:root{--ink:#061018;--green:#32efa6;--blue:#36a8ff;--paper:#f4f8fa}*{box-sizing:border-box}body{margin:0;background:var(--ink);color:var(--paper);font:16px Arial,sans-serif}main{max-width:960px;margin:auto;padding:64px 24px}.hero{display:grid;grid-template-columns:220px 1fr;gap:36px;align-items:center;border-bottom:1px solid #244252;padding-bottom:36px}.portrait{width:220px;height:220px;border-radius:50%;object-fit:cover;border:4px solid var(--green);background:#102330}.eyebrow{color:var(--green);font-size:12px;letter-spacing:.16em;font-weight:800}h1{font-size:56px;margin:8px 0 12px}h2{color:var(--green);margin-top:44px}.meta{color:#9ab0bd}.releases{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:14px}.releases article{background:#102330;border:1px solid #244252;border-radius:14px;padding:18px}a{color:var(--blue)}footer{margin-top:56px;color:#78909d;font-size:12px}@media(max-width:640px){.hero{grid-template-columns:1fr}.portrait{width:160px;height:160px}h1{font-size:40px}}</style></head><body><main><section class="hero">${avatarUrl ? `<img class="portrait" src="${escapeHtml(avatarUrl)}" alt="${escapeHtml(profile.artist_name)}">` : `<div class="portrait"></div>`}<div><div class="eyebrow">OFFICIAL ELECTRONIC PRESS KIT</div><h1>${escapeHtml(profile.artist_name)}</h1><p class="meta">${genres}${genres && location ? " · " : ""}${location}</p>${profile.website_url ? `<p><a href="${escapeHtml(profile.website_url)}">Official website</a></p>` : ""}</div></section><section><h2>Biography</h2><p>${escapeHtml(profile.bio || "Biography available upon request.")}</p></section><section><h2>Selected Releases</h2><div class="releases">${releaseCards}</div></section><section><h2>Contact</h2><p>${escapeHtml(profile.booking_email || "Contact information available upon request.")}</p></section><footer>Generated from the artist's verified distro profile · EPK version ${version}</footer></main></body></html>`;
  const objectPath = `${artistId}/${epk.id}/epk.html`;
  const { error: uploadError } = await adminClient.storage.from("epk-files").upload(objectPath, new Blob([html], { type: "text/html" }), { upsert: false });
  if (uploadError) {
    await adminClient.from("epks").update({ status: "failed", error_message: uploadError.message, completed_at: new Date().toISOString() }).eq("id", epk.id);
    return json({ error: "Unable to save EPK" }, 500);
  }

  await adminClient.from("epks").update({ status: "ready", object_path: objectPath, completed_at: new Date().toISOString() }).eq("id", epk.id);
  const { data: signed } = await adminClient.storage.from("epk-files").createSignedUrl(objectPath, 604800, { download: `${profile.artist_name}-EPK.html` });
  return json({ id: epk.id, version, status: "ready", download_url: signed?.signedUrl ?? null });
});
