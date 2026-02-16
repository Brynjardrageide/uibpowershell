Import-Module ActiveDirectory

$user = @{
    EmployeeID = Read-Host "Enter EmployeeID"
    GivenName = Read-Host "Enter GivenName"
    Surname = Read-Host "Enter Surname"
    ou = Read-Host "Enter OU (leave blank for default 'brukere')"
}
if ($user.ou -eq "" -or $user.ou -eq $null) {
    <# Action to perform if the condition is true #>
    $user.ou = "brukere"
}

$OU = "ou=$($user.ou),OU=users,OU=drageideou,DC=drageide,DC=com"
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