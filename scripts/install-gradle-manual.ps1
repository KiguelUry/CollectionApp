# Installe Gradle 8.14 manuellement si le wrapper échoue (SSL entreprise).
# Usage : .\scripts\install-gradle-manual.ps1

$ErrorActionPreference = "Stop"
$gradleDir = "$env:USERPROFILE\.gradle\wrapper\dists\gradle-8.14-all\c2qonpi39x1mddn7hk5gh9iqj"
$zipPath = Join-Path $gradleDir "gradle-8.14-all.zip"
$url = "https://services.gradle.org/distributions/gradle-8.14-all.zip"

Write-Host "Dossier Gradle : $gradleDir"
New-Item -ItemType Directory -Force -Path $gradleDir | Out-Null

Remove-Item "$gradleDir\*.part" -Force -ErrorAction SilentlyContinue
Remove-Item "$gradleDir\*.lck" -Force -ErrorAction SilentlyContinue

if (Test-Path $zipPath) {
    $size = (Get-Item $zipPath).Length
    if ($size -gt 100MB) {
        Write-Host "Archive déjà présente ($([math]::Round($size/1MB)) Mo). Rien à faire."
        exit 0
    }
    Remove-Item $zipPath -Force
}

Write-Host @"

1) Ouvre ce lien dans Chrome/Edge et enregistre le fichier :
   $url

2) Déplace le ZIP téléchargé vers :
   $zipPath

3) Relance : flutter run

"@

$open = Read-Host "Ouvrir le lien de téléchargement dans le navigateur ? (o/n)"
if ($open -eq "o") {
    Start-Process $url
}
