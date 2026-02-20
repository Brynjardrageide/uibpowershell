<#
Script: Create-HomeShareRoot.ps1
Purpose: Create the root folder and share for home directories with correct permissions.
Run on: The FILE SERVER (as Administrator)
#>

param(
    [string]$FolderPath = 'C:\Shares\FELLES',
    [string]$ShareName  = 'felles$',
    [switch]$HideFolder
)

# children folders for department shares will be created under this root, e.g. C:\Shares\FELLES\IT, C:\Shares\FELLES\SALES, etc.
<#
Note: You can create the root share with more open permissions 
(e.g. allow Authenticated Users to create subfolders) and then create 
department subfolders with more restrictive permissions 
(e.g. only allow the specific department group to access their folder). This way you can 
have a single share for all departments but still maintain security boundaries at the folder level.
#>

$children =@(
    "IT",
    "SAlg",
    "adm"
)


# Accounts
$admins  = New-Object System.Security.Principal.NTAccount('BUILTIN','Administrators')
$system  = New-Object System.Security.Principal.NTAccount('NT AUTHORITY','SYSTEM')
$auth    = New-Object System.Security.Principal.NTAccount('NT AUTHORITY','Authenticated Users')
$itTeam   = New-Object System.Security.Principal.NTAccount('DRAGEIDE','ITTeam')
$salesTeam   = New-Object System.Security.Principal.NTAccount('DRAGEIDE','salg')
$admteam   = New-Object System.Security.Principal.NTAccount('DRAGEIDE','adm')


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


$root.SetAccessControl($acl)

Write-Output "Home share '$ShareName' created and NTFS permissions applied."


# this is for groups spesific permissions on department subfolders, e.g. ITTeam gets FullControl on IT folder, etc.
# reuseble variables for rights and inheritance flags
$rights =
    [System.Security.AccessControl.FileSystemRights]::Read `
    -bor [System.Security.Security.AccessControl.FileSystemRights]::ReadPermissions `
    -bor [System.Security.AccessControl.FileSystemRights]::WriteAttributes `
    -bor [System.Security.AccessControl.FileSystemRights]::Delete

# dette er for denne mappen og alle undermapper og filer
$inherit = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit `
         -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit


for ($i = 0; $i -lt $children.Count; $i++) {
    $childPath = Join-Path $FolderPath $children[$i]
    New-Item -Path $childPath -ItemType Directory -Force | Out-Null
    Write-Output "Created child folder: $childPath"
}
$rootitem = Get-Item $"FolderPath\$($children[0])"
$acl  = $rootitem.GetAccessControl('Access')
$acl.AddAccessRule( (New-Object System.Security.AccessControl.FileSystemAccessRule(
    $itTeam,
    $rights,
    $inherit,
    ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
    [System.Security.AccessControl.PropagationFlags]::None,
    [System.Security.AccessControl.AccessControlType]::Allow
)))
$rootitem.SetAccessControl($acl)
$rootitem = Get-Item $"FolderPath\$($children[1])"
$acl  = $rootitem.GetAccessControl('Access')
$acl.AddAccessRule( (New-Object System.Security.AccessControl.FileSystemAccessRule(
    $salesTeam,
    $rights,
    $inherit,    
    ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
    [System.Security.AccessControl.PropagationFlags]::None,
    [System.Security.AccessControl.AccessControlType]::Allow
)))
$rootitem.SetAccessControl($acl)
$rootitem = Get-Item $"FolderPath\$($children[2])"
$acl  = $rootitem.GetAccessControl('Access')
$acl.AddAccessRule( (New-Object System.Security.AccessControl.FileSystemAccessRule(
    $admteam,
    $rights,
    $inherit,
    ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
    [System.Security.AccessControl.PropagationFlags]::None,
    [System.Security.AccessControl.AccessControlType]::Allow
)))
$rootitem.SetAccessControl($acl)
write-Output "Department subfolders created and permissions applied."