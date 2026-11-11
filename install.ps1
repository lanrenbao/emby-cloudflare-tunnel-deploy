# install.ps1 - One-click Emby + Cloudflare Tunnel deployment for Windows
# Usage (PowerShell):
#   .\install.ps1 -Domain "media.example.com" -EmbyDir "D:\EmbyServer"
# Prerequisites: Node.js + pm2 installed (npm i -g pm2), a domain hosted on Cloudflare.
param(
    [Parameter(Mandatory=$true)][string]$Domain,
    [string]$EmbyDir = "D:\EmbyServer",
    [string]$CloudflaredDir = "C:\ProgramData\cloudflared",
    [string]$TunnelName = "emby",
    [string]$EmbyVersion = "4.10.2.0"
)

$ErrorActionPreference = "Stop"
$WorkDir = Join-Path $env:TEMP "emby-deploy"
New-Item -ItemType Directory -Force -Path $WorkDir, $CloudflaredDir | Out-Null

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }

# 0. Pre-checks
Step "Checking prerequisites"
if (-not (Get-Command pm2 -ErrorAction SilentlyContinue)) {
    Write-Error "pm2 not found. Install first: npm i -g pm2"
}
if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
    Write-Error "curl.exe not found (built into Windows 10 1803+)"
}

# 1. Download tools
Step "Downloading cloudflared / 7zr / Emby $EmbyVersion"
$cfExe = Join-Path $CloudflaredDir "cloudflared.exe"
if (-not (Test-Path $cfExe)) {
    curl.exe -sL -o $cfExe "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
}
$7zr = Join-Path $WorkDir "7zr.exe"
if (-not (Test-Path $7zr)) {
    curl.exe -sL -o $7zr "https://www.7-zip.org/a/7zr.exe"
}
$emby7z = Join-Path $WorkDir "emby.7z"
if (-not (Test-Path $emby7z)) {
    curl.exe -sL -o $emby7z "https://github.com/MediaBrowser/Emby.Releases/releases/download/$EmbyVersion/embyserver-win-x64-$EmbyVersion.7z"
}
& $cfExe --version | Select-Object -First 1

# 2. Extract Emby
Step "Extracting Emby to $EmbyDir"
if (-not (Test-Path (Join-Path $EmbyDir "EmbyServer.exe"))) {
    & $7zr x $emby7z -o"$EmbyDir" -y | Out-Null
}

# 3. Cloudflare login
Step "Cloudflare authorization (browser will open, pick your domain and click Authorize)"
$certPath = Join-Path $env:USERPROFILE ".cloudflared\cert.pem"
if (-not (Test-Path $certPath)) {
    & $cfExe tunnel login
    if (-not (Test-Path $certPath)) { Write-Error "Login failed: cert.pem not found" }
} else {
    Write-Host "Existing cert found, skipping login."
}

# 4. Create tunnel + DNS route
Step "Creating tunnel '$TunnelName' and routing DNS for $Domain"
$createOut = & $cfExe tunnel create $TunnelName 2>&1 | Out-String
Write-Host $createOut
$credJson = ($createOut | Select-String -Pattern '"([^"]+\.json)"').Matches.Groups[1].Value
if (-not $credJson) { Write-Error "Failed to parse tunnel credentials path. Create the tunnel manually." }
$tunnelId = [IO.Path]::GetFileNameWithoutExtension($credJson)

& $cfExe tunnel route dns $TunnelName $Domain

# 5. Write config.yml
Step "Writing $CloudflaredDir\config.yml"
@"
tunnel: $tunnelId
credentials-file: $credJson

ingress:
  - hostname: $Domain
    service: http://127.0.0.1:8096
  - service: http_status:404
"@ | Set-Content -Path (Join-Path $CloudflaredDir "config.yml") -Encoding utf8

# 6. Register with pm2
Step "Starting emby-server and emby-tunnel via pm2"
pm2 delete emby-server 2>$null | Out-Null
pm2 delete emby-tunnel 2>$null | Out-Null
pm2 start "$EmbyDir\EmbyServer.exe" --name emby-server --cwd "$EmbyDir" | Out-Null
pm2 start "$cfExe" --name emby-tunnel -- --config "$CloudflaredDir\config.yml" --protocol http2 tunnel run $TunnelName | Out-Null
pm2 save | Out-Null

# 7. Verify
Step "Waiting for Emby to start, then verifying"
Start-Sleep -Seconds 12
try {
    $local = Invoke-WebRequest -Uri "http://127.0.0.1:8096/web/" -UseBasicParsing -TimeoutSec 10
    Write-Host "Local Emby:      HTTP $($local.StatusCode)" -ForegroundColor Green
} catch {
    Write-Warning "Local check failed: $($_.Exception.Message)"
}
Start-Sleep -Seconds 5
try {
    $public = Invoke-WebRequest -Uri "https://$Domain/web/" -UseBasicParsing -TimeoutSec 25
    Write-Host "Public endpoint: HTTP $($public.StatusCode)" -ForegroundColor Green
} catch {
    Write-Warning "Public check failed (DNS propagation may take a minute): $($_.Exception.Message)"
}

Write-Host @"

==============================================
 Deployment finished!
   Admin console : https://$Domain/web/
   Manage        : pm2 ls / pm2 restart emby-server
   Data dir      : C:\programdata  (back this up!)
==============================================
"@ -ForegroundColor Yellow
