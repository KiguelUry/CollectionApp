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
const MAX_META = 20;
/** Taille max d'un batch `/thing?id=` (Découvrir / meta). */
const MAX_THING_BATCH = 20;
const MAX_HOT = 50;
const THING_CHUNK = 20;
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

function decodeHtmlEntities(raw: string): string {
  let s = raw;
  s = s.replace(/&#(\d+);/g, (_, n: string) => {
    const code = parseInt(n, 10);
    return Number.isFinite(code) ? String.fromCharCode(code) : _;
  });
  s = s.replace(/&#x([0-9a-fA-F]+);/gi, (_, h: string) => {
    const code = parseInt(h, 16);
    return Number.isFinite(code) ? String.fromCharCode(code) : _;
  });
  s = s
    .replace(/&nbsp;/g, " ")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&#039;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&ndash;/g, "–")
    .replace(/&mdash;/g, "—")
    .replace(/&hellip;/g, "…")
    .replace(/&rsquo;/g, "’")
    .replace(/&lsquo;/g, "‘")
    .replace(/&amp;/g, "&");
  return s.trim();
}

function primaryTitle(inner: string): string {
  // Uniquement dans le fragment <item> fourni (jamais le document entier).
  // 1) <name type="primary" value="…" /> (ordre d'attributs variable).
  const primary = inner.match(
    /<name\b(?=[^>]*\btype="primary")[^>]*\bvalue="([^"]*)"[^>]*\/?>/i,
  );
  if (primary?.[1]) return decodeHtmlEntities(primary[1]);
  // 2) API Hot : <name value="…" /> sans type (ignorer alternate).
  const plain = inner.match(
    /<name\b(?![^>]*\btype\s*=)[^>]*\bvalue="([^"]*)"[^>]*\/?>/i,
  );
  if (plain?.[1]) return decodeHtmlEntities(plain[1]);
  return "Sans titre";
}

/** Direct-child image only (évite les <image> des <item> imbriqués versions). */
function directImage(inner: string): string | undefined {
  // Coupe les sous-<item> pour ne lire que le corps du nœud courant.
  const flat = inner.replace(/<item\b[\s\S]*?<\/item>/gi, "");
  return (
    flat.match(/<image>([^<]*)<\/image>/i)?.[1]?.trim() ||
    flat.match(/<thumbnail>([^<]*)<\/thumbnail>/i)?.[1]?.trim() ||
    undefined
  );
}

/**
 * Extrait les <item> de premier niveau uniquement (profondeur 1).
 * BGG peut imbriquer des <item> (versions) : un regex non-greedy
 * `<item>…</item>` décalage alors titres/images entre jeux du batch.
 */
