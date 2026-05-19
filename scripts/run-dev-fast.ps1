# Démarre l'app sans animation splash + connexion auto si DEV_TEST_* dans .env
# Usage: .\scripts\run-dev-fast.ps1
#        .\scripts\run-dev-fast.ps1 -d chrome

param(
  [string[]]$DeviceArgs = @()
)

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

$defines = @(
  "--dart-define=DEV_SKIP_SPLASH=true",
  "--dart-define=DEV_FAST_START=true"
)

Write-Host "Mode dev rapide (splash + login sautés si session / identifiants dev)" -ForegroundColor Cyan
flutter run @defines @DeviceArgs
