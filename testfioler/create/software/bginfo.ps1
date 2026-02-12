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

# executing bginfo
$bginfoPath = Join-Path $dest 'BGInfo.exe'
if (Test-Path $bginfoPath) {
    Start-Process -FilePath $bginfoPath -ArgumentList "/timer:0" -NoNewWindow
    Write-Host "BGInfo executed successfully."
} else {
    Write-Error "BGInfo executable not found at $bginfoPath"
}