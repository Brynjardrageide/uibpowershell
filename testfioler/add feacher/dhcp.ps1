# -----------------------------
# Install DHCP Role
# -----------------------------
Install-WindowsFeature DHCP -IncludeManagementTools
Import-Module DhcpServer

# -----------------------------
# MARK: VARIABLES
# -----------------------------
$nicAlias     = "Ethernet 2"

$serverIP     = "192.168.5.30"
$prefixLength = 24
$gateway      = "192.168.5.1"
$dnsList      = @("192.168.1.30","8.8.8.8")

$scopeStart   = "192.168.5.100"
$scopeEnd     = "192.168.5.200"
$scopeName    = "test"
$scopeId      = "192.168.5.0"
$subnetMask   = "255.255.255.0"

# -----------------------------
# MARK: Configure Static IP on Ethernet 2
# -----------------------------

# Disable IPv6 on ALL adapters
Get-NetAdapterBinding -ComponentID ms_tcpip6 |
    Disable-NetAdapterBinding -ComponentID ms_tcpip6 -Confirm:$false
    
Get-NetIPAddress -InterfaceAlias $nicAlias -AddressFamily IPv4 |
    Remove-NetIPAddress -Confirm:$false

New-NetIPAddress `
    -InterfaceAlias $nicAlias `
    -IPAddress $serverIP `
    -PrefixLength $prefixLength `
    -DefaultGateway $gateway

Set-DnsClientServerAddress `
    -InterfaceAlias $nicAlias `
    -ServerAddresses $dnsList

# -----------------------------
# Authorize DHCP in Active Directory
# (only required if domain joined)
# -----------------------------
$serverFQDN = "$env:COMPUTERNAME.$(Get-ADDomain).DNSRoot"

Add-DhcpServerInDC `
    -DnsName $serverFQDN `
    -IpAddress $serverIP

# -----------------------------
# Create and Activate DHCP Scope
# -----------------------------
Add-DhcpServerv4Scope `
    -Name $scopeName `
    -StartRange $scopeStart `
    -EndRange $scopeEnd `
    -SubnetMask $subnetMask `
    -State Active

# -----------------------------
# DHCP Options
# -----------------------------
Set-DhcpServerv4OptionValue -ScopeId $scopeId -Router $gateway
Set-DhcpServerv4OptionValue -ScopeId $scopeId -DnsServer $dnsList

Write-Host "✅ Ethernet 2 configured with IP $serverIP"
Write-Host "✅ DHCP installed, authorized, and scope active"