function extractTopLevelItems(
  xml: string,
): Array<{ id: string; attrs: string; inner: string }> {
  const out: Array<{ id: string; attrs: string; inner: string }> = [];
  const tagRe = /<\/?item\b[^>]*\/?>/gi;
  let depth = 0;
  let attrs = "";
  let innerStart = -1;
  let m: RegExpExecArray | null;
  while ((m = tagRe.exec(xml)) !== null) {
    const tag = m[0];
    const selfClosing = /\/>\s*$/.test(tag);
    if (tag.startsWith("</")) {
      if (depth === 1 && innerStart >= 0) {
        const id = attrs.match(/\bid="(\d+)"/i)?.[1];
        if (id) {
          out.push({
            id,
            attrs,
            inner: xml.slice(innerStart, m.index),
          });
        }
        innerStart = -1;
        attrs = "";
      }
      if (depth > 0) depth--;
      continue;
    }
    if (selfClosing) {
      if (depth === 0) {
        const a = tag.match(/^<item\b([^>]*)/i)?.[1] ?? "";
        const id = a.match(/\bid="(\d+)"/i)?.[1];
        if (id) out.push({ id, attrs: a, inner: "" });
      }
      continue;
    }
    if (depth === 0) {
      attrs = tag.match(/^<item\b([^>]*)/i)?.[1] ?? "";
      innerStart = m.index + tag.length;
    }
    depth++;
  }
  return out;
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
  for (const { id, attrs, inner } of extractTopLevelItems(xml)) {
    if (!isSearchableType(attrs)) continue;
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
  for (const { id, attrs, inner } of extractTopLevelItems(xml)) {
    const hotRank = attrs.match(/\brank="(\d+)"/i)?.[1] ?? "";
    const year =
      inner.match(/<yearpublished[^>]*value="([^"]*)"/i)?.[1] ?? "";
    const thumb = directImage(inner) ?? "";
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

  // Re-map strictement par id demandé (ordre BGG / index ignorés).
  return hits.map((g) => {
    const m = meta.get(g.id);
    if (!m) return g;
    const next: GameHit = { ...g, id: g.id };
    if (m.rank != null) next.bgg_rank = String(m.rank);
    if (m.image) next.image_url = m.image;
    else if (m.thumbnail) next.image_url = m.thumbnail;
    if (m.thumbnail) next.thumbnail_url = m.thumbnail;
    // Titre + image issus du MÊME nœud <item id="…">.
    if (m.title) next.title = m.title;
    if (m.year) next.year = m.year;
    if (m.categories?.length) next.bgg_categories = m.categories.join("|");
    if (m.avgRating != null) next.avg_rating = m.avgRating.toFixed(1);
    return next;
  });
}

function parseThingMeta(xml: string): Map<string, ThingMeta> {
  const out = new Map<string, ThingMeta>();
  // Dictionnaire indexé par bgg_id — jamais par ordre de réponse BGG.
  for (const { id, inner } of extractTopLevelItems(xml)) {
    const flat = inner.replace(/<item\b[\s\S]*?<\/item>/gi, "");
    const rankMatch = flat.match(
      /<rank[^>]*name="boardgame"[^>]*value="([^"]*)"/i,
    );
    let rank: number | undefined;
    const rawRank = rankMatch?.[1];
    if (rawRank && rawRank !== "Not Ranked") {
      const n = parseInt(rawRank, 10);
      if (!Number.isNaN(n)) rank = n;
    }
    const fullImage = flat.match(/<image>([^<]*)<\/image>/i)?.[1]?.trim();
    const thumb = flat.match(/<thumbnail>([^<]*)<\/thumbnail>/i)?.[1]?.trim();
    const year =
      flat.match(/<yearpublished[^>]*value="([^"]*)"/i)?.[1] ?? "";
    const categories: string[] = [];
    const linkRe = /<link\b([^>]*)\/?>/gi;
    let lm: RegExpExecArray | null;
    while ((lm = linkRe.exec(flat)) !== null) {
      const attrs = lm[1];
      if (!/type="boardgamecategory"/i.test(attrs)) continue;
      const val = attrs.match(/\bvalue="([^"]*)"/i)?.[1];
      if (val) categories.push(val);
    }
    const avgRaw = flat.match(/<average[^>]*value="([^"]*)"/i)?.[1];
    const avgRating = avgRaw ? parseFloat(avgRaw) : undefined;
    out.set(id, {
      rank,
      image: fullImage || undefined,
      thumbnail: thumb || undefined,
      title: primaryTitle(flat),
      ...(year ? { year } : {}),
      ...(categories.length ? { categories } : {}),
      ...(avgRating != null && !Number.isNaN(avgRating) ? { avgRating } : {}),
    });
  }
  return out;
}

function parseThingItem(xml: string, id: string): Record<string, unknown> | null {
  const node = extractTopLevelItems(xml).find((it) => it.id === id);
  if (!node) return null;
  return parseThingItemFromNode(node);
}

