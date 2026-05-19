# Importe le certificat racine Avast (ou proxy) dans le JDK Android Studio.
# Cause typique : "Avast Web/Mail Shield" intercepte HTTPS → PKIX failed dans Gradle/Java.
#
# Lancer PowerShell EN ADMINISTRATEUR :
#   .\scripts\import-corporate-ca-to-jbr.ps1
#
# Alternative : Avast → Paramètres → Protection → Bouclier principal →
#   cocher "Activer le scan HTTPS" → DÉSACTIVER (ou exclure java.exe / gradle)

$ErrorActionPreference = "Stop"
$jbr = "C:\Program Files\Android\Android Studio\jbr"
$keytool = Join-Path $jbr "bin\keytool.exe"
$cacerts = Join-Path $jbr "lib\security\cacerts"
$alias = "avast-ssl-scan-root"
$testUrl = "https://repo.maven.apache.org/maven2/"

if (-not (Test-Path $keytool)) {
    Write-Error "keytool introuvable : $keytool"
}

Write-Host "Certificat vu par Windows pour $testUrl ..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$req = [Net.HttpWebRequest]::Create($testUrl)
$req.AllowAutoRedirect = $true
try { $req.GetResponse().Close() } catch { }

$leaf = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($req.ServicePoint.Certificate)
Write-Host "  Sujet  : $($leaf.Subject)"
Write-Host "  Emetteur : $($leaf.Issuer)"

# Preferer la racine Avast du magasin Windows si presente
$root = Get-ChildItem Cert:\LocalMachine\Root, Cert:\CurrentUser\Root -ErrorAction SilentlyContinue |
    Where-Object { $_.Subject -match 'Avast' -and $_.Subject -match 'Root' } |
    Select-Object -First 1

if ($root) {
    Write-Host "Racine Avast trouvee dans Windows : $($root.Subject)"
    $cerPath = Join-Path $env:TEMP "avast-root.cer"
    Export-Certificate -Cert $root -FilePath $cerPath -Force | Out-Null
} else {
    Write-Host "Import du certificat emetteur (scan HTTPS) ..."
    $cerPath = Join-Path $env:TEMP "https-scan-root.cer"
    $bytes = $leaf.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
    [System.IO.File]::WriteAllBytes($cerPath, $bytes)
}

Write-Host "Import dans $cacerts ..."
& $keytool -delete -alias $alias -keystore $cacerts -storepass changeit 2>$null | Out-Null
& $keytool -importcert -noprompt -alias $alias -file $cerPath -keystore $cacerts -storepass changeit

Write-Host ""
Write-Host "Test HTTPS Java..."
$tmpDir = Join-Path $env:TEMP "ssl-test-java"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
@'
import javax.net.ssl.HttpsURLConnection;
import java.net.URL;
public class SslTest {
  public static void main(String[] a) throws Exception {
    var c = (HttpsURLConnection) new URL("https://repo.maven.apache.org/maven2/").openConnection();
    c.setRequestMethod("HEAD");
    c.connect();
    System.out.println("OK HTTP " + c.getResponseCode());
  }
}
'@ | Set-Content (Join-Path $tmpDir "SslTest.java") -Encoding ASCII
Push-Location $tmpDir
& (Join-Path $jbr "bin\javac.exe") SslTest.java
& (Join-Path $jbr "bin\java.exe") SslTest
Pop-Location

Write-Host ""
Write-Host "Termine. Relance : flutter run"
