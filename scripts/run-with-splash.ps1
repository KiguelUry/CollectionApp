# Démarre l'app avec l'animation splash pixel (~10 s, tap pour passer)
# Usage: .\scripts\run-with-splash.ps1
#        .\scripts\run-with-splash.ps1 -d windows

param(
  [string[]]$DeviceArgs = @()
)

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

Write-Host "Mode normal : splash pixel puis connexion" -ForegroundColor Cyan
flutter run @DeviceArgs
