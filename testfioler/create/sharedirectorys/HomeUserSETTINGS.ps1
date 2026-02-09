Import-Module ActiveDirectory

$shareServer = Read-Host "Enter the share server name (without backslashes)"
$shareName   = 'HomeShare$'   # keep in one place

# Get users with properties needed for checks
$users1 = Get-ADUser -Filter * -SearchBase "OU=brukere,OU=users,OU=drageideou,DC=drageide,DC=com" -Properties HomeDirectory,HomeDrive,sAMAccountName,SID
$users2 = Get-ADUser -Filter * -SearchBase "OU=it,OU=users,OU=drageideou,DC=drageide,DC=com"   -Properties HomeDirectory,HomeDrive,sAMAccountName,SID
$allusers = $users1 + $users2

foreach ($user in $allusers) {
    # Extract username and construct the intended home folder path
    $username = $user.SamAccountName
    if ([string]::IsNullOrWhiteSpace($username)) { continue }

    # If the user already has ANY HomeDirectory, skip
    if ($user.HomeDirectory) {
        Write-Output "SKIP: $username already has HomeDirectory ($($user.HomeDirectory))"
        continue
    }

    # test if the users homefolder exists, if not creates it, if it does not exist it will be created
    if (-not (Test-Path -Path "\\$shareServer\$shareName\$username")) {
        New-Item -Path "\\$shareServer\$shareName\$username" -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
        Write-Output "CREATED: Home folder for $username at \\$shareServer\$shareName\$username"
    }
    else {
        Write-Output "EXISTS: Home folder for $username already exists at \\$shareServer\$shareName\$username"
    }

    $homeFolderPath = "\\$shareServer\$shareName\$username"

    # Apply NTFS permissions so only Administrators/SYSTEM and the user have access
    try {
        $folder = Get-Item -Path $homeFolderPath -ErrorAction Stop

        # Build account objects
        $admins  = New-Object System.Security.Principal.NTAccount('BUILTIN','Administrators')
        $system  = New-Object System.Security.Principal.NTAccount('NT AUTHORITY','SYSTEM')

        # Resolve the AD user's NTAccount (domain\user)
        $userNt = if ($user.SID) {
            (New-Object System.Security.Principal.SecurityIdentifier($user.SID)).Translate([System.Security.Principal.NTAccount]).Value
        } else {
            # Fallback: try domain from environment
            "$($env:USERDOMAIN)\$username"
        }

        $userAccount = New-Object System.Security.Principal.NTAccount($userNt)

        # Get and reset ACL
        $acl = $folder.GetAccessControl('Access')
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($rule in $acl.Access) { $acl.RemoveAccessRule($rule) | Out-Null }

        # Administrators + SYSTEM: Full (inherit to all)
        $acl.AddAccessRule( (New-Object System.Security.AccessControl.FileSystemAccessRule(
            $admins,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Allow
        )))
        $acl.AddAccessRule( (New-Object System.Security.AccessControl.FileSystemAccessRule(
            $system,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Allow
        )))

        # User: Full control on their folder and children
        $acl.AddAccessRule( (New-Object System.Security.AccessControl.FileSystemAccessRule(
            $userAccount,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Allow
        )))

        # Apply the ACL
        $folder.SetAccessControl($acl)
        Write-Output "ACL SET: $homeFolderPath -> Administrators + SYSTEM + $userNt"
    }
    catch {
        Write-Warning "Failed to set ACL on $homeFolderPath : $($_.Exception.Message)"
    }

    # Set only AD attributes; do not create folders
    Set-ADUser -Identity $username -HomeDirectory $homeFolderPath -HomeDrive "H:"
    Write-Output "SET : $username -> $homeFolderPath"
}

Write-Output "Completed."
# End of script