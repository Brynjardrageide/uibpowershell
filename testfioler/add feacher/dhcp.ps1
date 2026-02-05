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
$dnsList      = "192.168.1.30"# Read-Host "Enter DNS servers (comma separated)"
$scopeName    = "test"# Read-Host "Enter scope name"


# --- CONFIGURE STATIC IP ---
Get-NetIPAddress -InterfaceAlias "Ethernet 2" | Remove-NetIPAddress -Confirm:$false
New-NetIPAddress -InterfaceAlias $nicAlias `
    -IPAddress $serverIP `
    -PrefixLength 24 `
    -DefaultGateway $gateway
set-dnsclientserveraddress -interfacealias $nicAlias `
    -serveraddresses $dnsList,"8.8.8.8"


# Convert prefix to subnet mask (simple + bulletproof)
$mask = "255.255.255.0"
$mask
# Calculate ScopeId from START RANGE (correct way)
$scopeId = "192.168.5.0"
$scopeId
Write-Host "Using ScopeId $scopeId and mask $mask"

# --- CREATE SCOPE ---
Add-DhcpServerv4Scope -Name $scopeName -StartRange $scopeStart -EndRange $scopeEnd -SubnetMask $mask -State Active

# --- DHCP OPTIONS ---
Set-DhcpServerv4OptionValue -ScopeId $scopeId -Router $gateway
Set-DhcpServerv4OptionValue -ScopeId $scopeId -DnsServer $dnsList

Write-Host "DHCP fully configured. Restarting in 15 minutes."
shutdown -r -t 900 -c "Restarting to finalize DHCP installation." -f