Import-Module ActiveDirectory -ErrorAction Stop

function EnsureOU {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$ParentDN
    )

    # Verify parent DN exists before doing any AD queries/creates
    # Retry a few times because the parent may have just been created earlier in this script
    $parentObj = $null
    for ($p = 0; $p -lt 6; $p++) {
        try {
            $parentObj = Get-ADObject -Identity $ParentDN -ErrorAction Stop
            break
        }
        catch {
            Start-Sleep -Seconds 1
        }
    }

    if (-not $parentObj) {
        Write-Error "Parent DN not found or not reachable after retries: $ParentDN. Cannot create OU '$Name'."
        return $null
    }
    else {
        Write-Verbose "Parent found: $($parentObj.DistinguishedName)"
    }

    # Exact match search using LDAP filter (more reliable)
    $ldapFilter = "(ou=$Name)"

    $existing = Get-ADOrganizationalUnit `
        -LDAPFilter $ldapFilter `
        -SearchBase $ParentDN `
        -ErrorAction SilentlyContinue

    start-sleep -seconds 0.5
    if ($existing) {
        Write-Host "OU already exists: $($existing.DistinguishedName)"
        return $existing.DistinguishedName
    }

    try {
        $newOU = New-ADOrganizationalUnit `
            -Name $Name `
            -Path $ParentDN `
            -ProtectedFromAccidentalDeletion $false `
            -ErrorAction Stop

        # Wait and verify the OU exists using the created object's DN (retries to account for AD latency)
        $found = $null
        $newDN = $newOU.DistinguishedName
        for ($i = 0; $i -lt 5; $i++) {
            Start-Sleep -Seconds 1
            $found = Get-ADOrganizationalUnit -Identity $newDN -ErrorAction SilentlyContinue
            if ($found) { break }
        }

        if ($found) {
            Write-Host "Created OU: $($found.DistinguishedName)"
            return $found.DistinguishedName
        }
        else {
            Write-Error "OU '$Name' was created but could not be verified at DN '$newDN'."
            return $null
        }
    }
    catch {
        Write-Error "Failed to create OU '$Name' under '$ParentDN': $_"
        return $null
    }
}

# Domain DN and OU names
$domainDN = "DC=drageide,DC=com"
$rootOUName = "drageideou"
$childrenrootOUs = @("computers","groups")
$usersOUName = "users"
$childOUs = @("brukere","it")
$computerchildOUs = @("klienter","servere")

# Ensure root OU (OU=drageideou,DC=drageide,DC=com)
$rootDN = EnsureOU -Name $rootOUName -ParentDN $domainDN
if (-not $rootDN) { exit 1 }

# Ensure users OU under the root (OU=users,OU=drageideou,DC=drageide,DC=com)
$usersDN = EnsureOU -Name $usersOUName -ParentDN $rootDN
if (-not $usersDN) { exit 1 }

# Ensure the requested child OUs under OU=drageideou's,...
foreach ($child in $childrenrootOUs) {
    EnsureOU -Name $child -ParentDN $rootDN | Out-Null
}

# Ensure the requested child OUs under OU=users,...
foreach ($child in $childOUs) {
    EnsureOU -Name $child -ParentDN $usersDN | Out-Null
}

foreach ($child in $computerchildOUs) {
    EnsureOU -Name $child -ParentDN "ou=computers,$rootDN" | Out-Null
}
 
Write-Host "OU creation complete."