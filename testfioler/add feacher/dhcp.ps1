# Install DHCP role
Install-WindowsFeature -Name DHCP -IncludeManagementTools
Import-Module DhcpServer

# ipv6
# Disable IPv6 on ALL network adapters
Get-NetAdapterBinding -ComponentID ms_tcpip6 | Disable-NetAdapterBinding -ComponentID ms_tcpip6 -Confirm:$false

# === Replicate DHCP Post-Install Wizard ===

# Create DHCP security groups (DHCP Administrators, DHCP Users)
Add-DhcpServerSecurityGroup

# Get server FQDN and IP for authorization
$hostname = (Get-CimInstance Win32_ComputerSystem).DNSHostName
$domain   = (Get-CimInstance Win32_ComputerSystem).Domain
$fqdn     = "$hostname.$domain"

$serverIP = (Get-NetIPAddress -InterfaceAlias "Ethernet 2" |
             Where-Object {$_.AddressFamily -eq "IPv4"}).IPAddress

# Authorize DHCP server in Active Directory (same as GUI wizard)
Add-DhcpServerInDC -DnsName $fqdn -IpAddress $serverIP



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
    param([Parameter(Mandatory)][int]$Prefix)

    if ($Prefix -lt 0 -or $Prefix -gt 32) {
        throw "Prefix length must be between 0 and 32."
    }

    # Build a 32-bit mask with $Prefix leading 1s (network order)
    $mask = 0
    if ($Prefix -gt 0) {
        $mask = [uint32]0xFFFFFFFF -shl (32 - $Prefix)
    }

    # Convert to dotted decimal in network byte order
    $b0 = ($mask -shr 24) -band 0xFF
    $b1 = ($mask -shr 16) -band 0xFF
    $b2 = ($mask -shr 8)  -band 0xFF
    $b3 =  $mask          -band 0xFF
    return "$b0.$b1.$b2.$b3"
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
$subnetMask = "255.255.255.0" # default for /24
if ($prefixLength -ne 24) {
    $subnetMask = Convert-PrefixToMask -Prefix $prefixLength
}
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

Write-Host "DHCP server installed and scope created successfully! going to restart later"

shutdown -r -t 900 -c "Restarting in 15 minutes to finalize DHCP installation." -f