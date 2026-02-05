# Install DHCP role
Install-WindowsFeature -Name DHCP -IncludeManagementTools
Import-Module DhcpServer

# Disable IPv6 on ALL adapters
Get-NetAdapterBinding -ComponentID ms_tcpip6 |
    Disable-NetAdapterBinding -ComponentID ms_tcpip6 -Confirm:$false

# === DHCP POST-INSTALL WIZARD ===
Add-DhcpServerSecurityGroup

$hostname = (Get-CimInstance Win32_ComputerSystem).DNSHostName
$domain   = (Get-CimInstance Win32_ComputerSystem).Domain
$fqdn     = "$hostname.$domain"

# --- USER INPUT ---
$nicAlias = "Ethernet 2"

$serverIP     = Read-Host "Enter static IP (example 192.168.5.10)"
$prefixLength = Read-Host "Enter prefix length (example: 24)"
$scopeStart   = Read-Host "Enter scope START IP"
$scopeEnd     = Read-Host "Enter scope END IP"
$gateway      = Read-Host "Enter default gateway"
$dnsList      = Read-Host "Enter DNS servers (comma separated)"
$scopeName    = Read-Host "Enter scope name"

# Convert prefix to mask only once
$mask = (New-Object System.Net.IPAddress(
            ([uint32]0xFFFFFFFF -shl (32 - [int]$prefixLength))
        )).IPAddressToString

# Calculate ScopeId = NETWORK ID of the SCOPE, not server
$scopeId = ([System.Net.IPAddress]::Parse($scopeStart).GetAddressBytes() `
            -band [System.Net.IPAddress]::Parse($mask).GetAddressBytes()) `
            -join '.'

Write-Host "ScopeId = $scopeId"

# Authorize DHCP in AD
Add-DhcpServerInDC -DnsName $fqdn -IpAddress $serverIP

# Set static IP
Set-NetIPInterface -InterfaceAlias $nicAlias -Dhcp Disabled

Get-NetIPAddress -InterfaceAlias $nicAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

New-NetIPAddress -InterfaceAlias $nicAlias -IPAddress $serverIP -PrefixLength $prefixLength -DefaultGateway $gateway

Set-DnsClientServerAddress -InterfaceAlias $nicAlias -ServerAddresses ($dnsList.Split(","))

# Create scope
Add-DhcpServerv4Scope -Name $scopeName -StartRange $scopeStart -EndRange $scopeEnd -SubnetMask $mask -State Active

# Set DHCP options
Set-DhcpServerv4OptionValue -ScopeId $scopeId -Router $gateway
Set-DhcpServerv4OptionValue -ScopeId $scopeId -DnsServer ($dnsList.Split(","))

Write-Host "DHCP fully configured. Restarting in 15 minutes."
shutdown -r -t 900 -c "Restarting to finalize DHCP installation." -f