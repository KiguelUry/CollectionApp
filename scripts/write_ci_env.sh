#!/usr/bin/env bash
# Génère .env pour le build CI (GitHub Actions) à partir des secrets du repo.
# SUPABASE_URL doit être exact : https://jfudrneoblsiingjqsio.supabase.co (deux « i »).
# Les secrets vides ("") sont traités comme absents → fallback (évite "No API key").
set -euo pipefail

_default_url='https://jfudrneoblsiingjqsio.supabase.co'
_default_anon='sb_publishable_lyB3xo2ORzY6zwrbkn5g3A_7p5ddw7n'

# ${VAR:-default} ne s'applique PAS si VAR="" (set but empty) → on normalise.
_pick() {
  local val="${1:-}"
  local fallback="$2"
  if [ -n "$val" ]; then
    printf '%s' "$val"
  else
    printf '%s' "$fallback"
  fi
}

SUPABASE_URL="$(_pick "${SUPABASE_URL:-}" "$_default_url")"
SUPABASE_ANON_KEY="$(_pick "${SUPABASE_ANON_KEY:-}" "$_default_anon")"

cat > .env <<EOF
SUPABASE_URL=${SUPABASE_URL}
SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}
BGG_APPLICATION_TOKEN=${BGG_APPLICATION_TOKEN:-}
GOOGLE_BOOKS_API_KEY=${GOOGLE_BOOKS_API_KEY:-}
DISCOGS_TOKEN=${DISCOGS_TOKEN:-}
TMDB_API_KEY=${TMDB_API_KEY:-}
RAWG_API_KEY=${RAWG_API_KEY:-}
REBRICKABLE_API_KEY=${REBRICKABLE_API_KEY:-}
EOF

echo "write_ci_env: SUPABASE key length=${#SUPABASE_ANON_KEY}, GB key length=${#GOOGLE_BOOKS_API_KEY}"
