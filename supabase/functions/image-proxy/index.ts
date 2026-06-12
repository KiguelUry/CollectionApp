/// <reference path="../deno.d.ts" />
// Proxy images pour Flutter Web (CORS) — déployer : supabase functions deploy image-proxy --no-verify-jwt

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, accept",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

const ALLOWED_HOSTS = new Set([
  "cf.geekdo-images.com",
  "boardgamegeek.com",
  "covers.openlibrary.org",
  "assets.tcgdex.net",
  "images.pokemontcg.io",
  "i.discogs.com",
  "img.discogs.com",
  "st.discogs.com",
  "image.tmdb.org",
  "media.rawg.io",
  "cdn.cloudflare.steamstatic.com",
  "cdn.rebrickable.com",
  "images.brickset.com",
  "m.media-amazon.com",
  "books.google.com",
  "lh3.googleusercontent.com",
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

  if (target.protocol !== "https:" && target.protocol !== "http:") {
    return new Response("Invalid protocol", { status: 400, headers: corsHeaders });
  }

  const host = target.hostname.toLowerCase();
  if (!ALLOWED_HOSTS.has(host)) {
    return new Response(`Host not allowed: ${host}`, {
      status: 403,
      headers: corsHeaders,
    });
  }

  const res = await fetch(target.toString(), {
    headers: { "User-Agent": "Collectingo/1.1" },
  });

  const contentType = res.headers.get("Content-Type") ?? "image/jpeg";
  const body = await res.arrayBuffer();

  return new Response(body, {
    status: res.status,
    headers: {
      ...corsHeaders,
      "Content-Type": contentType,
      "Cache-Control": "public, max-age=86400",
    },
  });
});
