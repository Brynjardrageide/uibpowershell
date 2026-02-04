# Install DHCP role
Install-WindowsFeature -Name DHCP -IncludeManagementTools
Import-Module DhcpServer

# ipv6
# Disable IPv6 on ALL network adapters
Get-NetAdapterBinding -ComponentID ms_tcpip6 | Disable-NetAdapterBinding -ComponentID ms_tcpip6 -Confirm:$false

# --- INPUTS ---
$nicAlias = "Ethernet 2"   # Fixed NIC for DHCP server

$serverIP = Read-Host "Enter the IP address you want to assign to Ethernet 2 (e.g., 192.168.5.10)"
$prefixLength = Read-Host "Enter prefix length (24 = 255.255.255.0)"
$scopeStartIp = Read-Host "Enter DHCP scope START IP (e.g., 192.168.5.50)"
$scopeEndIp = Read-Host "Enter DHCP scope END IP (e.g., 192.168.5.200)"
$scopeGateway = Read-Host "Enter Default Gateway for the scope (e.g., 192.168.5.1)"
$scopeDns = Read-Host "Enter DNS servers (comma separated)"
$scopeName = Read-Host "Enter Scope name (e.g., Office 192.168.5.x)"

# Convert prefix to subnet mask (matches Microsoft examples)
function Convert-PrefixToMask {
    param([int]$Prefix)

    $mask = [uint32]0
    if ($Prefix -gt 0) {
        $mask = 0xffffffff -shl (32 - $Prefix)
    }

    return [System.Net.IPAddress]$mask
}

# Calculate network ID from IP + mask
function Get-NetworkID {
    param([string]$Ip, [string]$Mask)

    $ipBytes = [System.Net.IPAddress]::Parse($Ip).GetAddressBytes()
    $maskBytes = [System.Net.IPAddress]::Parse($Mask).GetAddressBytes()

    $netBytes = for ($i=0; $i -lt 4; $i++) { $ipBytes[$i] -band $maskBytes[$i] }
    return ($netBytes -join '.')
}

# Generate subnet mask from prefix
$subnetMask = Convert-PrefixToMask -Prefix $prefixLength
$scopeId = Get-NetworkID -Ip $serverIP -Mask $subnetMask

Write-Host "Calculated ScopeId (Network ID): $scopeId"
Write-Host "Subnet Mask: $subnetMask"

# --- CONFIGURE STATIC IP ---
Set-NetIPInterface -InterfaceAlias $nicAlias -Dhcp Disabled

# Remove any old IPv4 before adding new
Get-NetIPAddress -InterfaceAlias $nicAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

# Assign static IP
New-NetIPAddress -InterfaceAlias $nicAlias -IPAddress $serverIP -PrefixLength $prefixLength -DefaultGateway $scopeGateway

# Configure DNS on NIC
Set-DnsClientServerAddress -InterfaceAlias $nicAlias -ServerAddresses ($scopeDns.Split(","))

# --- DHCP SCOPE CREATION ---
Add-DhcpServerv4Scope -Name $scopeName -StartRange $scopeStartIp -EndRange $scopeEndIp -SubnetMask $subnetMask -State Active

# DHCP Options
Set-DhcpServerv4OptionValue -ScopeId $scopeId -Router $scopeGateway
Set-DhcpServerv4OptionValue -ScopeId $scopeId -DnsServer ($scopeDns.Split(","))

Write-Host "DHCP server installed and scope created successfully!"