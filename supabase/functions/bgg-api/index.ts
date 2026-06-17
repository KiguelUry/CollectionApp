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

const MAX_SEARCH = 40;
const MAX_META = 15;
const THING_CHUNK = 8;

type GameHit = Record<string, string>;
type ThingMeta = { rank?: number; thumbnail?: string };

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

function parseSearchItems(xml: string): GameHit[] {
  const out: GameHit[] = [];
  const re = /<item\b([^>]*)>([\s\S]*?)<\/item>/gi;
  let m: RegExpExecArray | null;
  while ((m = re.exec(xml)) !== null) {
    const attrs = m[1];
    const inner = m[2];
    if (!/type="boardgame"/i.test(attrs)) continue;
    const id = attrs.match(/\bid="(\d+)"/i)?.[1];
    if (!id) continue;
    const year =
      inner.match(/<yearpublished[^>]*value="([^"]*)"/i)?.[1] ?? "";
    out.push({ id, title: primaryTitle(inner), year });
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
    if (out.length >= 20) break;
  }
  return out;
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
    const thumb =
      inner.match(/<thumbnail>([^<]*)<\/thumbnail>/i)?.[1]?.trim() ??
      inner.match(/<image>([^<]*)<\/image>/i)?.[1]?.trim();
    out.set(id, {
      rank,
      thumbnail: thumb || undefined,
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
  };
}

function stripHtml(html: string | undefined): string {
  if (!html) return "";
  return html.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim();
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
    const res = await fetch(target.toString(), { headers });
    const text = await res.text();
    lastStatus = res.status;
    lastBody = text;
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

  items.sort((a, b) => {
    const relA = titleRelevanceScore(a.title, query);
    const relB = titleRelevanceScore(b.title, query);
    const rankA = rankOf(a);
    const rankB = rankOf(b);
    const popA = rankA < 999_999 ? 2000 - Math.min(rankA, 2000) : 0;
    const popB = rankB < 999_999 ? 2000 - Math.min(rankB, 2000) : 0;
    const scoreA = relA * 10 + popA;
    const scoreB = relB * 10 + popB;
    return scoreB - scoreA;
  });
}

async function handleSearch(query: string, sort: string): Promise<Response> {
  const trimmed = query.trim();
  if (trimmed.length < 1) {
    return json({ games: [] });
  }

  const xml = await fetchBgg("/xmlapi2/search", {
    query: trimmed,
    type: "boardgame",
  });
  const candidates = parseSearchItems(xml);
  if (candidates.length === 0) return json({ games: [] });

  candidates.sort(
    (a, b) => titleRelevanceScore(b.title, trimmed) -
      titleRelevanceScore(a.title, trimmed),
  );

  const top = candidates.slice(0, MAX_META);
  const meta = new Map<string, ThingMeta>();

  for (let i = 0; i < top.length; i += THING_CHUNK) {
    const chunk = top.slice(i, i + THING_CHUNK).map((g) => g.id);
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

  const ranked = top.map((g) => {
    const m = meta.get(g.id);
    const hit: GameHit = { ...g };
    if (m?.rank != null) hit.bgg_rank = String(m.rank);
    if (m?.thumbnail) hit.image_url = m.thumbnail;
    return hit;
  });

  sortSearchResults(ranked, trimmed, sort, meta);
  return json({ games: ranked.slice(0, 20) });
}

async function handleHot(): Promise<Response> {
  const xml = await fetchBgg("/xmlapi2/hot", { type: "boardgame" });
  return json({ games: parseHotItems(xml) });
}

async function handleGame(id: string): Promise<Response> {
  if (!/^\d+$/.test(id)) {
    return json({ error: "Invalid id" }, 400);
  }
  const xml = await fetchBgg("/xmlapi2/thing", { id });
  const game = parseThingItem(xml, id);
  if (!game) return json({ error: "Not found" }, 404);
  return json({ game });
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
