# --- install BGInfo from web ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$url  = 'https://download.sysinternals.com/files/BGInfo.zip'
$zip  = Join-Path $env:TEMP 'BGInfo.zip'
$dest = 'C:\Shares\BGInfo'

Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
New-Item -Path $dest -ItemType Directory -Force | Out-Null
Expand-Archive -LiteralPath $zip -DestinationPath $dest -Force
Remove-Item $zip -Force

Write-Host "BGInfo installed to $dest"

# -------------------------------------------------------------
# Create custom BGInfo layout (RTF is required)
# -------------------------------------------------------------
# --- Create multi-adapter BGInfo layout ---

$rtfLayout = @"
Computer Name:           <computername>
Domain:                  <domain>
OS Version:              <osversion>
Boot Time:               <boottime>
Uptime:                  <uptime>

================= NETWORK ADAPTERS =================

Adapter Description:     <adapterdescription>
Adapter Name:            <adaptername>
MAC Address:             <macaddress>
IP Address:              <ipaddress>
DHCP Enabled:            <dhcpenabled>
Adapter Type:            <adaptertype>

====================================================
"@

$rtfPath = Join-Path $dest "Layout.rtf"
$rtfLayout | Out-File $rtfPath -Encoding ASCII -Force

# -------------------------------------------------------------
# Generate a REAL .BGI config using BGInfo itself
# -------------------------------------------------------------
$bginfoExe = Join-Path $dest "Bginfo.exe"
$targetBgi  = Join-Path $dest "BGInfoConfig.bgi"

& $bginfoExe $rtfPath /timer:0 /nolicprompt /silent /save $targetBgi

Write-Host "Created valid BGInfo configuration: $targetBgi"