Import-Module ActiveDirectory

$shareServer = Read-Host "Enter the share server name (without backslashes)"
$shareName   = 'HomeShare$'   # keep in one place

# Get users with properties needed for checks
$users1 = Get-ADUser -Filter * -SearchBase "OU=brukere,OU=users,OU=drageideou's,DC=drageide,DC=com" -Properties HomeDirectory,HomeDrive,sAMAccountName
$users2 = Get-ADUser -Filter * -SearchBase "OU=admins,OU=users,OU=drageideou's,DC=drageide,DC=com"   -Properties HomeDirectory,HomeDrive,sAMAccountName
$allusers = $users1 + $users2

foreach ($user in $allusers) {
    $username = $user.SamAccountName
    if ([string]::IsNullOrWhiteSpace($username)) { continue }

    # If the user already has ANY HomeDirectory, skip
    if ($user.HomeDirectory) {
        Write-Output "SKIP: $username already has HomeDirectory ($($user.HomeDirectory))"
        continue
    }

    $homeFolderPath = "\\$shareServer\$shareName\%username%"

    # Set only AD attributes; do not create folders
    Set-ADUser -Identity $username -HomeDirectory $homeFolderPath -HomeDrive "H:"
    Write-Output "SET : $username -> $homeFolderPath"
}

Write-Output "Completed."
# End of script