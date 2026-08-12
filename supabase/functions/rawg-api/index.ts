/// <reference path="../deno.d.ts" />
// Proxy RAWG + Steam pour Flutter Web (CORS) — déployer : supabase functions deploy rawg-api --no-verify-jwt
// Secret : RAWG_API_KEY

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, accept",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

type GameHit = Record<string, string>;

const SEARCH_CACHE_TTL_MS = 15 * 60 * 1000;
const SEARCH_CACHE_MAX = 64;
const searchCache = new Map<string, { at: number; games: GameHit[] }>();

function normalize(s: string): string {
  return s.toLowerCase().trim().replace(/\s+/g, " ");
}

function titleRelevanceScore(title: string, query: string): number {
  const t = normalize(title);
  const q = normalize(query);
  if (!q) return 0;
  if (t === q) return 1000;
  if (t.startsWith(q)) return 500;
  if (t.includes(q)) return 120;
  for (const w of t.split(/\s+/)) {
    if (w.startsWith(q)) return 350;
  }
  return 0;
}

function storeCache(key: string, games: GameHit[]): void {
  searchCache.set(key, { at: Date.now(), games: [...games] });
  if (searchCache.size <= SEARCH_CACHE_MAX) return;
  let oldestKey: string | undefined;
  let oldestAt = Infinity;
  for (const [k, v] of searchCache.entries()) {
    if (v.at < oldestAt) {
      oldestAt = v.at;
      oldestKey = k;
    }
  }
  if (oldestKey) searchCache.delete(oldestKey);
}

async function fetchRawg(query: string, key: string): Promise<GameHit[]> {
  const url = new URL("https://api.rawg.io/api/games");
  url.searchParams.set("key", key);
  url.searchParams.set("search", query);
  url.searchParams.set("page_size", "24");

  const res = await fetch(url.toString(), {
    headers: { Accept: "application/json", "User-Agent": "Palomnia/1.0" },
  });
  if (!res.ok) return [];

  const data = await res.json();
  const list = (data.results ?? []) as Record<string, unknown>[];
  const out: GameHit[] = [];

  for (const g of list) {
    const name = g.name?.toString();
    if (!name) continue;
    const platforms = (g.platforms as { platform?: { name?: string } }[] | undefined)
      ?.map((p) => p.platform?.name)
      .filter(Boolean)
      .slice(0, 6)
      .join(", ") ?? "";
    const released = g.released?.toString() ?? "";
    const year = released.length >= 4 ? released.substring(0, 4) : "";
    const rating = typeof g.rating === "number" ? g.rating.toFixed(1) : "";
    const desc = g.description_raw?.toString() ?? g.description?.toString() ?? "";
    const summary = desc.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
    const hit: GameHit = {
      title: name,
      image_url: g.background_image?.toString() ?? "",
      platform: platforms,
      year,
      rawg_id: g.id?.toString() ?? "",
      source: "rawg",
    };
    if (rating) hit.rawg_rating = rating;
    if (summary) hit.summary = summary.length > 280 ? `${summary.slice(0, 277)}…` : summary;
    out.push(hit);
  }
  return out;
}

async function fetchSteam(query: string): Promise<GameHit[]> {
  const url = new URL("https://store.steampowered.com/api/storesearch/");
  url.searchParams.set("term", query);
  url.searchParams.set("l", "french");
  url.searchParams.set("cc", "FR");

  const res = await fetch(url.toString(), {
    headers: { Accept: "application/json", "User-Agent": "Palomnia/1.0" },
  });
  if (!res.ok) return [];

  const data = await res.json();
  const list = (data.items ?? []) as Record<string, unknown>[];
  const out: GameHit[] = [];

  for (const g of list) {
    const name = g.name?.toString();
    if (!name) continue;
    out.push({
      title: name,
      image_url: g.tiny_image?.toString() ?? "",
      platform: "PC (Steam)",
      steam_appid: g.id?.toString() ?? "",
      source: "steam",
    });
  }
  return out;
}

function mergeHits(rawg: GameHit[], steam: GameHit[]): GameHit[] {
  const seen = new Set<string>();
  const out: GameHit[] = [];
  const add = (h: GameHit) => {
    const key = normalize(h.title ?? "");
    if (!key || seen.has(key)) return;
    seen.add(key);
    out.push(h);
  };
  for (const h of rawg) add(h);
  for (const h of steam) add(h);
  return out;
}

async function handleSearch(query: string): Promise<Response> {
  const trimmed = query.trim();
  if (trimmed.length < 2) {
    return json({ games: [] });
  }

  const cacheKey = normalize(trimmed);
  const cached = searchCache.get(cacheKey);
  if (cached && Date.now() - cached.at < SEARCH_CACHE_TTL_MS) {
    return json({ games: cached.games, cached: true });
  }

  const key = Deno.env.get("RAWG_API_KEY")?.trim() ?? "";
  const [rawg, steam] = await Promise.all([
    key ? fetchRawg(trimmed, key) : Promise.resolve([]),
    fetchSteam(trimmed),
  ]);

  let games = mergeHits(rawg, steam);
  games.sort(
    (a, b) =>
      titleRelevanceScore(b.title ?? "", trimmed) -
      titleRelevanceScore(a.title ?? "", trimmed),
  );
  games = games.slice(0, 30);

  storeCache(cacheKey, games);
  return json({ games });
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "public, max-age=120",
    },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
  if (req.method !== "GET") {
    return json({ error: "Method not allowed" }, 405);
  }

  const url = new URL(req.url);
  const action = url.searchParams.get("action") ?? "search";

  try {
    if (action === "search") {
      return await handleSearch(url.searchParams.get("query") ?? "");
    }
    return json({ error: "Unknown action" }, 400);
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    return json({ error: message }, 503);
  }
});
