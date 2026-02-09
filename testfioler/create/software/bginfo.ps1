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

# ---------------------------------------------------------
# Create REAL RTF layout (BGInfo requires proper RTF syntax)
# ---------------------------------------------------------

$rtfPath = Join-Path $dest "Layout.rtf"

$rtfContent = @"
{\rtf1\ansi
Computer Name:\tab <computername>\par
Domain:\tab <domain>\par
OS Version:\tab <osversion>\par
Boot Time:\tab <boottime>\par
Uptime:\tab <uptime>\par
\par
================= NETWORK ADAPTERS =================\par
Adapter Description:\tab <adapterdescription>\par
Adapter Name:\tab <adaptername>\par
MAC Address:\tab <macaddress>\par
IP Address:\tab <ipaddress>\par
DHCP Enabled:\tab <dhcpenabled>\par
Adapter Type:\tab <adaptertype>\par
====================================================\par
}
"@

Set-Content -Path $rtfPath -Value $rtfContent -Encoding ASCII
Write-Host "RTF layout created."

# ---------------------------------------------------------
# Generate BGInfoConfig.bgi using BGInfo itself
# ---------------------------------------------------------

$bginfoExe = Join-Path $dest "Bginfo.exe"
$targetBgi = Join-Path $dest "BGInfoConfig.bgi"

& $bginfoExe $rtfPath /timer:0 /silent /nolicprompt /save $targetBgi

if (Test-Path $targetBgi) {
    Write-Host "SUCCESS! BGInfo configuration created at: $targetBgi"
} else {
    Write-Host "FAILED! BGInfo did not create the BGI file."
}