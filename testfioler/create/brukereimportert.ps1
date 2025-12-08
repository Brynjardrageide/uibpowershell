# importererbrukere fra CSV-fil og legger dem til i Active Directory
# csv-filen skal ha kolonnene: eployeeid, FirstName, LastName
function Get-eployeeFromCsv {
    [cmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$filePath,
        [Parameter(Mandatory)]
        [string]$Delimiter,
        [Parameter(Mandatory)]
        [hashtable]$SyncfieldMap
    )
    
    try {
        $SyncProperties=$SyncfieldMap.GetEnumerator()
        $properties=foreach($property in $SyncProperties){
            @{Name=$property.Value;Expression=[scriptblock]::Create("`$_.$($property.Key)")}
        }

        Import-Csv -Path $filePath -Delimiter $Delimiter | Select-Object -Property $properties
    }
    catch {
        <#Do this if a terminating exception happens#>
        write-error "An error occurred: $_.Exception.Message"
    }

}
$SyncfieldMap = @{
    EmployeeID="EmployeeID"
    FirstName="GivenName"
    LastName="Surname"
}
# Get-eployeeFromCsv -filePath ".\testfioler\create\users.csv" -Delimiter "," -SyncfieldMap $SyncfieldMap
$userinfo = Get-eployeeFromCsv -filePath "C:\Users\Administrator\Documents\csv\brukere.csv" -Delimiter "," -SyncfieldMap $SyncfieldMap
foreach ($user in $userinfo) {
    $OU = "OU=brukere,OU=users,OU=drageideou's,DC=drageide,DC=com"
    $Domain = "drageide.com"
    $Email = "$($user.Givenname).$($user.Surname)@$Domain"
    New-ADUser `
        -EmployeeID $user.EmployeeID `
        -UserPrincipalName "$($user.GivenName).$($user.Surname)@$Domain" `
        -GivenName $user.GivenName `
        -Surname $user.Surname `
        -Name "$($user.GivenName) $($user.Surname)" `
        -Path $OU `
        -EmailAddress $Email `
        -AccountPassword (ConvertTo-SecureString "Passord01!" -AsPlainText -Force) `
        -Enabled $true `
        -PasswordNeverExpires $false `
        -ChangePasswordAtLogon $false
}