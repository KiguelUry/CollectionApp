# Build Flutter Web (release) pour Vercel — embarque .env local via pubspec assets
# Sortie : build\web\  → déployer sur Vercel (CLI ou glisser-déposer du dossier)

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

$flutter = "$env:USERPROFILE\Flutter\flutter\bin\flutter.bat"
if (-not (Test-Path $flutter)) {
    $flutter = "flutter"
}

if (-not (Test-Path ".env")) {
    Write-Error "Fichier .env manquant à la racine (SUPABASE_URL, SUPABASE_ANON_KEY)."
}

Write-Host "Collectingo — build Web release (Vercel)" -ForegroundColor Cyan
& $flutter pub get
& $flutter build web --release --pwa-strategy=none

if (Test-Path "build\web\index.html") {
    & (Join-Path $PSScriptRoot "sync-web-deploy.ps1")
    Write-Host ""
    Write-Host "Pret pour Vercel : commit + push (dossier web_deploy)." -ForegroundColor Green
} else {
    Write-Error "build\web introuvable apres le build."
}
