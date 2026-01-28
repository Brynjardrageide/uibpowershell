<#
Script: Create-HomeShareRoot.ps1
Purpose: Create the root folder and share for home directories with correct permissions.
Run on: The FILE SERVER (as Administrator)
#>

param(
    [string]$FolderPath = 'C:\Shares\HomeShare',
    [string]$ShareName  = 'HomeShare$',
    [switch]$HideFolder
)

# Accounts
$admins  = New-Object System.Security.Principal.NTAccount('BUILTIN','Administrators')
$system  = New-Object System.Security.Principal.NTAccount('NT AUTHORITY','SYSTEM')
$auth    = New-Object System.Security.Principal.NTAccount('NT AUTHORITY','Authenticated Users')
$creator = New-Object System.Security.Principal.NTAccount('CREATOR OWNER')

# Ensure admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Run as Administrator."
    exit 1
}

# Create folder
New-Item -Path $FolderPath -ItemType Directory -Force | Out-Null
if ($HideFolder) {
    $item = Get-Item $FolderPath
    $item.Attributes = $item.Attributes -bor [IO.FileAttributes]::Hidden
}

# Create / fix share (Change for Authenticated Users)
if (-not (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue)) {
    New-SmbShare `
        -Name $ShareName `
        -Path $FolderPath `
        -FullAccess "BUILTIN\Administrators","NT AUTHORITY\SYSTEM" `
        -ChangeAccess "NT AUTHORITY\Authenticated Users" `
        -FolderEnumerationMode AccessBased `
        -CachingMode None `
        -Description "Home Share Root" | Out-Null
} else {
    Set-SmbShare -Name $ShareName -FolderEnumerationMode AccessBased -CachingMode None
    Revoke-SmbShareAccess -Name $ShareName -AccountName Everyone -Force -ErrorAction SilentlyContinue
    Grant-SmbShareAccess  -Name $ShareName -AccountName "BUILTIN\Administrators" -AccessRight Full   -Force
    Grant-SmbShareAccess  -Name $ShareName -AccountName "NT AUTHORITY\SYSTEM"   -AccessRight Full   -Force
    Grant-SmbShareAccess  -Name $ShareName -AccountName "NT AUTHORITY\Authenticated Users" -AccessRight Change -Force
}

# NTFS ACLs (root)
$root = Get-Item -Path $FolderPath
$acl  = $root.GetAccessControl('Access')

# Disable inheritance and remove existing explicit ACEs to start clean
$acl.SetAccessRuleProtection($true, $false)
foreach ($rule in $acl.Access) { $acl.RemoveAccessRule($rule) | Out-Null }

# Admins + SYSTEM: Full (inherit to all)
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

# Authenticated Users: allow creating subfolders at root (THIS FOLDER ONLY)
$rightsAuth =
      [System.Security.AccessControl.FileSystemRights]::CreateDirectories `
    -bor [System.Security.AccessControl.FileSystemRights]::AppendData `
    -bor [System.Security.AccessControl.FileSystemRights]::ListDirectory `
    -bor [System.Security.AccessControl.FileSystemRights]::ReadAttributes `
    -bor [System.Security.AccessControl.FileSystemRights]::ReadExtendedAttributes `
    -bor [System.Security.AccessControl.FileSystemRights]::Traverse `
    -bor [System.Security.AccessControl.FileSystemRights]::ReadPermissions

$acl.AddAccessRule( (New-Object System.Security.AccessControl.FileSystemAccessRule(
    $auth,
    $rightsAuth,
    [System.Security.AccessControl.InheritanceFlags]::None,
    [System.Security.AccessControl.PropagationFlags]::None,
    [System.Security.AccessControl.AccessControlType]::Allow
)))

# CREATOR OWNER: Full control on subfolders/files only
$acl.AddAccessRule( (New-Object System.Security.AccessControl.FileSystemAccessRule(
    $creator,
    [System.Security.AccessControl.FileSystemRights]::FullControl,
    ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
    [System.Security.AccessControl.PropagationFlags]::InheritOnly,
    [System.Security.AccessControl.AccessControlType]::Allow
)))

$root.SetAccessControl($acl)

Write-Output "Home share '$ShareName' created and NTFS permissions applied."