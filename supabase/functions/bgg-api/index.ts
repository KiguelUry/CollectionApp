/// <reference path="../deno.d.ts" />
// API JSON BGG pour Flutter Web — parse le XML côté serveur.
// Déployer : supabase functions deploy bgg-api --no-verify-jwt
// Secret : BGG_APPLICATION_TOKEN (même que bgg-proxy)

const BGG_ORIGIN = "https://boardgamegeek.com";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, accept",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

const MAX_SEARCH = 50;
const MAX_META = 24;
const MAX_HOT = 50;
const THING_CHUNK = 8;
const SEARCH_TYPES = "boardgame,rpgitem,boardgameexpansion";
const SEARCH_CACHE_TTL_MS = 15 * 60 * 1000;
const SEARCH_CACHE_MAX = 48;
const MIN_BGG_GAP_MS = 320;

/** Titres très courts que l’API search BGG rate souvent. */
const KNOWN_BGG_ID_BY_TITLE: Record<string, string> = { ra: "12" };

const searchCache = new Map<string, { at: number; games: GameHit[] }>();
let lastBggHttpAt = 0;
let lastBggStatus: string | undefined;

type GameHit = Record<string, string>;
type ThingMeta = {
  rank?: number;
  thumbnail?: string;
  image?: string;
  title?: string;
  year?: string;
  categories?: string[];
  avgRating?: number;
};

function normalize(s: string): string {
  return s.toLowerCase().trim().replace(/\s+/g, " ");
}

function titleRelevanceScore(title: string, query: string): number {
  const t = normalize(title);
  const q = normalize(query);
  if (!q) return 0;
  if (t === q) return 1000;
  if (t.startsWith(q)) return 500 + (100 - Math.min(t.length, 100));
  for (const word of t.split(/\s+/)) {
    if (word.startsWith(q)) return 350 + (50 - Math.min(word.length, 50));
  }
  if (t.includes(q)) return 120;
  return 0;
}

function primaryTitle(inner: string): string {
  const primary = inner.match(
    /<name[^>]*type="primary"[^>]*value="([^"]*)"/i,
  );
  if (primary?.[1]) return primary[1];
  const any = inner.match(/<name[^>]*value="([^"]*)"/i);
  return any?.[1] ?? "Sans titre";
}

function isSearchableType(attrs: string): boolean {
  return /type="(boardgame|rpgitem|boardgameexpansion)"/i.test(attrs);
}

function exactQueryVariants(query: string): string[] {
  const t = query.trim();
  if (!t) return [];
  const out = new Set<string>([t]);
  const lower = t.toLowerCase();
  out.add(lower);
  if (t.length <= 20 && lower.length > 0) {
    out.add(`${lower[0].toUpperCase()}${lower.slice(1)}`);
  }
  return [...out];
}

function parseSearchItems(xml: string): GameHit[] {
  const out: GameHit[] = [];
  const re = /<item\b([^>]*)>([\s\S]*?)<\/item>/gi;
  let m: RegExpExecArray | null;
  while ((m = re.exec(xml)) !== null) {
    const attrs = m[1];
    const inner = m[2];
    if (!isSearchableType(attrs)) continue;
    const id = attrs.match(/\bid="(\d+)"/i)?.[1];
    if (!id) continue;
    const type = attrs.match(/\btype="([^"]*)"/i)?.[1] ?? "";
    const year =
      inner.match(/<yearpublished[^>]*value="([^"]*)"/i)?.[1] ?? "";
    const hit: GameHit = { id, title: primaryTitle(inner), year };
    if (type) hit.bgg_type = type;
    out.push(hit);
    if (out.length >= MAX_SEARCH) break;
  }
  return out;
}