function parseThingItemFromNode(
  node: { id: string; attrs: string; inner: string },
): Record<string, unknown> | null {
  const id = node.id;
  const inner = node.inner;
  const flat = inner.replace(/<item\b[\s\S]*?<\/item>/gi, "");

  const image = directImage(inner);
  const galleryUrls = imageUrlsFromThingXml(flat, image);

  const attr = (tag: string): number | undefined => {
    const v = flat.match(
      new RegExp(`<${tag}[^>]*value="([^"]*)"`, "i"),
    )?.[1];
    if (!v) return undefined;
    const n = parseInt(v, 10);
    return Number.isNaN(n) ? undefined : n;
  };

  const categories = linkValues(flat, "boardgamecategory", 12);
  const designers = linkValues(flat, "boardgamedesigner", 4);
  const publishers = linkValues(flat, "boardgamepublisher", 3);

  const playingTime =
    attr("playingtime") ?? attr("maxplaytime") ?? attr("minplaytime");

  const itemType = node.attrs.match(/\btype="([^"]*)"/i)?.[1];
  const isExpansion = itemType === "boardgameexpansion";

  let baseBggId: string | undefined;
  let baseTitle: string | undefined;
  if (isExpansion) {
    const linkRe2 = /<link\b([^>]*)\/?>/gi;
    let lm2: RegExpExecArray | null;
    while ((lm2 = linkRe2.exec(flat)) !== null) {
      const a = lm2[1];
      const type = a.match(/\btype="([^"]*)"/i)?.[1];
      if (type !== "boardgameexpansion") continue;
      if (!/inbound="true"/i.test(a)) continue;
      const baseId = a.match(/\bid="(\d+)"/i)?.[1];
      const baseName = a.match(/\bvalue="([^"]*)"/i)?.[1];
      if (baseId) {
        baseBggId = baseId;
        baseTitle = baseName;
        break;
      }
    }
  }

  const title = primaryTitle(flat);
  const desc = flat.match(/<description>([\s\S]*?)<\/description>/i)?.[1];
  const cleanDesc = stripHtml(desc);
  const bestPlayers = parseBestPlayerCount(flat);
  const avgRaw = flat.match(/<average[^>]*value="([^"]*)"/i)?.[1];
  const avgRating = avgRaw ? parseFloat(avgRaw) : undefined;

  return {
    bgg_id: id,
    id,
    ...(title && title !== "Sans titre" ? { title } : {}),
    ...(image ? { image_url: image } : {}),
    ...(galleryUrls.length ? { bgg_gallery_urls: galleryUrls } : {}),
    ...(attr("yearpublished") != null
      ? { year_published: attr("yearpublished") }
      : {}),
    ...(attr("minage") != null ? { min_age: attr("minage") } : {}),
    min_players: attr("minplayers") ?? null,
    max_players: attr("maxplayers") ?? null,
    playing_time:
      playingTime != null && playingTime > 0 ? playingTime : null,
    ...(categories.length ? { bgg_categories: categories } : {}),
    bgg_designers: designers,
    bgg_publishers: publishers,
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

// XML API2 usually supplies only a cover, but preserve extra image URLs when
// BGG includes them in image elements or link attributes. This does not crawl.
function linkValues(inner: string, type: string, limit: number): string[] {
  const out: string[] = [];
  const linkRe = /<link\b([^>]*)\/?>/gi;
  let lm: RegExpExecArray | null;
  const typeRe = new RegExp(`type="${type}"`, "i");
  while ((lm = linkRe.exec(inner)) !== null) {
    const attrs = lm[1];
    if (!typeRe.test(attrs)) continue;
    const val = attrs.match(/\bvalue="([^"]*)"/i)?.[1];
    if (val && !out.includes(val)) out.push(val);
    if (out.length >= limit) break;
  }
  return out;
}

