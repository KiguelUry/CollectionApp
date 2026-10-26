/// <reference path="../deno.d.ts" />
// Proxy CORS pour Flutter Web — MangaDex + iTunes (allorigins/codetabs tombent en 520/522).
// Déployer : supabase functions deploy catalog-proxy --no-verify-jwt

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, accept",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

const ALLOWED_HOSTS = new Set([
  "api.mangadex.org",
  "itunes.apple.com",
]);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  if (req.method !== "GET") {
    return new Response("Method not allowed", {
      status: 405,
      headers: corsHeaders,
    });
  }

  const raw = new URL(req.url).searchParams.get("url")?.trim() ?? "";
  let target: URL;
  try {
    target = new URL(raw);
  } catch {
    return new Response("Invalid url", { status: 400, headers: corsHeaders });
  }

  if (target.protocol !== "https:") {
    return new Response("HTTPS only", { status: 400, headers: corsHeaders });
  }

  const host = target.hostname.toLowerCase();
  if (!ALLOWED_HOSTS.has(host)) {
    return new Response(`Host not allowed: ${host}`, {
      status: 403,
      headers: corsHeaders,
    });
  }

  try {
    const upstream = await fetch(target.toString(), {
      headers: {
        Accept: "application/json",
        "User-Agent": "Collectingo/1.1",
      },
    });
    const body = await upstream.arrayBuffer();
    const contentType =
      upstream.headers.get("Content-Type") ?? "application/json";
    return new Response(body, {
      status: upstream.status,
      headers: {
        ...corsHeaders,
        "Content-Type": contentType,
        "Cache-Control": "public, max-age=120",
      },
    });
  } catch (e) {
    return new Response(`Upstream error: ${e}`, {
      status: 502,
      headers: corsHeaders,
    });
  }
});