function parseHotItems(xml: string): GameHit[] {
  const out: GameHit[] = [];
  const re = /<item\b([^>]*)>([\s\S]*?)<\/item>/gi;
  let m: RegExpExecArray | null;
  while ((m = re.exec(xml)) !== null) {
    const attrs = m[1];
    const inner = m[2];
    const id = attrs.match(/\bid="(\d+)"/i)?.[1];
    if (!id) continue;
    const hotRank = attrs.match(/\brank="(\d+)"/i)?.[1] ?? "";
    const year =
      inner.match(/<yearpublished[^>]*value="([^"]*)"/i)?.[1] ?? "";
    const thumb =
      inner.match(/<thumbnail>([^<]*)<\/thumbnail>/i)?.[1]?.trim() ?? "";
    const hit: GameHit = {
      id,
      title: primaryTitle(inner),
      year,
    };
    if (hotRank) hit.hot_rank = hotRank;
    if (thumb) hit.image_url = thumb;
    out.push(hit);
    if (out.length >= MAX_HOT) break;
  }
  return out;
}

async function enrichGameHits(hits: GameHit[]): Promise<GameHit[]> {
  const ids = hits.map((g) => g.id).filter((id) => /^\d+$/.test(id));
  if (ids.length === 0) return hits;

  const meta = new Map<string, ThingMeta>();
  for (let i = 0; i < ids.length; i += THING_CHUNK) {
    const chunk = ids.slice(i, i + THING_CHUNK);
    try {
      const thingXml = await fetchBgg("/xmlapi2/thing", {
        id: chunk.join(","),
        stats: "1",
      });
      for (const [id, m] of parseThingMeta(thingXml)) {
        meta.set(id, m);
      }
    } catch {
      // métadonnées optionnelles
    }
  }

  return hits.map((g) => {
    const m = meta.get(g.id);
    if (!m) return g;
    const next: GameHit = { ...g };
    if (m.rank != null && !next.bgg_rank) next.bgg_rank = String(m.rank);
    if (m.image && !next.image_url) next.image_url = m.image;
    else if (m.thumbnail && !next.image_url) next.image_url = m.thumbnail;
    if (m.thumbnail) next.thumbnail_url = m.thumbnail;
    if (m.title && !next.title) next.title = m.title;
    if (m.year && !next.year) next.year = m.year;
    if (m.categories?.length) next.bgg_categories = m.categories.join("|");
    if (m.avgRating != null && !next.avg_rating) {
      next.avg_rating = m.avgRating.toFixed(1);
    }
    return next;
  });
}

function parseThingMeta(xml: string): Map<string, ThingMeta> {
  const out = new Map<string, ThingMeta>();
  const re = /<item\b([^>]*)>([\s\S]*?)<\/item>/gi;
  let m: RegExpExecArray | null;
  while ((m = re.exec(xml)) !== null) {
    const id = m[1].match(/\bid="(\d+)"/i)?.[1];
    if (!id) continue;
    const inner = m[2];
    const rankMatch = inner.match(
      /<rank[^>]*name="boardgame"[^>]*value="([^"]*)"/i,
    );
    let rank: number | undefined;
    const rawRank = rankMatch?.[1];
    if (rawRank && rawRank !== "Not Ranked") {
      const n = parseInt(rawRank, 10);
      if (!Number.isNaN(n)) rank = n;
    }
    const fullImage =
      inner.match(/<image>([^<]*)<\/image>/i)?.[1]?.trim();
    const thumb =
      inner.match(/<thumbnail>([^<]*)<\/thumbnail>/i)?.[1]?.trim();
    const year =
      inner.match(/<yearpublished[^>]*value="([^"]*)"/i)?.[1] ?? "";
    const categories: string[] = [];
    const linkRe = /<link\b([^>]*)\/?>/gi;
    let lm: RegExpExecArray | null;
    while ((lm = linkRe.exec(inner)) !== null) {
      const attrs = lm[1];
      if (!/type="boardgamecategory"/i.test(attrs)) continue;
      const val = attrs.match(/\bvalue="([^"]*)"/i)?.[1];
      if (val) categories.push(val);
    }
    const avgRaw = inner.match(/<average[^>]*value="([^"]*)"/i)?.[1];
    const avgRating = avgRaw ? parseFloat(avgRaw) : undefined;
    out.set(id, {
      rank,
      image: fullImage || undefined,
      thumbnail: thumb || undefined,
      title: primaryTitle(inner),
      ...(year ? { year } : {}),
      ...(categories.length ? { categories } : {}),
      ...(avgRating != null && !Number.isNaN(avgRating) ? { avgRating } : {}),
    });
  }
  return out;
}

