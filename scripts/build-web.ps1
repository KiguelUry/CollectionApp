# Build Flutter Web (release) pour Vercel — embarque .env local via pubspec assets
# Sortie : build\web\  → déployer sur Vercel (CLI ou glisser-déposer du dossier)

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

$flutter = "$env:USERPROFILE\Flutter\flutter\bin\flutter.bat"
if (-not (Test-Path $flutter)) {
    $flutter = "flutter"
}

if (-not (Test-Path '.env')) {
    Write-Error 'Fichier .env manquant a la racine (SUPABASE_URL, SUPABASE_ANON_KEY).'
}

function Get-DotEnvValue([string]$key) {
    $line = Get-Content '.env' | Where-Object { $_ -match "^\s*$key=" } | Select-Object -First 1
    if (-not $line) { return '' }
    return ($line -replace "^\s*$key=", '').Trim()
}

$supabaseUrl = Get-DotEnvValue 'SUPABASE_URL'
$supabaseAnon = Get-DotEnvValue 'SUPABASE_ANON_KEY'
$googleBooks = Get-DotEnvValue 'GOOGLE_BOOKS_API_KEY'
if ([string]::IsNullOrWhiteSpace($supabaseUrl)) {
    $supabaseUrl = 'https://jfudrneoblsiingjqsio.supabase.co'
}
if ([string]::IsNullOrWhiteSpace($supabaseAnon)) {
    Write-Error 'SUPABASE_ANON_KEY manquant dans .env'
}

Write-Host 'Collectingo - build Web release (Vercel)' -ForegroundColor Cyan
& $flutter pub get
& $flutter build web --release --pwa-strategy=none `
    "--dart-define=SUPABASE_URL=$supabaseUrl" `
    "--dart-define=SUPABASE_ANON_KEY=$supabaseAnon" `
    "--dart-define=GOOGLE_BOOKS_API_KEY=$googleBooks"

if (Test-Path 'build\web\index.html') {
    & (Join-Path $PSScriptRoot 'sync-web-deploy.ps1')
    Write-Host ''
    Write-Host 'Pret pour Vercel : commit + push (dossier web_deploy).' -ForegroundColor Green
} else {
    Write-Error 'build\web introuvable apres le build.'
}
