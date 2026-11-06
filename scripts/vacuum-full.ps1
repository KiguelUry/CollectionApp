# Compacte l'espace mort PostgreSQL (dead tuples) — HORS du SQL Editor Supabase.
# Le SQL Editor refuse VACUUM (transaction) et ne comprend PAS la commande `psql`.
#
# Usage :
#   1. Dashboard Supabase → Project Settings → Database → Connection string → URI
#      (mode Session / direct, pas Transaction pooler si possible)
#   2. PowerShell à la racine du projet :
#        $env:DATABASE_URL = "postgresql://postgres.xxx:MOT_DE_PASSE@db.xxx.supabase.co:5432/postgres"
#        .\scripts\vacuum-full.ps1
#
# Prérequis : `psql` (PostgreSQL client).
#   winget install PostgreSQL.PostgreSQL
#   ou : https://www.postgresql.org/download/windows/ (installer "Command Line Tools")

$ErrorActionPreference = "Stop"

$url = $env:DATABASE_URL
if (-not $url -or $url.Trim() -eq "") {
  Write-Host @"

DATABASE_URL manquante.

1) Supabase Dashboard → Project Settings → Database → Connection string (URI)
2) Puis dans PowerShell :

   `$env:DATABASE_URL = "postgresql://postgres.[REF]:[PASSWORD]@db.[REF].supabase.co:5432/postgres"
   .\scripts\vacuum-full.ps1

"@ -ForegroundColor Yellow
  exit 1
}

$psql = Get-Command psql -ErrorAction SilentlyContinue
if (-not $psql) {
  Write-Host "psql introuvable. Installe les outils client PostgreSQL, puis relance." -ForegroundColor Red
  Write-Host "  winget install PostgreSQL.PostgreSQL" -ForegroundColor Cyan
  exit 1
}

$tables = @(
  "public.collection_items",
  "public.book_volumes",
  "public.book_series",
  "public.bgg_catalog_cache",
  "public.activity_events"
)

Write-Host "VACUUM FULL (une table à la fois, hors transaction)…" -ForegroundColor Cyan
foreach ($t in $tables) {
  Write-Host "→ $t"
  & psql $url -v ON_ERROR_STOP=1 -c "VACUUM FULL $t;"
  if ($LASTEXITCODE -ne 0) {
    Write-Host "Échec sur $t (exit $LASTEXITCODE)" -ForegroundColor Red
    exit $LASTEXITCODE
  }
}

Write-Host "OK — espace mort compacté. Relance ta requête top-10 tailles dans le SQL Editor." -ForegroundColor Green
