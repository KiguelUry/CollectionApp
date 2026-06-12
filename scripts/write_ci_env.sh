#!/usr/bin/env bash
# Génère .env pour le build CI (GitHub Actions) à partir des secrets du repo.
set -euo pipefail

SUPABASE_URL="${SUPABASE_URL:-https://jfudrneoblsiingjqsio.supabase.co}"
SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-sb_publishable_lyB3xo2ORzY6zwrbkn5g3A_7p5ddw7n}"

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
