/// <reference path="../deno.d.ts" />
// Proxy RiftScribe pour Flutter Web — contourne CORS (pas de clé API).
// Déployer : supabase functions deploy riftscribe-proxy --no-verify-jwt
const RIFTSCRIBE_ORIGIN = "https://riftscribe.gg";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, accept",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

function isAllowedPath(path: string): boolean {
  return path.startsWith("/api/cards");
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

  const target = new URL(path, RIFTSCRIBE_ORIGIN);
  incoming.searchParams.forEach((value, key) => {
    if (key !== "path" && key !== "apikey") target.searchParams.set(key, value);
  });

  const res = await fetch(target.toString(), {
    headers: {
      "User-Agent": "Collectingo/1.1",
      Accept: "application/json",
    },
  });

  const body = await res.text();
  const outHeaders: Record<string, string> = {
    ...corsHeaders,
    "Content-Type": res.headers.get("Content-Type") ?? "application/json",
  };
  const total = res.headers.get("x-total-count");
  if (total) outHeaders["x-total-count"] = total;

  return new Response(body, {
    status: res.status,
    headers: outHeaders,
  });
});
