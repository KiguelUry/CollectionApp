/// <reference path="../deno.d.ts" />
// Proxy BGG pour Flutter Web (Vercel / Safari) — contourne CORS.
// Déployer : supabase functions deploy bgg-proxy --no-verify-jwt
// Secret : Edge Functions → Secrets → BGG_APPLICATION_TOKEN
const BGG_ORIGIN = "https://boardgamegeek.com";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, accept",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

function isAllowedPath(path: string): boolean {
  return path.startsWith("/xmlapi2/");
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

  const incoming = new URL(req.url);
  const path = incoming.searchParams.get("path") ?? "";
  if (!isAllowedPath(path)) {
    return new Response("Invalid path", { status: 400, headers: corsHeaders });
  }

  const token = Deno.env.get("BGG_APPLICATION_TOKEN")?.trim() ?? "";
  if (!token) {
    return new Response(
      "BGG_APPLICATION_TOKEN manquant. Supabase → Project Settings → Edge Functions → Secrets, " +
        "ajoute BGG_APPLICATION_TOKEN (même valeur que dans ton .env local). " +
        "Voir https://boardgamegeek.com/applications",
      { status: 503, headers: corsHeaders },
    );
  }

  const target = new URL(path, BGG_ORIGIN);
  incoming.searchParams.forEach((value, key) => {
    if (key !== "path") target.searchParams.set(key, value);
  });

  const headers: Record<string, string> = {
    "User-Agent": "Collectingo/1.1",
    "Accept": "application/xml",
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
      return new Response(text, {
        status: res.status,
        headers: {
          ...corsHeaders,
          "Content-Type": res.headers.get("Content-Type") ?? "application/xml",
        },
      });
    }
    await new Promise((r) => setTimeout(r, 400 + attempt * 250));
  }

  return new Response(lastBody, {
    status: lastStatus,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/xml",
    },
  });
});
