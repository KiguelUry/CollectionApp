/**
 * Cloudflare Worker — remplace supabase/functions/catalog-proxy
 *
 * Déploiement (dash.cloudflare.com) :
 * 1. Workers & Pages → Create → Create Worker → nom `paloma-catalog-proxy` → Deploy
 * 2. Edit code → coller CE fichier entier → Deploy
 * 3. Copier l'URL https://paloma-catalog-proxy.<ton-compte>.workers.dev
 * 4. La coller dans lib/config/catalog_proxy_config.dart (kCloudflareCatalogProxyUrl)
 *
 * Secret optionnel (Settings → Variables) : GOOGLE_BOOKS_API_KEY
 *
 * Appel client : GET /?url=<urlencoded>  (PAS d'apikey → pas de preflight)
 * Lightbox MangaDex .512 : l'URL cible doit déjà finir par .512.jpg
 */

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

const ALLOWED_JSON_HOSTS = new Set([
  "api.mangadex.org",
  "itunes.apple.com",
  "www.googleapis.com",
  "openlibrary.org",
]);

const IMAGE_EXT_RE = /\.(jpe?g|png|webp|gif|avif|bmp|svg)(\?|$)/i;
const ALLOWED_IMAGE_HOST = "uploads.mangadex.org";

function isBlockedImageHost(target) {
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

function stripMangaDexThumb(path) {
  let p = path;
  p = p.replace(/\.(jpe?g|png|webp)\.(256|512)\.jpe?g$/i, ".$1");
  p = p.replace(/\.(256|512)\.jpe?g$/i, ".jpg");
  return p;
}

/** Append officiel MangaDex : file.jpg → file.jpg.256.jpg */
function withMangaDexThumb(target, size) {
  const out = new URL(target.toString());
  out.protocol = "https:";
  let path = stripMangaDexThumb(out.pathname);
  if (size !== "full") {
    path = `${path}.${size}.jpg`;
  }
  out.pathname = path;
  return out;
}

function wants512(target, reqUrl) {
  if (reqUrl.searchParams.get("size") === "512") return true;
  return /\.(jpe?g|png|webp)\.512\.jpe?g$/i.test(target.pathname) ||
    /\.512\.jpe?g$/i.test(target.pathname);
}

async function fetchMangaDexImage(url) {
  try {
    const upstream = await fetch(url, {
      headers: {
        Accept: "image/*,*/*;q=0.8",
        "User-Agent": "Collectingo/1.3-cf",
      },
      redirect: "follow",
    });
    if (!upstream.ok) {
      try {
        await upstream.body?.cancel();
      } catch (_) {
        /* ignore */
      }
      return null;
    }
    const contentType = upstream.headers.get("Content-Type") ?? "";
    if (contentType && !contentType.startsWith("image/")) {
      try {
        await upstream.body?.cancel();
      } catch (_) {
        /* ignore */
      }
      return null;
    }
    return upstream;
  } catch (_) {
    return null;
  }
}

function imageResponse(body, contentType, status = 200) {
  const headers = new Headers({
    ...corsHeaders,
    "Content-Type": contentType || "image/jpeg",
    "Cache-Control": "public, max-age=31536000, immutable",
  });
  headers.delete("set-cookie");
  headers.delete("set-cookie2");
  return new Response(body, { status, headers });
}

export default {
  async fetch(request, env, ctx) {
    if (request.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders });
    }

    if (request.method !== "GET") {
      return new Response("Method not allowed", {
        status: 405,
        headers: corsHeaders,
      });
    }

    const reqUrl = new URL(request.url);
    const raw = reqUrl.searchParams.get("url")?.trim() ?? "";
    let target;
    try {
      target = new URL(raw);
    } catch (_) {
      return new Response("Invalid url", { status: 400, headers: corsHeaders });
    }

    if (target.protocol !== "https:" && target.protocol !== "http:") {
      return new Response("HTTP(S) only", { status: 400, headers: corsHeaders });
    }
    if (target.protocol === "http:") {
      target = new URL(target.toString().replace(/^http:/i, "https:"));
    }

    const host = target.hostname.toLowerCase();
    const cache = caches.default;
    const cacheKey = new Request(reqUrl.toString(), { method: "GET" });

    // --- Images MangaDex ---
    if (host === ALLOWED_IMAGE_HOST) {
      const hit = await cache.match(cacheKey);
      if (hit) return hit;

      const size = wants512(target, reqUrl) ? "512" : "256";
      const candidates = [
        withMangaDexThumb(target, size).toString(),
        withMangaDexThumb(target, "full").toString(),
      ];
      const seen = new Set();
      let upstream = null;
      for (const u of candidates) {
        if (seen.has(u)) continue;
        seen.add(u);
        upstream = await fetchMangaDexImage(u);
        if (upstream) break;
        await new Promise((r) => setTimeout(r, 40));
      }

      if (!upstream) {
        return new Response("MangaDex cover unavailable", {
          status: 404,
          headers: { ...corsHeaders, "Cache-Control": "public, max-age=60" },
        });
      }

      const body = await upstream.arrayBuffer();
      const contentType = upstream.headers.get("Content-Type") ?? "image/jpeg";
      const res = imageResponse(body, contentType, 200);
      ctx.waitUntil(cache.put(cacheKey, res.clone()).catch(() => {}));
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
      const jsonCacheHit = await cache.match(cacheKey);
      if (jsonCacheHit) return jsonCacheHit;

      if (host === "www.googleapis.com" && target.pathname.includes("/books/")) {
        target.searchParams.delete("key");
        const booksKey = (env.GOOGLE_BOOKS_API_KEY || "").trim();
        if (booksKey) target.searchParams.set("key", booksKey);
      }

      const upstream = await fetch(target.toString(), {
        headers: {
          Accept: "application/json",
          "User-Agent": "Collectingo/1.3-cf",
        },
        redirect: "follow",
      });
      const body = await upstream.arrayBuffer();
      const contentType =
        upstream.headers.get("Content-Type") ?? "application/json";
      const headers = new Headers({
        ...corsHeaders,
        "Content-Type": contentType,
        "Cache-Control": "public, max-age=86400, s-maxage=86400",
      });
      headers.delete("set-cookie");
      headers.delete("set-cookie2");
      const res = new Response(body, {
        status: upstream.status,
        headers,
      });
      if (upstream.status === 200) {
        ctx.waitUntil(cache.put(cacheKey, res.clone()).catch(() => {}));
      }
      return res;
    } catch (e) {
      return new Response(`Upstream error: ${e}`, {
        status: 502,
        headers: corsHeaders,
      });
    }
  },
};
