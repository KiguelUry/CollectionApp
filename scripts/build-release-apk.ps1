# Build APK release pour distribution famille (WhatsApp, Drive, etc.)
# Sortie : build\app\outputs\flutter-apk\app-release.apk

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

Write-Host "Collectingo — build APK release (1.1.0+2)" -ForegroundColor Cyan
flutter pub get
flutter build apk --release

$apk = "build\app\outputs\flutter-apk\app-release.apk"
if (Test-Path $apk) {
    $dest = "dist\Collectingo-1.1.0.apk"
    New-Item -ItemType Directory -Force -Path dist | Out-Null
    Copy-Item $apk $dest -Force
    Write-Host ""
    Write-Host "APK pret : $((Resolve-Path $dest).Path)" -ForegroundColor Green
    Write-Host "Envoie ce fichier a ta famille (fichier complet, ~tens of MB)." -ForegroundColor Yellow
} else {
    Write-Error "APK introuvable apres le build."
}
