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

# ading members to groups
$itusers  = get-aduser -SearchBase "ou=it,ou=users,ou=drageideou,dc=drageide,dc=com"`
    -Filter * | Add-ADGroupMember -Identity $it



$otherusers = get-aduser -SearchBase "ou=sales,ou=users,ou=drageideou,dc=drageide,dc=com"`
    -Filter * | Add-ADGroupMember -Identity $brukere

Add-ADGroupMember -Identity $itusers -Members $it
Add-ADGroupMember -Identity $otherusers -Members $brukere