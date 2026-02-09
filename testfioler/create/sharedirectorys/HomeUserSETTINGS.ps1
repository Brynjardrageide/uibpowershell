Import-Module ActiveDirectory

# Config
$shareServer = Read-Host "Enter the share server name (FQDN or NetBIOS, no backslashes)"
$shareName   = 'HomeShare$'
$useRemoting = $true  # $true = run folder creation on $shareServer via Invoke-Command
# If using remoting and you need different creds:
# $cred = Get-Credential

$rootUNC = "\\$shareServer\$shareName"
if (-not (Test-Path $rootUNC)) {
    Write-Error "Share not reachable: $rootUNC. Ensure the share exists and you have network access."
    return
}

# Enumerate users (fix SearchBase)
$users1 = Get-ADUser -Filter * -SearchBase "OU=brukere,OU=users,OU=drageideou,DC=drageide,DC=com" -Properties HomeDirectory,HomeDrive,sAMAccountName
$users2 = Get-ADUser -Filter * -SearchBase "OU=it,OU=users,OU=drageideou,DC=drageide,DC=com"   -Properties HomeDirectory,HomeDrive,sAMAccountName
$allusers = $users1 + $users2

# Scriptblock run on file server to create folder & set ACLs
$createAndAclBlock = {
    param($username, $rootPath)

    $userFolder = Join-Path $rootPath $username
    if (-not (Test-Path $userFolder)) {
        New-Item -Path $userFolder -ItemType Directory -Force | Out-Null
    }

    # Apply deterministic ACLs:
    $acl = Get-Acl -Path $userFolder

    # Remove explicit Authenticated Users ACE on this folder only (optional)
    $acl.Access | Where-Object { $_.IdentityReference -like '*Authenticated Users*' -and -not $_.IsInherited } | ForEach-Object { $acl.RemoveAccessRule($_) }

    # Administrators and SYSTEM FullControl (inherited)
    $admins = 'BUILTIN\Administrators'
    $system = 'NT AUTHORITY\SYSTEM'
    $ruleAdmins = New-Object System.Security.AccessControl.FileSystemAccessRule($admins,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
    $ruleSystem = New-Object System.Security.AccessControl.FileSystemAccessRule($system,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
    $acl.AddAccessRule($ruleAdmins)
    $acl.AddAccessRule($ruleSystem)

    # Give the user FullControl on their own folder (domain\samaccountname)
    # If running on the file server in domain, we can use Domain\SAM
    $domain = (Get-WmiObject Win32_ComputerSystem).Domain
    $userAccount = \"$domain\$username\"
    $ruleUser = New-Object System.Security.AccessControl.FileSystemAccessRule($userAccount,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
    $acl.AddAccessRule($ruleUser)

    Set-Acl -Path $userFolder -AclObject $acl

    return $userFolder
}

foreach ($user in $allusers) {
    $username = $user.SamAccountName
    if ([string]::IsNullOrWhiteSpace($username)) { continue }

    if ($user.HomeDirectory) {
        Write-Output \"SKIP: $username already has HomeDirectory ($($user.HomeDirectory))\"
        continue
    }

    $homeUNC = Join-Path $rootUNC $username

    # Create folder and ACLs either locally over UNC or by invoking on the file server
    if ($useRemoting) {
        # Run creation on the file server (use -Credential if needed)
        try {
            $createdPath = Invoke-Command -ComputerName $shareServer -ScriptBlock $createAndAclBlock -ArgumentList $username,$rootUNC -ErrorAction Stop
            Write-Output \"Created (remote) : $createdPath\"
        } catch {
            Write-Error \"Failed creating folder on $shareServer for $username: $_\"
            continue
        }
    } else {
        # Attempt to create over UNC from this host (requires that the script account has rights)
        try {
            if (-not (Test-Path $homeUNC)) { New-Item -Path $homeUNC -ItemType Directory -Force | Out-Null }
            # Apply ACLs locally (when creating over UNC, Set-Acl works if account has permissions)
            # Reuse createAndAclBlock logic by calling it locally via & (invoke) after importing the block (or copy the code)
            & $createAndAclBlock $username $rootUNC | Out-Null
            Write-Output \"Created (unc) : $homeUNC\"
        } catch {
            Write-Error \"Failed creating folder via UNC for $username: $_\"
            continue
        }
    }

    # Finally set AD attributes
    try {
        Set-ADUser -Identity $username -HomeDirectory $homeUNC -HomeDrive 'H:'
        Write-Output \"SET AD : $username -> $homeUNC\"
    } catch {
        Write-Error \"Failed to set AD HomeDirectory for $username : $_\"
    }
}

Write-Output "Completed."
# End of script