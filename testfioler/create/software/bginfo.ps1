# --- install BGInfo from web ---
# Ensure TLS 1.2 for modern HTTPS
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$url = 'https://download.sysinternals.com/files/BGInfo.zip'
$zip = Join-Path $env:TEMP 'BGInfo.zip'
$dest = 'C:\Shares\BGInfo'    # change to where you want it

Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
New-Item -Path $dest -ItemType Directory -Force | Out-Null
Expand-Archive -LiteralPath $zip -DestinationPath $dest -Force
Remove-Item $zip -Force
Write-Host "Installed to $dest"

# Optionally, you can run BGInfo with a specific configuration file:    
#$config = 'C:\Path\To\YourConfig.bgi'
$bgiconfig = "<BGInfo>
    <Version>4.30</Version>
    <Fields>
        <Field>
            <Id>1</Id>
            <Name>Computer Name</Name>
            <Value>%COMPUTERNAME%</Value>
        </Field>
        <Field>
            <Id>2</Id>
            <Name>IP Address</Name>
            <Value>%IP_ADDRESS%</Value>
        </Field>
        <!-- Add more fields as needed -->
    </Fields>
    <BackgroundColor>0x000000</BackgroundColor>
    <TextColor>0xFFFFFF</TextColor>
    <FontName>Segoe UI</FontName>
    <FontSize>12</FontSize>
    <Position>BottomRight</Position>"
$bgiconfigPath = Join-Path $dest 'BGInfoConfig.bgi'
$bgiconfig | Out-File -FilePath $bgiconfigPath -Encoding UTF8 -Force
Write-Host "BGInfo configuration saved to $bgiconfigPath"