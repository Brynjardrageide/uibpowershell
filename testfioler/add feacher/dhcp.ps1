Install-WindowsFeature -Name DHCP -IncludeManagementTools
Import-Module DHCPServer

# Authorize the DHCP server in Active Directory
$dhcpServerIp = (Get-NetIPAddress -InterfaceAlias "Ethernet" | Where-Object {$_.AddressFamily -eq "IPv4"}).IPAddress
Add-DhcpServerInDC -DnsName $dhcpServerIp -IpAddress $dhcpServerIp
# Configure a DHCP scope
$scopeName = "Office Network"
$scopeStartIp = Read-Host "Enter the start IP address for the DHCP scope (e.g.,"
$scopeEndIp = Read-Host "Enter the end IP address for the DHCP scope (e.g.,"
$scopeSubnetMask = Read-Host "Enter the subnet mask for the DHCP scope (e.g.,"
$scopeGateway = Read-Host "Enter the default gateway for the DHCP scope (e.g.,"
$scopeDnsServers = Read-Host "Enter the DNS server IP addresses for the DHCP scope, separated by commas (e.g.,"
Add-DhcpServerv4Scope -Name $scopeName -StartRange $scopeStartIp -EndRange $scopeEndIp -SubnetMask $scopeSubnetMask -State Active
Set-DhcpServerv4OptionValue -ScopeId $scopeStartIp -Router $scopeGateway -DnsServer $scopeDnsServers
Write-Host "DHCP server configured successfully."
# End of script