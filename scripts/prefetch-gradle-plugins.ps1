# Prépare Gradle/Android sur PC avec Avast (scan HTTPS) ou proxy entreprise.
# Usage : .\scripts\prefetch-gradle-plugins.ps1
# Puis : flutter run

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path $PSScriptRoot -Parent
$androidDir = Join-Path $projectRoot "android"
$truststore = Join-Path $androidDir "avast-truststore.jks"
$jbr = "C:\Program Files\Android\Android Studio\jbr"
$keytool = Join-Path $jbr "bin\keytool.exe"
$cacerts = Join-Path $jbr "lib\security\cacerts"

if (-not (Test-Path $keytool)) {
    Write-Error "JDK Android Studio introuvable : $jbr"
}

# 1) Truststore avec certificat Avast (ou racine du scan HTTPS)
if (-not (Test-Path $truststore)) {
    Write-Host "Creation $truststore ..."
    Copy-Item $cacerts $truststore -Force
    $avast = Get-ChildItem Cert:\LocalMachine\Root, Cert:\CurrentUser\Root -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -match 'Avast Web/Mail Shield Root' } |
        Select-Object -First 1
    if ($avast) {
        $cer = Join-Path $env:TEMP "avast-root.cer"
        Export-Certificate -Cert $avast -FilePath $cer -Force | Out-Null
        & $keytool -importcert -noprompt -alias avast-ssl-scan -file $cer -keystore $truststore -storepass changeit
        Write-Host "OK : certificat Avast importe"
    } else {
        Write-Host "Pas de certificat Avast dans Windows."
        Write-Host "Si erreur PKIX persiste, lance : .\scripts\import-corporate-ca-to-jbr.ps1"
    }
} else {
    Write-Host "Truststore deja present."
}

# 2) Patch SDK Flutter (depot local + metadata POM pour mode hors-ligne partiel)
$localProps = Join-Path $androidDir "local.properties"
if (-not (Test-Path $localProps)) {
    Write-Error "Lance d'abord : flutter pub get"
}
$flutterSdk = ((Get-Content $localProps | Where-Object { $_ -match '^flutter\.sdk=' }) -replace '^flutter\.sdk=', '').Trim()
$flutterSettings = Join-Path $flutterSdk "packages\flutter_tools\gradle\settings.gradle.kts"
$localRepo = Join-Path $androidDir "local-gradle-plugins"
$fileUri = "file:///$($localRepo.Replace('\', '/'))"
$mavenBlock = @"
        maven {
            url = uri("$fileUri")
            metadataSources {
                mavenPom()
                artifact()
            }
        }
"@

$content = Get-Content $flutterSettings -Raw
if ($content -notmatch [regex]::Escape($localRepo.Replace('\', '/'))) {
    $content = $content -replace '(pluginManagement\s*\{\s*repositories\s*\{)', "`$1`n$mavenBlock"
    $content = $content -replace '(dependencyResolutionManagement\s*\{[^}]*repositories\s*\{)', "`$1`n$mavenBlock"
    Set-Content -Path $flutterSettings -Value $content.TrimEnd() -Encoding UTF8
    Write-Host "OK : depot local reference dans le SDK Flutter"
}

# 3) Gradle warmup
Write-Host ""
Write-Host "Gradle (premier lancement = telechargements, peut prendre 5-10 min)..."
$env:JAVA_HOME = $jbr
$env:PATH = "$jbr\bin;$env:PATH"
Push-Location $androidDir
try {
    & .\gradlew.bat --no-daemon help *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "OK. Lance : flutter run"
    } else {
        Write-Host "Gradle a echoue (code $LASTEXITCODE)."
        Write-Host "Relance sans redirection pour voir l'erreur : cd android; .\gradlew.bat help"
        exit $LASTEXITCODE
    }
} finally {
    Pop-Location
}
