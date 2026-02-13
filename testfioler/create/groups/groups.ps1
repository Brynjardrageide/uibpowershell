Import-Module ActiveDirectory
function  New-ADGroupWithParams {
    param (
        [string]$Name,
        [string]$SamAccountName = $($Name -replace '\s+', ''),
        [string]$GroupScope = "Global",
        [string]$GroupCategory = "Security",
        [string]$Path
    )
    new-adgroup `
        -Name $Name `
        -SamAccountName $SamAccountName `
        -GroupScope $GroupScope `
        -GroupCategory $GroupCategory `
        -Path $Path
}

# variabler for gruppeopprettelse
$groupPath = "OU=Groups,OU=drageideou,DC=drageide,DC=com"
$brukere = "brukere"
$it = "ITTeam"


# opprett grupper
New-ADGroupWithParams -Name $brukere -Path $groupPath
New-ADGroupWithParams -Name $it -Path $groupPath

# adding members to groups

# Resolve groups (safer than relying only on names)
$itGroup       = Get-ADGroup -Identity $it -ErrorAction Stop
$brukereGroup  = Get-ADGroup -Identity $brukere -ErrorAction Stop

# Get users from OUs
$itUsers = Get-ADUser -SearchBase "OU=IT,OU=Users,OU=drageideou,DC=drageide,DC=com" -Filter * -ErrorAction Stop
$otherUsers = Get-ADUser -SearchBase "OU=Sales,OU=Users,OU=drageideou,DC=drageide,DC=com" -Filter * -ErrorAction Stop

# Helper: add only users that aren't already members
function Add-MembersIfMissing {
    param(
        [Parameter(Mandatory)][Microsoft.ActiveDirectory.Management.ADGroup]$Group,
        [Parameter(Mandatory)][Microsoft.ActiveDirectory.Management.ADAccount[]]$Members
    )

    if (-not $Members -or $Members.Count -eq 0) {
        Write-Host "No candidates to add to group '$($Group.Name)'."
        return
    }

    $existing = Get-ADGroupMember -Identity $Group -Recursive -ErrorAction SilentlyContinue
    $existingDN = @()
    if ($existing) { $existingDN = $existing.DistinguishedName }

    $toAdd = $Members | Where-Object { $existingDN -notcontains $_.DistinguishedName }

    if ($toAdd.Count -gt 0) {
        Add-ADGroupMember -Identity $Group -Members $toAdd -ErrorAction Stop
        Write-Host "Added $($toAdd.Count) member(s) to '$($Group.Name)'."
    }
    else {
        Write-Host "All candidates are already members of '$($Group.Name)'."
    }
}

# Add users to groups
Add-MembersIfMissing -Group $itGroup      -Members $itUsers
Add-MembersIfMissing -Group $brukereGroup -Members $otherUsers

# (Optional) If you also want the IT group nested into 'brukere', uncomment:
# Add-ADGroupMember -Identity $brukereGroup -Members $itGroup -ErrorAction SilentlyContinue