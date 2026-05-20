# Copie build\web → web_deploy\ pour déploiement Vercel via Git (sans Node CLI).
# Prérequis : .\scripts\build-web.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$src = Join-Path $root "build\web"
$dst = Join-Path $root "web_deploy"

if (-not (Test-Path (Join-Path $src "index.html"))) {
    Write-Error "Lance d'abord .\scripts\build-web.ps1"
}

if (Test-Path $dst) {
    Remove-Item $dst -Recurse -Force
}
New-Item -ItemType Directory -Path $dst | Out-Null
Copy-Item -Path "$src\*" -Destination $dst -Recurse -Force

# .env embarqué : uniquement Supabase (pas de DEV_TEST ni BGG — le web passe par bgg-proxy).
$envFile = Join-Path $root ".env"
$prodEnv = Join-Path $dst "assets\.env"
if (-not (Test-Path $envFile)) {
    Write-Error "Fichier .env manquant à la racine."
}
$lines = Get-Content $envFile | Where-Object {
    $_ -match '^\s*SUPABASE_URL=' -or $_ -match '^\s*SUPABASE_ANON_KEY='
}
if ($lines.Count -lt 2) {
    Write-Error ".env doit contenir SUPABASE_URL et SUPABASE_ANON_KEY."
}
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($prodEnv, ($lines -join "`n") + "`n", $utf8NoBom)

Write-Host "web_deploy synchronise (assets/.env = Supabase uniquement)" -ForegroundColor Green
Write-Host "Commit + push, puis Vercel redéploie depuis le dashboard (Git)." -ForegroundColor Yellow
