# Install DHCP role
Install-WindowsFeature -Name DHCP -IncludeManagementTools
Import-Module DhcpServer

# Disable IPv6 on ALL adapters
Get-NetAdapterBinding -ComponentID ms_tcpip6 |
    Disable-NetAdapterBinding -ComponentID ms_tcpip6 -Confirm:$false

# --- USER INPUT ---
$nicAlias = "Ethernet 2"

$serverIP     ="192.168.5.30" # Read-Host "Enter static IP (example 192.168.5.10)"
$prefixLength = "24"# Read-Host "Enter prefix length (example 24)"
$scopeStart   = "192.168.5.100"# Read-Host "Enter scope START IP"
$scopeEnd     = "192.168.5.200"# Read-Host "Enter scope END IP"
$gateway      = "192.168.5.1"# Read-Host "Enter default gateway"
$dnsList      = "192.168.5.30"# Read-Host "Enter DNS servers (comma separated)"
$scopeName    = "test"# Read-Host "Enter scope name"

# Convert prefix to subnet mask (simple + bulletproof)
$mask = (New-Object System.Net.IPAddress(
            ([uint32]0xFFFFFFFF -shl (32 - [int]$prefixLength))
        )).IPAddressToString
$mask
# Calculate ScopeId from START RANGE (correct way)
$scopeId = ([System.Net.IPAddress]::Parse($scopeStart).GetAddressBytes() `
            -band [System.Net.IPAddress]::Parse($mask).GetAddressBytes()) `
            -join '.'
$scopeId
Write-Host "Using ScopeId $scopeId and mask $mask"

# --- CONFIGURE STATIC IP ---
Set-NetIPInterface -InterfaceAlias $nicAlias -Dhcp Disabled

Get-NetIPAddress -InterfaceAlias $nicAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

New-NetIPAddress -InterfaceAlias $nicAlias -IPAddress $serverIP -PrefixLength $prefixLength -DefaultGateway $gateway

Set-DnsClientServerAddress -InterfaceAlias $nicAlias -ServerAddresses ($dnsList.Split(","))

# --- DHCP POST INSTALL (correct placement!) ---
Add-DhcpServerSecurityGroup

$hostname = (Get-CimInstance Win32_ComputerSystem).DNSHostName
$domain   = (Get-CimInstance Win32_ComputerSystem).Domain
$fqdn     = "$hostname.$domain"

Add-DhcpServerInDC -DnsName $fqdn -IpAddress $serverIP

# --- CREATE SCOPE ---
Add-DhcpServerv4Scope -Name $scopeName -StartRange $scopeStart -EndRange $scopeEnd -SubnetMask $mask -State Active

# --- DHCP OPTIONS ---
Set-DhcpServerv4OptionValue -ScopeId $scopeId -Router $gateway
Set-DhcpServerv4OptionValue -ScopeId $scopeId -DnsServer ($dnsList.Split(","))

Write-Host "DHCP fully configured. Restarting in 15 minutes."
shutdown -r -t 900 -c "Restarting to finalize DHCP installation." -f
