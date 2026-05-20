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

Write-Host "web_deploy synchronise depuis build\web" -ForegroundColor Green
Write-Host "Commit + push, puis Vercel redéploie depuis le dashboard (Git)." -ForegroundColor Yellow