function parseThingItem(xml: string, id: string): Record<string, unknown> | null {
  const itemRe = new RegExp(
    `<item\\b[^>]*\\bid="${id}"[^>]*>([\\s\\S]*?)<\\/item>`,
    "i",
  );
  const m = xml.match(itemRe);
  if (!m) return null;
  const inner = m[1];

  const image =
    inner.match(/<image>([^<]*)<\/image>/i)?.[1]?.trim() ??
    inner.match(/<thumbnail>([^<]*)<\/thumbnail>/i)?.[1]?.trim();

  const attr = (tag: string): number | undefined => {
    const v = inner.match(
      new RegExp(`<${tag}[^>]*value="([^"]*)"`, "i"),
    )?.[1];
    if (!v) return undefined;
    const n = parseInt(v, 10);
    return Number.isNaN(n) ? undefined : n;
  };

  const categories: string[] = [];
  const linkRe = /<link\b([^>]*)\/?>/gi;
  let lm: RegExpExecArray | null;
  while ((lm = linkRe.exec(inner)) !== null) {
    const attrs = lm[1];
    if (!/type="boardgamecategory"/i.test(attrs)) continue;
    const val = attrs.match(/\bvalue="([^"]*)"/i)?.[1];
    if (val) categories.push(val);
  }

  const playingTime =
    attr("playingtime") ?? attr("maxplaytime") ?? attr("minplaytime");

  const itemType = inner.match(/\btype="([^"]*)"/i)?.[1];
  const isExpansion = itemType === "boardgameexpansion";

  let baseBggId: string | undefined;
  let baseTitle: string | undefined;
  if (isExpansion) {
    const linkRe2 = /<link\b([^>]*)\/?>/gi;
    let lm2: RegExpExecArray | null;
    while ((lm2 = linkRe2.exec(inner)) !== null) {
      const attrs = lm2[1];
      const type = attrs.match(/\btype="([^"]*)"/i)?.[1];
      if (type !== "boardgameexpansion") continue;
      if (!/inbound="true"/i.test(attrs)) continue;
      const baseId = attrs.match(/\bid="(\d+)"/i)?.[1];
      const baseName = attrs.match(/\bvalue="([^"]*)"/i)?.[1];
      if (baseId) {
        baseBggId = baseId;
        baseTitle = baseName;
        break;
      }
    }
  }

  const desc = inner.match(/<description>([\s\S]*?)<\/description>/i)?.[1];
  const cleanDesc = stripHtml(desc);
  const bestPlayers = parseBestPlayerCount(inner);
  const avgRaw = inner.match(/<average[^>]*value="([^"]*)"/i)?.[1];
  const avgRating = avgRaw ? parseFloat(avgRaw) : undefined;

  return {
    bgg_id: id,
    ...(image ? { image_url: image } : {}),
    ...(attr("yearpublished") != null
      ? { year_published: attr("yearpublished") }
      : {}),
    ...(attr("minage") != null ? { min_age: attr("minage") } : {}),
    min_players: attr("minplayers") ?? null,
    max_players: attr("maxplayers") ?? null,
    playing_time:
      playingTime != null && playingTime > 0 ? playingTime : null,
    ...(categories.length ? { bgg_categories: categories } : {}),
    ...(cleanDesc ? { bgg_description: cleanDesc } : {}),
    ...(avgRating != null && !Number.isNaN(avgRating) && avgRating > 0
      ? { bgg_avg_rating: avgRating }
      : {}),
    ...(bestPlayers != null ? { bgg_best_players: bestPlayers } : {}),
    ...(isExpansion ? { bgg_is_expansion: true } : {}),
    ...(baseBggId ? { base_game_bgg_id: baseBggId } : {}),
    ...(baseTitle ? { base_game_title: baseTitle } : {}),
  };
}

function stripHtml(html: string | undefined): string {
  if (!html) return "";
  return html.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim();
}

async function fetchGeekItemExtras(
  id: string,
): Promise<Record<string, unknown>> {
  try {
    const res = await fetch(
      `https://boardgamegeek.com/api/geekitems?objectid=${id}&objecttype=thing`,
      {
        headers: {
          "User-Agent": "Collectingo/1.1",
          Accept: "application/json",
        },
      },
    );
    if (!res.ok) return {};
    const data = await res.json();
    const short = data?.item?.short_description?.toString?.()?.trim();
    return short ? { bgg_short_description: short } : {};
  } catch {
    return {};
  }
}

