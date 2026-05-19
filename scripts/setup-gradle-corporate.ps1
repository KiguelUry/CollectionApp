# Configure Gradle pour réseau d'entreprise (SSL / plugins.gradle.org).
# À lancer une fois : .\scripts\setup-gradle-corporate.ps1

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path $PSScriptRoot -Parent
$localProps = Join-Path $projectRoot "android\local.properties"

if (-not (Test-Path $localProps)) {
    Write-Error "Fichier introuvable : android\local.properties (lance d'abord flutter pub get)"
}

$flutterSdk = (Get-Content $localProps | Where-Object { $_ -match '^flutter\.sdk=' }) -replace '\\', '/'
$flutterSdk = $flutterSdk -replace '^flutter\.sdk=', ''
if ([string]::IsNullOrWhiteSpace($flutterSdk)) {
    Write-Error "flutter.sdk introuvable dans local.properties"
}

$flutterGradleSettings = Join-Path $flutterSdk "packages\flutter_tools\gradle\settings.gradle.kts"
if (-not (Test-Path $flutterGradleSettings)) {
    Write-Error "Fichier Flutter introuvable : $flutterGradleSettings"
}

# Supprimer l'ancien init script cassé (s'il existe)
$brokenInit = Join-Path $env:USERPROFILE ".gradle\init.d\collection-app-corporate.gradle.kts"
if (Test-Path $brokenInit) {
    Remove-Item $brokenInit -Force
    Write-Host "OK : init script cassé supprimé"
}

$content = Get-Content $flutterGradleSettings -Raw
if ($content -notmatch 'pluginManagement\s*\{') {
    $patch = @"
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

"@
    Set-Content -Path $flutterGradleSettings -Value ($patch + $content) -Encoding UTF8
    Write-Host "OK : pluginManagement ajouté au SDK Flutter"
} else {
    Write-Host "Flutter SDK : pluginManagement déjà présent"
}

Write-Host @"

Prochaine étape :
  cd $projectRoot
  flutter run

Si ça échoue encore, ajoute ton proxy dans android/gradle.properties
ou teste hors réseau Persolis (hotspot 4G).

"@
