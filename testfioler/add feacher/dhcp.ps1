Install-WindowsFeature -Name DHCP -IncludeManagementTools
Import-Module DHCPServer

# Configure a static IP address for the DHCP server
$eth2ip = Read-Host "read the ip adress you want to set for the dhcp server"
scopeGateway = Read-Host "Enter the default gateway for the DHCP scope and dhcp server (e.g.,"
$scopeDnsServers = Read-Host "Enter the DNS server IP addresses for the DHCP scope and dhcp server, separated by commas (e.g.,"

Set-NetIPInterface -InterfaceAlias "Ethernet 2" -Dhcp Disabled
New-NetIPAddress -InterfaceAlias "Ethernet 2" -IPAddress $eth2ip -PrefixLength 24 -DefaultGateway "192.168.1.1"
Set-DnsClientServerAddress -InterfaceAlias "Ethernet 2" -ServerAddresses ("127.0.0.1",$scopeDnsServers.Split(","))


# Authorize the DHCP server in Active Directory
$dhcpServerIp = (Get-NetIPAddress -InterfaceAlias "Ethernet" | Where-Object {$_.AddressFamily -eq "IPv4"}).IPAddress
Add-DhcpServerInDC -DnsName $dhcpServerIp -IpAddress $dhcpServerIp
# Configure a DHCP scope
$scopeName = "Office Network"
$scopeStartIp = Read-Host "Enter the start IP address for the DHCP scope (e.g.,"
$scopeEndIp = Read-Host "Enter the end IP address for the DHCP scope (e.g.,"
Add-DhcpServerv4Scope -Name $scopeName -StartRange $scopeStartIp -EndRange $scopeEndIp -SubnetMask $scopeSubnetMask -State Active
Set-DhcpServerv4OptionValue -ScopeId $scopeStartIp -Router $scopeGateway -DnsServer $scopeDnsServers
Write-Host "DHCP server configured successfully."
# End of script