function imageUrlsFromThingXml(inner: string, cover?: string): string[] {
  const urls = new Set<string>();
  const add = (raw?: string) => {
    const url = raw?.trim();
    if (/^https?:\/\//i.test(url ?? "")) urls.add(url!);
  };

  add(cover);
  const imageRe = /<image>([^<]*)<\/image>/gi;
  let imageMatch: RegExpExecArray | null;
  while ((imageMatch = imageRe.exec(inner)) !== null) add(imageMatch[1]);

  const linkRe = /<link\b([^>]*)\/?>/gi;
  let linkMatch: RegExpExecArray | null;
  while ((linkMatch = linkRe.exec(inner)) !== null) {
    const attrs = linkMatch[1];
    for (const attr of ["url", "href", "image"]) {
      add(attrs.match(new RegExp(`\\b${attr}="([^"]*)"`, "i"))?.[1]);
    }
  }
  return [...urls];
}

function stripHtml(html: string | undefined): string {
  if (!html) return "";
  const named: Record<string, string> = {
    amp: "&",
    lt: "<",
    gt: ">",
    quot: '"',
    apos: "'",
    nbsp: " ",
    ndash: "–",
    mdash: "—",
    hellip: "…",
    rsquo: "’",
    lsquo: "‘",
  };
  return html
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/p\s*>/gi, "\n")
    .replace(/<[^>]*>/g, " ")
    .replace(/&(#x?[0-9a-fA-F]+|[a-zA-Z]+);/g, (all, token: string) => {
      if (token[0] === "#") {
        const code = token[1] === "x" || token[1] === "X"
          ? parseInt(token.slice(2), 16)
          : parseInt(token.slice(1), 10);
        return Number.isFinite(code) ? String.fromCharCode(code) : all;
      }
      return named[token] ?? all;
    })
    .replace(/[ \t]+\n/g, "\n")
    .replace(/[ \t]{2,}/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
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
  const top = extractTopLevelItems(xml);
  if (top.length === 0) return [];

  const baseInner = top[0].inner.replace(/<item\b[\s\S]*?<\/item>/gi, "");
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

  const byId = new Map<string, Record<string, unknown>>();
  for (const { id, inner } of top) {
    if (!expansionIds.has(id)) continue;
    const flat = inner.replace(/<item\b[\s\S]*?<\/item>/gi, "");
    const image = directImage(inner);
    const yearRaw = flat.match(
      /<yearpublished[^>]*value="([^"]*)"/i,
    )?.[1];
    const year = yearRaw ? parseInt(yearRaw, 10) : undefined;
    const rankMatch = flat.match(
      /<rank[^>]*name="boardgame"[^>]*value="([^"]*)"/i,
    );
    let bggRank: number | undefined;
    const rawRank = rankMatch?.[1];
    if (rawRank && rawRank !== "Not Ranked") {
      const n = parseInt(rawRank, 10);
      if (!Number.isNaN(n)) bggRank = n;
    }
    const desc = flat.match(/<description>([\s\S]*?)<\/description>/i)?.[1];
    const clean = stripHtml(desc);
    const summary = clean.length > 140 ? `${clean.slice(0, 137)}…` : clean;
    const avgRaw = flat.match(/<average[^>]*value="([^"]*)"/i)?.[1];
    const avgRating = avgRaw ? parseFloat(avgRaw) : undefined;

    byId.set(id, {
      bggId: id,
      title: primaryTitle(flat),
      ...(image ? { imageUrl: image } : {}),
      ...(year != null && !Number.isNaN(year) ? { year } : {}),
      ...(summary ? { summary } : {}),
      ...(bggRank != null ? { bggRank } : {}),
      ...(avgRating != null && !Number.isNaN(avgRating) && avgRating > 0
        ? { avgRating }
        : {}),
    });
  }

  const expansions = [...expansionIds.keys()]
    .map((id) => byId.get(id))
    .filter((row): row is Record<string, unknown> => row != null);

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