function parseBestPlayerCount(inner: string): number | undefined {
  const pollRe =
    /<poll\b[^>]*\bname="suggested_numplayers"[^>]*>([\s\S]*?)<\/poll>/i;
  const pollMatch = inner.match(pollRe);
  if (!pollMatch) return undefined;

  const pollInner = pollMatch[1];
  let bestCount: number | undefined;
  let maxVotes = 0;
  const resultsRe = /<results\b[^>]*\bnumplayers="([^"]*)"[^>]*>([\s\S]*?)<\/results>/gi;
  let rm: RegExpExecArray | null;
  while ((rm = resultsRe.exec(pollInner)) !== null) {
    const numMatch = rm[1].match(/^(\d+)/);
    if (!numMatch) continue;
    const numPlayers = parseInt(numMatch[1], 10);
    if (Number.isNaN(numPlayers)) continue;

    const resultsInner = rm[2];
    const bestVoteMatch = resultsInner.match(
      /<result\b[^>]*\bvalue="Best"[^>]*\bnumvotes="(\d+)"/i,
    );
    const votes = bestVoteMatch ? parseInt(bestVoteMatch[1], 10) : 0;
    if (!Number.isNaN(votes) && votes > maxVotes) {
      maxVotes = votes;
      bestCount = numPlayers;
    }
  }
  return maxVotes > 0 ? bestCount : undefined;
}

function parseExpansions(xml: string): Array<Record<string, unknown>> {
  const baseMatch = xml.match(/<item\b[^>]*>([\s\S]*?)<\/item>/i);
  if (!baseMatch) return [];

  const baseInner = baseMatch[1];
  const expansionIds = new Map<string, string>();
  const linkRe = /<link\b([^>]*)\/?>/gi;
  let lm: RegExpExecArray | null;
  while ((lm = linkRe.exec(baseInner)) !== null) {
    const attrs = lm[1];
    const type = attrs.match(/\btype="([^"]*)"/i)?.[1];
    if (type !== "boardgameexpansion" && type !== "boardgameintegration") {
      continue;
    }
    if (/inbound="false"/i.test(attrs)) continue;
    const id = attrs.match(/\bid="(\d+)"/i)?.[1];
    const title = attrs.match(/\bvalue="([^"]*)"/i)?.[1];
    if (id && title) expansionIds.set(id, title);
  }
  if (expansionIds.size === 0) return [];

  const expansions: Array<Record<string, unknown>> = [];
  const re = /<item\b([^>]*)>([\s\S]*?)<\/item>/gi;
  let m: RegExpExecArray | null;
  while ((m = re.exec(xml)) !== null) {
    const id = m[1].match(/\bid="(\d+)"/i)?.[1];
    if (!id || !expansionIds.has(id)) continue;
    const inner = m[2];
    const image =
      inner.match(/<image>([^<]*)<\/image>/i)?.[1]?.trim() ??
      inner.match(/<thumbnail>([^<]*)<\/thumbnail>/i)?.[1]?.trim();
    const yearRaw = inner.match(
      /<yearpublished[^>]*value="([^"]*)"/i,
    )?.[1];
    const year = yearRaw ? parseInt(yearRaw, 10) : undefined;
    const rankMatch = inner.match(
      /<rank[^>]*name="boardgame"[^>]*value="([^"]*)"/i,
    );
    let bggRank: number | undefined;
    const rawRank = rankMatch?.[1];
    if (rawRank && rawRank !== "Not Ranked") {
      const n = parseInt(rawRank, 10);
      if (!Number.isNaN(n)) bggRank = n;
    }
    const desc = inner.match(/<description>([\s\S]*?)<\/description>/i)?.[1];
    const clean = stripHtml(desc);
    const summary = clean.length > 140 ? `${clean.slice(0, 137)}…` : clean;

    expansions.push({
      bggId: id,
      title: primaryTitle(inner),
      ...(image ? { imageUrl: image } : {}),
      ...(year != null && !Number.isNaN(year) ? { year } : {}),
      ...(summary ? { summary } : {}),
      ...(bggRank != null ? { bggRank } : {}),
    });
  }

  expansions.sort((a, b) => {
    const ra = a.bggRank as number | undefined;
    const rb = b.bggRank as number | undefined;
    if (ra != null && rb != null) return ra - rb;
    if (ra != null) return -1;
    if (rb != null) return 1;
    const ya = (a.year as number | undefined) ?? 0;
    const yb = (b.year as number | undefined) ?? 0;
    if (ya !== yb) return yb - ya;
    return String(a.title).localeCompare(String(b.title));
  });

  return expansions;
}

