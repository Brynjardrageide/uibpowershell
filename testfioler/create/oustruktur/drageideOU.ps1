Import-Module ActiveDirectory -ErrorAction Stop

function EnsureOU {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$ParentDN
    )

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

        Write-Host "Created OU: $($newOU.DistinguishedName)"

        # Fix: wait for AD replication to settle
        Start-Sleep -Seconds 1

        return $newOU.DistinguishedName
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
 
Write-Host "OU creation complete."