async function handleSearch(
  query: string,
  sort: string,
  lite = false,
): Promise<Response> {
  const trimmed = query.trim();
  if (trimmed.length < 1) {
    return json({ games: [] });
  }

  const cacheKey = searchCacheKey(trimmed, lite ? `${sort}:lite` : sort);
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

  const top = candidates.slice(0, lite ? 40 : MAX_META);
  if (lite) {
    storeSearchCache(cacheKey, top);
    lastBggStatus = undefined;
    return json({
      games: top,
      lite: true,
      status: "Recherche sans fiches détaillées",
    });
  }
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

/**
 * Prochaines sorties : Hot + recherches « recent », années >= 2027
 * (et fin 2026), avec badge crowdfunding / à paraître.
 */
async function handleUpcoming(): Promise<Response> {
  const nowY = new Date().getFullYear();
  const minYear = Math.max(2027, nowY); // strictement futures / 2027+
  const byId = new Map<string, GameHit>();

  const absorb = (games: GameHit[]) => {
    for (const g of games) {
      if (!g.id || byId.has(g.id)) continue;
      const year = parseInt(g.year ?? "", 10);
      if (!Number.isFinite(year) || year < minYear) continue;
      const next: GameHit = { ...g };
      if (year > nowY) next.crowdfunding = "1";
      byId.set(g.id, next);
    }
  };

  try {
    const hotXml = await fetchBgg("/xmlapi2/hot", { type: "boardgame" });
    absorb(await enrichGameHits(parseHotItems(hotXml)));
  } catch {
    // hot optionnel
  }

  // Recherches à tri « recent » pour étoffer 20–30 sorties attendues.
  const queries = [
    "legacy",
    "edition",
    "quest",
    "war",
    "realm",
    "saga",
    "empire",
    "dungeon",
    "kickstarter",
    "campaign",
  ];
  for (const q of queries) {
    if (byId.size >= 30) break;
    try {
      const xml = await fetchBgg("/xmlapi2/search", {
        query: q,
        type: SEARCH_TYPES,
      });
      const hits = parseSearchItems(xml);
      hits.sort((a, b) => {
        const ya = parseInt(a.year ?? "", 10) || 0;
        const yb = parseInt(b.year ?? "", 10) || 0;
        return yb - ya;
      });
      absorb(await enrichGameHits(hits.slice(0, 20)));
    } catch {
      // ignore une requête en échec
    }
  }

  const games = [...byId.values()].sort((a, b) => {
    const ya = parseInt(a.year ?? "", 10) || 9999;
    const yb = parseInt(b.year ?? "", 10) || 9999;
    if (ya !== yb) return ya - yb;
    return (a.title ?? "").localeCompare(b.title ?? "");
  });
  return json({ games: games.slice(0, 40) });
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
  // Ordre = liste demandée, données = Map par id (jamais index XML).
  const byId = new Map(enriched.map((g) => [g.id, g]));
  return json({
    games: ids.map((id) => byId.get(id) ?? { id, title: "" }),
  });
}

/**
 * Batch fiches complètes : 1 appel BGG `thing?id=a,b,…` (≤20) → Map par bgg_id.
 * Utilisé par Découvrir pour éviter N requêtes unitaires.
 */
async function handleThings(idsParam: string): Promise<Response> {
  const ids = [
    ...new Set(
      idsParam
        .split(",")
        .map((s) => s.trim())
        .filter((id) => /^\d+$/.test(id)),
    ),
  ].slice(0, MAX_THING_BATCH);
  if (ids.length === 0) return json({ games: [] });

  const xml = await fetchBgg("/xmlapi2/thing", {
    id: ids.join(","),
    stats: "1",
  });
  const byId = new Map<string, Record<string, unknown>>();
  for (const node of extractTopLevelItems(xml)) {
    const game = parseThingItemFromNode(node);
    if (game) byId.set(node.id, game);
  }
  const games = ids
    .map((id) => byId.get(id))
    .filter((g): g is Record<string, unknown> => g != null);
  return json({ games });
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

async function handleImages(id: string): Promise<Response> {
  if (!/^\d+$/.test(id)) {
    return json({ error: "Invalid id" }, 400);
  }
  const target = new URL("https://api.geekdo.com/api/images");
  target.searchParams.set("ajax", "1");
  target.searchParams.set("gallery", "game");
  target.searchParams.set("nosession", "1");
  target.searchParams.set("objectid", id);
  target.searchParams.set("objecttype", "thing");
  target.searchParams.set("pageid", "1");
  target.searchParams.set("showcount", "12");
  target.searchParams.set("sort", "hot");
  try {
    const res = await fetch(target.toString(), {
      headers: {
        Accept: "application/json",
        "User-Agent": "CollectionFamille/1.0",
      },
    });
    if (!res.ok) return json({ images: [] });
    const body = await res.json();
    const raw = Array.isArray(body?.images) ? body.images : [];
    const images: { url: string; caption: string }[] = [];
    for (const item of raw) {
      const url = bggGalleryUrl(item as Record<string, unknown>);
      if (!url) continue;
      const caption = String(item?.caption ?? "");
      if (caption.toLowerCase().includes("box cover")) continue;
      images.push({ url, caption });
      if (images.length >= 8) break;
    }
    return json({ images });
  } catch {
    return json({ images: [] });
  }
}

function bggGalleryUrl(item: Record<string, unknown> | null): string | null {
  if (!item || typeof item !== "object") return null;
  const images = item.images as Record<string, unknown> | undefined;
  const nested = (size: string) => {
    const node = images?.[size] as Record<string, unknown> | undefined;
    return typeof node?.url === "string" ? node.url : null;
  };
  const raw = nested("large") ||
    nested("medium") ||
    (typeof item.imageurl_lg === "string" ? item.imageurl_lg : null) ||
    (typeof item.imageurl === "string" ? item.imageurl : null) ||
    (typeof item.url === "string" ? item.url : null);
  if (!raw) return null;
  const url = raw.replace(/\\/g, "");
  return url.startsWith("http") ? url : null;
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

function parseCollectionItems(xml: string): Array<Record<string, unknown>> {
  const out: Array<Record<string, unknown>> = [];
  const seen = new Set<string>();
  for (const { id: _ignore, attrs, inner } of extractTopLevelItems(xml)) {
    const id = attrs.match(/\bobjectid="(\d+)"/i)?.[1];
    if (!id || seen.has(id)) continue;
    seen.add(id);
    const flat = inner.replace(/<item\b[\s\S]*?<\/item>/gi, "");
    const subtype = attrs.match(/\bsubtype="([^"]*)"/i)?.[1] ?? "";
    const title =
      flat.match(/<name[^>]*>([^<]*)<\/name>/i)?.[1]?.trim() || "Sans titre";
    const year = parseInt(
      flat.match(/<yearpublished>([^<]*)<\/yearpublished>/i)?.[1] ?? "",
      10,
    );
    const image = flat.match(/<image>([^<]*)<\/image>/i)?.[1]?.trim();
    const thumb = flat.match(/<thumbnail>([^<]*)<\/thumbnail>/i)?.[1]?.trim();
    const statsAttrs = flat.match(/<stats\b([^>]*)>/i)?.[1] ?? "";
    const stat = (name: string): number | undefined => {
      const v = parseInt(
        statsAttrs.match(new RegExp(`\\b${name}="(\\d+)"`, "i"))?.[1] ?? "",
        10,
      );
      return Number.isNaN(v) || v <= 0 ? undefined : v;
    };
    out.push({
      bgg_id: id,
      title,
      ...(Number.isNaN(year) ? {} : { year }),
      ...(image ? { image_url: image } : {}),
      ...(thumb ? { thumbnail_url: thumb } : {}),
      ...(stat("minplayers") ? { min_players: stat("minplayers") } : {}),
      ...(stat("maxplayers") ? { max_players: stat("maxplayers") } : {}),
      ...((stat("playingtime") ?? stat("maxplaytime"))
        ? { playing_time: stat("playingtime") ?? stat("maxplaytime") }
        : {}),
      ...(subtype === "boardgameexpansion" ? { is_expansion: true } : {}),
    });
  }
  return out;
}

/// Collection BGG (jeux possédés). BGG répond 202 tant qu'elle est en file :
/// on renvoie `{ pending: true }` et l'app réessaie.
async function handleCollection(username: string): Promise<Response> {
  const user = username.trim();
  if (!user) return json({ error: "Missing username" }, 400, false);
  const token = Deno.env.get("BGG_APPLICATION_TOKEN")?.trim() ?? "";
  const target = new URL("/xmlapi2/collection", BGG_ORIGIN);
  target.searchParams.set("username", user);
  target.searchParams.set("own", "1");
  target.searchParams.set("stats", "1");
  const headers: Record<string, string> = {
    "User-Agent": "Collectingo/1.1",
    Accept: "application/xml",
  };
  if (token) headers.Authorization = `Bearer ${token}`;

  const now = Date.now();
  const wait = MIN_BGG_GAP_MS - (now - lastBggHttpAt);
  if (wait > 0) await new Promise((r) => setTimeout(r, wait));
  lastBggHttpAt = Date.now();

  const res = await fetch(target.toString(), { headers });
  const text = await res.text();
  if (res.status === 202 || text.includes("Please try again later")) {
    return json({ pending: true, status: "BGG prépare la collection…" }, 200, false);
  }
  if (res.status === 429) {
    return json({ pending: true, status: "BGG surchargé — nouvel essai…" }, 200, false);
  }
  if (res.status !== 200) {
    return json({ error: `BGG a répondu ${res.status}` }, 502, false);
  }
  const err = text.match(/<error>[\s\S]*?<message>([^<]*)<\/message>/i)?.[1];
  if (err) return json({ error: err.trim() }, 404, false);
  return json({ items: parseCollectionItems(text) }, 200, false);
}

async function handlePrices(eid: string): Promise<Response> {
  const id = eid.trim();
  if (!id) return json({ error: "Missing eid" }, 400);
  const pricesUrl = new URL("https://boardgameprices.com/api/info");
  pricesUrl.searchParams.set("eid", id);
  pricesUrl.searchParams.set("currency", "EUR");
  pricesUrl.searchParams.set("destination", "FR");
  pricesUrl.searchParams.set("sitename", "collectingo.app");
  pricesUrl.searchParams.set("locale", "fr");
  pricesUrl.searchParams.set("sort", "CHEAP2");
  const res = await fetch(pricesUrl.toString(), {
    headers: { Accept: "application/json" },
  });
  if (res.ok) {
    const body = await res.json();
    const items = (body as { items?: unknown })?.items;
    if (Array.isArray(items) && items.length > 0) return json(body);
  }
  const market = await fetchGeekMarketEur(id);
  if (market) return json(market);
  if (!res.ok) {
    return json({ error: `BoardGamePrices ${res.status}` }, res.status);
  }
  return json({ items: [] });
}

/// Annonces GeekMarket (EUR) quand BoardGamePrices ne renvoie rien.
async function fetchGeekMarketEur(id: string): Promise<unknown | null> {
  const url =
    `https://api.geekdo.com/api/geekmarket/products?objecttype=thing&objectid=${id}&pageid=1&currency=EUR`;
  try {
    const res = await fetch(url, {
      headers: { Accept: "application/json", "User-Agent": "Collectingo/1.1" },
    });
    if (!res.ok) return null;
    const data = await res.json();
    const products = (data as { products?: unknown; items?: unknown })
      ?.products ??
      (data as { items?: unknown })?.items;
    if (!Array.isArray(products)) return null;
    const prices = [];
    for (const p of products) {
      if (!p || typeof p !== "object") continue;
      const row = p as Record<string, unknown>;
      const raw = row.price ?? row.convertedprice ?? row.prettyprice;
      const eur = typeof raw === "number"
        ? raw
        : parseFloat(String(raw ?? "").replace(",", "."));
      if (!eur || eur <= 0) continue;
      const seller = row.sellername ?? row.username ?? row.user ??
        (row.seller && typeof row.seller === "object"
          ? (row.seller as Record<string, unknown>).username
          : null);
      prices.push({
        product: eur,
        price: eur,
        stock: "Y",
        country: "FR",
        name: String(seller ?? "GeekMarket"),
        link: String(row.listingurl ?? row.url ?? ""),
      });
    }
    if (prices.length === 0) return null;
    return { items: [{ prices, versions: [] }] };
  } catch {
    return null;
  }
}

function json(body: unknown, status = 200, cacheable = true): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": cacheable ? "public, max-age=300" : "no-store",
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
          url.searchParams.get("lite") === "1",
        );
      case "hot":
        return await handleHot();
      case "upcoming":
        return await handleUpcoming();
      case "meta":
        return await handleMeta(url.searchParams.get("ids") ?? "");
      case "things":
        return await handleThings(url.searchParams.get("ids") ?? "");
      case "game": {
        const id = url.searchParams.get("id") ?? "";
        return await handleGame(id);
      }
      case "images": {
        const id = url.searchParams.get("id") ?? "";
        return await handleImages(id);
      }
      case "expansions": {
        const id = url.searchParams.get("id") ?? "";
        return await handleExpansions(id);
      }
      case "collection":
        return await handleCollection(
          url.searchParams.get("username") ?? "",
        );
      case "prices": {
        const eid = url.searchParams.get("eid") ?? "";
        return await handlePrices(eid);
      }
      default:
        return json({ error: "Unknown action" }, 400);
    }
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    return json({ error: message }, 503);
  }
});
