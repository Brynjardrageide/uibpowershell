Import-Module ActiveDirectory

$user = @{
    EmployeeID = Read-Host "Enter EmployeeID"
    GivenName = Read-Host "Enter GivenName"
    Surname = Read-Host "Enter Surname"
    ou = Read-Host "Enter OU (leave blank for default 'brukere')"
}
if ($user.ou -eq "" -or $null -eq $user.ou) {
    <# Action to perform if the condition is true #>
    $user.ou = "brukere"
}

$OU = "ou=$($user.ou),OU=users,OU=drageideou,DC=drageide,DC=com"
# test in if the OU exists before trying to create the user and if the employeeid already exists in AD employee id should be unique and not already exist in AD
if (Get-ADUser -Filter "EmployeeID -eq '$($user.EmployeeID)'" -ErrorAction SilentlyContinue) {
    Write-Host "A user with EmployeeID '$($user.EmployeeID)' already exists. Please use a unique EmployeeID." -ForegroundColor Red
    exit
}
if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$OU'" -ErrorAction SilentlyContinue)) {
    Write-Host "OU '$OU' does not exist. Please create the OU before adding users." -ForegroundColor Red
    exit
}



$Domain = "drageide.com"
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
    -ChangePasswordAtLogon $false