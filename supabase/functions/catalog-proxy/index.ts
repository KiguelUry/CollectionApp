/// <reference path="../deno.d.ts" />
// Proxy CORS pour Flutter Web :
// - JSON : MangaDex API + iTunes + Google Books + Open Library
// - Images : UNIQUEMENT uploads.mangadex.org (miniatures .256/.512.jpg)
// Déployer : supabase functions deploy catalog-proxy --no-verify-jwt

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, user-agent, accept",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

/** Hosts JSON uniquement. */
const ALLOWED_JSON_HOSTS = new Set([
  "api.mangadex.org",
  "itunes.apple.com",
  "www.googleapis.com",
  "openlibrary.org",
]);

const IMAGE_EXT_RE = /\.(jpe?g|png|webp|gif|avif|bmp|svg)(\?|$)/i;

/** Seul CDN image autorisé (MangaDex anti-hotlink + CORS). */
const ALLOWED_IMAGE_HOST = "uploads.mangadex.org";

function isBlockedImageHost(target: URL): boolean {
  const host = target.hostname.toLowerCase();
  if (host === ALLOWED_IMAGE_HOST) return false;
  if (
    host === "covers.openlibrary.org" ||
    host.includes("mzstatic.com") ||
    host.includes("geekdo-images.com") ||
    host.includes("googleusercontent.com") ||
    host.includes("anilist.co") ||
    host.includes("image.tmdb.org") ||
    host.includes("rawg.io") ||
    (host.includes("books.google.") && target.pathname.includes("/content"))
  ) {
    return true;
  }
  if (IMAGE_EXT_RE.test(target.pathname) && host !== ALLOWED_IMAGE_HOST) {
    return true;
  }
  return false;
}

/** Retire tout suffixe .256/.512 (append officiel OU replace erroné). */
function stripMangaDexThumb(path: string): string {
  let p = path;
  p = p.replace(/\.(jpe?g|png|webp)\.(256|512)\.jpe?g$/i, ".$1");
  p = p.replace(/\.(256|512)\.jpe?g$/i, ".jpg");
  return p;
}

/**
 * Force miniature MangaDex officielle.
 * Append `.256.jpg` / `.512.jpg` au filename (docs MangaDex) —
 * NE PAS remplacer `.jpg` par `.256.jpg` (sert l'original ~2 Mo).
 */
function withMangaDexThumb(target: URL, size: "256" | "512" | "full"): URL {
  const out = new URL(target.toString());
  out.protocol = "https:";
  let path = stripMangaDexThumb(out.pathname);
  if (size !== "full") {
    if (/\.(jpe?g|png|webp)$/i.test(path)) {
      path = `${path}.${size}.jpg`;
    } else {
      path = `${path}.${size}.jpg`;
    }
  }
  out.pathname = path;
  return out;
}

async function fetchMangaDexImage(url: string): Promise<Response | null> {
  try {
    const upstream = await fetch(url, {
      headers: {
        Accept: "image/*,*/*;q=0.8",
        "User-Agent": "Collectingo/1.2",
      },
      redirect: "follow",
    });
    if (!upstream.ok) {
      // Ne consomme pas le body sur 404/403 — on essaie le fallback.
      try {
        await upstream.body?.cancel();
      } catch {
        /* ignore */
      }
      return null;
    }
    const contentType = upstream.headers.get("Content-Type") ?? "";
    if (contentType && !contentType.startsWith("image/")) {
      try {
        await upstream.body?.cancel();
      } catch {
        /* ignore */
      }
      return null;
    }
    return upstream;
  } catch {
    return null;
  }
}

function imageResponse(
  body: ArrayBuffer,
  contentType: string,
  status = 200,
): Response {
  const responseHeaders = new Headers({
    ...corsHeaders,
    "Content-Type": contentType || "image/jpeg",
    // Cache navigateur 1 an — après 1er load, 0 octet Supabase.
    "Cache-Control": "public, max-age=31536000, immutable",
  });
  responseHeaders.delete("set-cookie");
  responseHeaders.delete("set-cookie2");
  return new Response(body, { status, headers: responseHeaders });
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

  const reqUrl = new URL(req.url);
  const raw = reqUrl.searchParams.get("url")?.trim() ?? "";
  let target: URL;
  try {
    target = new URL(raw);
  } catch {
    return new Response("Invalid url", { status: 400, headers: corsHeaders });
  }

  if (target.protocol !== "https:" && target.protocol !== "http:") {
    return new Response("HTTP(S) only", { status: 400, headers: corsHeaders });
  }

  if (target.protocol === "http:") {
    target = new URL(target.toString().replace(/^http:/i, "https:"));
  }

  const host = target.hostname.toLowerCase();

  // --- Images MangaDex uniquement ---
  if (host === ALLOWED_IMAGE_HOST) {
    // Cache Edge (Cloudflare) : 2e hit = 0 fetch MangaDex + moins d'Egress.
    const cache = (globalThis as { caches?: { default: Cache } }).caches
      ?.default;
    const cacheKey = new Request(reqUrl.toString(), { method: "GET" });
    if (cache) {
      const hit = await cache.match(cacheKey);
      if (hit) return hit;
    }

    // Toujours tenter .256.jpg d'abord (Egress). Fallback original si absent.
    const candidates = [
      withMangaDexThumb(target, "256").toString(),
      withMangaDexThumb(target, "full").toString(),
    ];
    // Déduplique si l'URL était déjà en .256
    const seen = new Set<string>();
    let upstream: Response | null = null;
    for (const u of candidates) {
      if (seen.has(u)) continue;
      seen.add(u);
      upstream = await fetchMangaDexImage(u);
      if (upstream) break;
      // Petit backoff si MangaDex refuse sous charge.
      await new Promise((r) => setTimeout(r, 40));
    }

    if (!upstream) {
      return new Response("MangaDex cover unavailable", {
        status: 404,
        headers: {
          ...corsHeaders,
          "Cache-Control": "public, max-age=60",
        },
      });
    }

    const body = await upstream.arrayBuffer();
    const contentType = upstream.headers.get("Content-Type") ?? "image/jpeg";
    const res = imageResponse(body, contentType, 200);
    if (cache) {
      try {
        await cache.put(cacheKey, res.clone());
      } catch {
        /* quota / unsupported — ignore */
      }
    }
    return res;
  }

  if (isBlockedImageHost(target)) {
    return new Response(
      "Images blocked on catalog-proxy (except uploads.mangadex.org).",
      { status: 400, headers: corsHeaders },
    );
  }

  if (!ALLOWED_JSON_HOSTS.has(host)) {
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
    const upstream = await fetch(target.toString(), {
      headers: {
        Accept: "application/json",
        "User-Agent": "Collectingo/1.2",
      },
      redirect: "follow",
    });
    const body = await upstream.arrayBuffer();
    const contentType = upstream.headers.get("Content-Type") ??
      "application/json";
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
