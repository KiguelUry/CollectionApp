/// <reference path="../deno.d.ts" />
// Proxy CORS pour Flutter Web — JSON only (MangaDex API + iTunes + Google Books).
// JAMAIS d'images : 0 Mo d'Egress couverture sur Supabase.
// Déployer : supabase functions deploy catalog-proxy --no-verify-jwt

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, user-agent, accept",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

/** Hosts JSON uniquement — pas de CDN images. */
const ALLOWED_HOSTS = new Set([
  "api.mangadex.org",
  "itunes.apple.com",
  "www.googleapis.com",
  "openlibrary.org",
]);

const IMAGE_EXT_RE = /\.(jpe?g|png|webp|gif|avif|bmp|svg)(\?|$)/i;

function isImageTarget(target: URL): boolean {
  const host = target.hostname.toLowerCase();
  if (
    host === "uploads.mangadex.org" ||
    host === "covers.openlibrary.org" ||
    host.includes("mzstatic.com") ||
    host.includes("geekdo-images.com") ||
    host.includes("googleusercontent.com") ||
    (host.includes("books.google.") && target.pathname.includes("/content"))
  ) {
    return true;
  }
  if (IMAGE_EXT_RE.test(target.pathname)) return true;
  return false;
}

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
    return new Response("HTTP(S) only", { status: 400, headers: corsHeaders });
  }

  if (isImageTarget(target)) {
    return new Response(
      "Images are blocked on catalog-proxy (use wsrv.nl). Zero image egress.",
      { status: 400, headers: corsHeaders },
    );
  }

  const host = target.hostname.toLowerCase();
  if (!ALLOWED_HOSTS.has(host)) {
    return new Response(`Host not allowed: ${host}`, {
      status: 403,
      headers: corsHeaders,
    });
  }

  try {
    if (host === "www.googleapis.com" && target.pathname.includes("/books/")) {
      target.searchParams.delete("key");
      const booksKey = Deno.env.get("GOOGLE_BOOKS_API_KEY")?.trim() ?? "";
      if (booksKey.length > 0) target.searchParams.set("key", booksKey);
    }
    if (target.protocol === "http:") {
      target = new URL(target.toString().replace(/^http:/i, "https:"));
    }
    const upstream = await fetch(target.toString(), {
      headers: {
        Accept: "application/json",
        "User-Agent": "Collectingo/1.1",
      },
      redirect: "follow",
    });
    const body = await upstream.arrayBuffer();
    const contentType = upstream.headers.get("Content-Type") ??
      "application/json";
    // Jamais de Set-Cookie upstream (Cloudflare `__cf_bm` → domaine invalide Firefox).
    const responseHeaders = new Headers({
      ...corsHeaders,
      "Content-Type": contentType,
      "Cache-Control": "public, max-age=86400, s-maxage=86400",
    });
    responseHeaders.delete("set-cookie");
    responseHeaders.delete("set-cookie2");
    return new Response(body, {
      status: upstream.status,
      headers: responseHeaders,
    });
  } catch (e) {
    return new Response(`Upstream error: ${e}`, {
      status: 502,
      headers: corsHeaders,
    });
  }
});