async function fetchBgg(path: string, params: Record<string, string>): Promise<string> {
  const token = Deno.env.get("BGG_APPLICATION_TOKEN")?.trim() ?? "";
  if (!token) {
    throw new Error(
      "BGG_APPLICATION_TOKEN manquant (Supabase → Edge Functions → Secrets).",
    );
  }

  const target = new URL(path, BGG_ORIGIN);
  for (const [k, v] of Object.entries(params)) {
    target.searchParams.set(k, v);
  }

  const headers: Record<string, string> = {
    "User-Agent": "Collectingo/1.1",
    Accept: "application/xml",
    Authorization: `Bearer ${token}`,
  };

  let lastStatus = 502;
  let lastBody = "";
  for (let attempt = 0; attempt < 10; attempt++) {
    const now = Date.now();
    const wait = MIN_BGG_GAP_MS - (now - lastBggHttpAt);
    if (wait > 0) await new Promise((r) => setTimeout(r, wait));
    lastBggHttpAt = Date.now();

    const res = await fetch(target.toString(), { headers });
    const text = await res.text();
    lastStatus = res.status;
    lastBody = text;
    if (res.status === 429) {
      lastBggStatus =
        `BGG surchargé — nouvel essai (${attempt + 1}/10)…`;
      await new Promise((r) => setTimeout(r, 900 + attempt * 700));
      continue;
    }
    const pending =
      res.status === 202 ||
      (res.status === 200 && text.includes("Please try again"));
    if (!pending) {
      if (res.status !== 200) {
        throw new Error(`BGG a répondu ${res.status}`);
      }
      return text;
    }
    await new Promise((r) => setTimeout(r, 400 + attempt * 250));
  }
  throw new Error(`BGG indisponible (${lastStatus}) : ${lastBody.slice(0, 120)}`);
}

function sortSearchResults(
  items: GameHit[],
  query: string,
  sort: string,
  meta: Map<string, ThingMeta>,
): void {
  const rankOf = (g: GameHit) => meta.get(g.id)?.rank ?? 999_999;
  const yearOf = (g: GameHit) => parseInt(g.year ?? "", 10) || 0;

  if (sort === "recent") {
    items.sort((a, b) => {
      const y = yearOf(b) - yearOf(a);
      if (y !== 0) return y;
      return rankOf(a) - rankOf(b);
    });
    return;
  }

  if (sort === "popularity") {
    items.sort((a, b) => {
      const ra = rankOf(a);
      const rb = rankOf(b);
      if (ra !== rb) return ra - rb;
      return titleRelevanceScore(b.title, query) -
        titleRelevanceScore(a.title, query);
    });
    return;
  }

  items.sort((a, b) => {
    const relA = titleRelevanceScore(a.title, query);
    const relB = titleRelevanceScore(b.title, query);
    const rankA = rankOf(a);
    const rankB = rankOf(b);
    const popA = rankA < 999_999 ? 3000 - Math.min(rankA, 3000) : 0;
    const popB = rankB < 999_999 ? 3000 - Math.min(rankB, 3000) : 0;
    const scoreA = relA * 6 + popA;
    const scoreB = relB * 6 + popB;
    return scoreB - scoreA;
  });
}

function mergeSearchHits(primary: GameHit[], secondary: GameHit[]): GameHit[] {
  const seen = new Set(primary.map((g) => g.id));
  const out = [...primary];
  for (const g of secondary) {
    if (!g.id || seen.has(g.id)) continue;
    seen.add(g.id);
    out.push(g);
    if (out.length >= MAX_SEARCH) break;
  }
  return out;
}

