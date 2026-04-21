# importererbrukere fra CSV-fil og legger dem til i Active Directory
# csv-filen skal ha kolonnene: eployeeid, FirstName, LastName

# MARK: variabler
$domain = "drageide.com" # Domain name for email and AD user principal name
$domainshort = "drageide" # Short domain name for SAM account name
$defaultOU = "OU=users,OU=drageideou,DC=$domainshort,DC=com"  # Default OU if not specified in CSV
$filename = "brukere.csv" # CSV file name


# MARK: CSV ARBEID
function Get-employeeFromCsv {
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
    phone="phone"
    ou="ou"
}
# Get-eployeeFromCsv -filePath ".\testfioler\create\users.csv" -Delimiter "," -SyncfieldMap $SyncfieldMap
$userinfo = Get-employeeFromCsv -filePath ".\bulkusers_secure\$filename" -Delimiter "," -SyncfieldMap $SyncfieldMap

# MARK: laging av brukere
foreach ($user in $userinfo) {
    if (Get-ADUser -LDAPFilter "(employeeID=$($user.EmployeeID))" -ErrorAction SilentlyContinue) {
        Write-Host "User with EmployeeID $($user.EmployeeID) already exists. Skipping..." -ForegroundColor Yellow
        continue
    }else {
        Write-Host "Creating user: $($user.GivenName) $($user.Surname)" -ForegroundColor Green
        # Default OU
        if ([string]::IsNullOrWhiteSpace($user.ou)) {
            $user.ou = "brukere"
        }
      
        $OU = "OU=$($user.ou),$defaultOU"

        $Email = "$($user.Givenname).$($user.Surname)@$Domain"
        New-ADUser `
            -EmployeeID $user.EmployeeID `
            -UserPrincipalName "$($user.GivenName).$($user.Surname)@$Domain" `
            -GivenName $user.GivenName `
            -Surname $user.Surname `
            -Name "$($user.GivenName) $($user.Surname)" `
            -SamAccountName "$($user.GivenName.Substring(0,2))$($user.Surname.Substring(0,3))" `
            -Path $OU `
            -EmailAddress $Email `
            -AccountPassword (ConvertTo-SecureString "Passord01!" -AsPlainText -Force) `
            -Enabled $true `
            -PasswordNeverExpires $false `
            -HomePhone $user.phone `
            -ChangePasswordAtLogon $false
    }
}