# when i ad adds running my autodcmaster it adds dns but not all needed for reverce lookup zone
Import-Module DnsServer -ErrorAction Stop
$zoneName = "1.168.192.in-addr.arpa"
$zoneExists = Get-DnsServerZone -Name $zoneName -ErrorAction SilentlyContinue
$eth1 = Get-NetAdapter | Where-Object { $_.Name -eq "Ethernet" } | Get-NetIPAddress | Where-Object { $_.AddressFamily -eq "IPv4" }
$gatewayIP = $eth1.IPAddress
$eth2 = Get-NetAdapter | Where-Object { $_.Name -eq "Ethernet 2" } | Get-NetIPAddress | Where-Object { $_.AddressFamily -eq "IPv4" }
$dnsServerIP = $eth2.IPAddress
#lol
$dnsServerIP

if (-not $zoneExists) {
    Write-Output "Creating reverse lookup zone: $zoneName"
    Add-DnsServerPrimaryZone -NetworkId "192.168.1.0/24" -ZoneFile "$zoneName.dns" -DynamicUpdate Secure
    Write-Output "Reverse lookup zone '$zoneName' created successfully."
} else {
    Write-Output "Reverse lookup zone '$zoneName' already exists. No action taken."
}
# Add necessary PTR records (example for gateway and DNS server)
$ptrRecords = @(
    @{ IPAddress = "$gatewayIP"; HostName = "dmmaterdc1" }
    @{ IPAddress = "192.168.1.31"; HostName = "printserver" }
)
foreach ($record in $ptrRecords) {
    # derive the PTR name (last octet) from the IPv4 address
    $ptrName = ($record.IPAddress -split '\.')[-1]
    # ensure we have a FQDN for the PTR target
    $fqdn = if ($record.HostName -match '\.') { $record.HostName } else { "$($record.HostName).drageide.com" }

    # check for an existing PTR by the last octet (reverse zone stores records by octet)
    $existingPTR = Get-DnsServerResourceRecord -ZoneName $zoneName -RRType PTR -Name $ptrName -ErrorAction SilentlyContinue

    if (-not $existingPTR) {
        Write-Output "Adding PTR record for $fqdn with IP $($record.IPAddress) (name: $ptrName)"
        Add-DnsServerResourceRecordPtr -ZoneName $zoneName -Name $ptrName -PtrDomainName $fqdn -TimeToLive (New-TimeSpan -Hours 1)
        Write-Output "PTR record for $fqdn added successfully."
    }
    else {
        $currentPtrTarget = $existingPTR.RecordData[0].PtrDomainName.TrimEnd('.')
        if ($currentPtrTarget -ne $fqdn) {
            Write-Output "PTR for $ptrName exists but points to $currentPtrTarget. Updating to $fqdn."
            # remove the old PTR and add the correct one
            Remove-DnsServerResourceRecord -ZoneName $zoneName -RRType PTR -Name $ptrName -Force -ErrorAction Stop
            Add-DnsServerResourceRecordPtr -ZoneName $zoneName -Name $ptrName -PtrDomainName $fqdn -TimeToLive (New-TimeSpan -Hours 1)
            Write-Output "PTR record for $fqdn updated successfully."
        }
        else {
            Write-Output "PTR record for $fqdn already exists and is correct. No action taken."
        }
    }
}

Write-Output "DNS reverse lookup zone configuration completed."