async function fetchExactSearchHits(
  query: string,
  type = SEARCH_TYPES,
): Promise<GameHit[]> {
  let merged: GameHit[] = [];
  for (const variant of exactQueryVariants(query)) {
    try {
      const exactXml = await fetchBgg("/xmlapi2/search", {
        query: variant,
        type,
        exact: "1",
      });
      merged = mergeSearchHits(merged, parseSearchItems(exactXml));
    } catch {
      // recherche exacte optionnelle
    }
  }
  return merged;
}

async function fetchKnownTitleHits(query: string): Promise<GameHit[]> {
  const id = KNOWN_BGG_ID_BY_TITLE[normalize(query)];
  if (!id) return [];
  try {
    const enriched = await enrichGameHits([{ id, title: "" }]);
    return enriched.filter((g) => g.title?.trim());
  } catch {
    return [];
  }
}

function searchCacheKey(query: string, sort: string): string {
  return `${sort}:${normalize(query)}`;
}

function storeSearchCache(key: string, games: GameHit[]): void {
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

function pinExactTitleMatches(items: GameHit[], query: string): void {
  const q = normalize(query);
  if (!q) return;
  const exact: GameHit[] = [];
  const rest: GameHit[] = [];
  for (const g of items) {
    if (normalize(g.title) === q) exact.push(g);
    else rest.push(g);
  }
  if (exact.length === 0) return;
  items.length = 0;
  items.push(...exact, ...rest);
}

async function handleSearch(query: string, sort: string): Promise<Response> {
  const trimmed = query.trim();
  if (trimmed.length < 1) {
    return json({ games: [] });
  }

  const cacheKey = searchCacheKey(trimmed, sort);
  const cached = searchCache.get(cacheKey);
  if (cached && Date.now() - cached.at < SEARCH_CACHE_TTL_MS) {
    return json({
      games: cached.games,
      cached: true,
      status: "Résultats en cache (moins d’appels BGG)",
    });
  }

  lastBggStatus = "Recherche sur BoardGameGeek…";

  let candidates: GameHit[] = [];
  try {
    if (trimmed.length <= 3) {
      candidates = mergeSearchHits(
        await fetchKnownTitleHits(trimmed),
        mergeSearchHits(
          await fetchExactSearchHits(trimmed, "boardgame"),
          await fetchExactSearchHits(trimmed),
        ),
      );
    } else {
      const xml = await fetchBgg("/xmlapi2/search", {
        query: trimmed,
        type: SEARCH_TYPES,
      });
      candidates = parseSearchItems(xml);
      if (trimmed.length <= 8) {
        candidates = mergeSearchHits(
          await fetchKnownTitleHits(trimmed),
          candidates,
        );
        candidates = mergeSearchHits(
          await fetchExactSearchHits(trimmed, "boardgame"),
          candidates,
        );
        candidates = mergeSearchHits(
          await fetchExactSearchHits(trimmed),
          candidates,
        );
      }
    }
  } catch (e) {
    const known = await fetchKnownTitleHits(trimmed).catch(() => []);
    if (known.length > 0) {
      return json({
        games: known,
        status: lastBggStatus,
        warning: String(e),
      });
    }
    return json(
      {
        error: String(e),
        status: lastBggStatus ??
          "BGG limite les requêtes — réessaie dans quelques secondes.",
      },
      503,
    );
  }

  if (candidates.length === 0) {
    lastBggStatus = undefined;
    return json({ games: [] });
  }

  candidates.sort(
    (a, b) =>
      titleRelevanceScore(b.title, trimmed) -
      titleRelevanceScore(a.title, trimmed),
  );

  const top = candidates.slice(0, MAX_META);
  const enriched = await enrichGameHits(top);
  const meta = new Map<string, ThingMeta>();
  for (const g of enriched) {
    const rank = parseInt(g.bgg_rank ?? "", 10);
    if (!Number.isNaN(rank)) {
      meta.set(g.id, { rank, thumbnail: g.image_url });
    } else if (g.image_url) {
      meta.set(g.id, { thumbnail: g.image_url });
    }
  }

  sortSearchResults(enriched, trimmed, sort, meta);
  pinExactTitleMatches(enriched, trimmed);
  const games = enriched.slice(0, 40);
  storeSearchCache(cacheKey, games);
  lastBggStatus = undefined;
  return json({ games });
}

async function handleHot(): Promise<Response> {
  const xml = await fetchBgg("/xmlapi2/hot", { type: "boardgame" });
  const hot = parseHotItems(xml);
  const enriched = await enrichGameHits(hot);
  enriched.sort((a, b) => {
    const ha = parseInt(a.hot_rank ?? "999", 10);
    const hb = parseInt(b.hot_rank ?? "999", 10);
    if (ha !== hb) return ha - hb;
    const ra = parseInt(a.bgg_rank ?? "999999", 10);
    const rb = parseInt(b.bgg_rank ?? "999999", 10);
    return ra - rb;
  });
  return json({ games: enriched });
}

async function handleMeta(idsParam: string): Promise<Response> {
  const ids = idsParam
    .split(",")
    .map((s) => s.trim())
    .filter((id) => /^\d+$/.test(id))
    .slice(0, MAX_META);
  if (ids.length === 0) return json({ games: [] });

  const hits: GameHit[] = ids.map((id) => ({ id, title: "" }));
  const enriched = await enrichGameHits(hits);
  return json({ games: enriched });
}

async function handleGame(id: string): Promise<Response> {
  if (!/^\d+$/.test(id)) {
    return json({ error: "Invalid id" }, 400);
  }
  const [xml, extras] = await Promise.all([
    fetchBgg("/xmlapi2/thing", { id, stats: "1" }),
    fetchGeekItemExtras(id),
  ]);
  const game = parseThingItem(xml, id);
  if (!game) return json({ error: "Not found" }, 404);
  return json({ game: { ...game, ...extras } });
}

async function handleExpansions(id: string): Promise<Response> {
  if (!/^\d+$/.test(id)) {
    return json({ error: "Invalid id" }, 400);
  }

  const baseXml = await fetchBgg("/xmlapi2/thing", { id });
  const baseMatch = baseXml.match(/<item\b[^>]*>([\s\S]*?)<\/item>/i);
  if (!baseMatch) return json({ expansions: [] });

  const expansionIds = new Map<string, string>();
  const linkRe = /<link\b([^>]*)\/?>/gi;
  let lm: RegExpExecArray | null;
  while ((lm = linkRe.exec(baseMatch[1])) !== null) {
    const attrs = lm[1];
    const type = attrs.match(/\btype="([^"]*)"/i)?.[1];
    if (type !== "boardgameexpansion" && type !== "boardgameintegration") {
      continue;
    }
    if (/inbound="false"/i.test(attrs)) continue;
    const expId = attrs.match(/\bid="(\d+)"/i)?.[1];
    const title = attrs.match(/\bvalue="([^"]*)"/i)?.[1];
    if (expId && title) expansionIds.set(expId, title);
  }
  if (expansionIds.size === 0) return json({ expansions: [] });

  const ids = [...expansionIds.keys()];
  let detailXml = "";
  for (let i = 0; i < ids.length; i += THING_CHUNK) {
    const chunk = ids.slice(i, i + THING_CHUNK);
    const part = await fetchBgg("/xmlapi2/thing", {
      id: chunk.join(","),
      stats: "1",
    });
    detailXml += part;
  }

  return json({ expansions: parseExpansions(baseXml + detailXml) });
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "public, max-age=300",
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
  const action = url.searchParams.get("action") ?? "";

  try {
    switch (action) {
      case "search":
        return await handleSearch(
          url.searchParams.get("query") ?? "",
          url.searchParams.get("sort") ?? "smart",
        );
      case "hot":
        return await handleHot();
      case "meta":
        return await handleMeta(url.searchParams.get("ids") ?? "");
      case "game": {
        const id = url.searchParams.get("id") ?? "";
        return await handleGame(id);
      }
      case "expansions": {
        const id = url.searchParams.get("id") ?? "";
        return await handleExpansions(id);
      }
      default:
        return json({ error: "Unknown action" }, 400);
    }
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    return json({ error: message }, 503);
  }
});
