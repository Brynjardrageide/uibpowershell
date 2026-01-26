
<#
Script: foldersHomeSHARE.ps1
Purpose: Create home folder share root with proper NTFS + SMB permissions.
Run as Administrator.
#>

param(
    [string]$FolderPath = 'C:\Shares\HomeShare',
    [string]$ShareName  = 'HomeShare$',
    [string]$domain     = 'DRAGEIDE'
)

# Account objects
$admins  = New-Object System.Security.Principal.NTAccount('Administrators')
$system  = New-Object System.Security.Principal.NTAccount('SYSTEM')
$auth    = New-Object System.Security.Principal.NTAccount('Authenticated Users')
$creator = New-Object System.Security.Principal.NTAccount('CREATOR OWNER')

# Inheritance flags
$CI = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit
$OI = [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
$NoneInherit = [System.Security.AccessControl.InheritanceFlags]::None

$InheritOnly = [System.Security.AccessControl.PropagationFlags]::InheritOnly
$NoneProp    = [System.Security.AccessControl.PropagationFlags]::None

# Admin check
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator."
    exit 1
}

# Create folder
New-Item -Path $FolderPath -ItemType Directory -Force | Out-Null

# Hide folder (optional)
(Get-Item $FolderPath).Attributes = (Get-Item $FolderPath).Attributes -bor 'Hidden'

# SMB Share
New-SmbShare `
    -Name $ShareName `
    -Path $FolderPath `
    -FullAccess "$domain\Administrators","SYSTEM" `
    -ReadAccess "Authenticated Users" `
    -Description "Home Share Root" `
    -ErrorAction Stop

# Remove Everyone
Remove-SmbShareAccess -Name $ShareName -AccountName "Everyone" -Force -ErrorAction SilentlyContinue

Write-Output "SMB Share '$ShareName' created."

# NTFS Permissions
$root = Get-Item -Path $FolderPath
$acl = $root.GetAccessControl('Access')

# Disable inheritance
$acl.SetAccessRuleProtection($true, $false)

# Add Administrators + SYSTEM
$acl.AddAccessRule( (New-Object System.Security.AccessControl.FileSystemAccessRule(
    $admins, "FullControl", $CI -bor $OI, $NoneProp, "Allow"
)))

$acl.AddAccessRule( (New-Object System.Security.AccessControl.FileSystemAccessRule(
    $system, "FullControl", $CI -bor $OI, $NoneProp, "Allow"
)))

# Authenticated Users – Create Folders Only
$rightsAuth = [System.Security.AccessControl.FileSystemRights]::CreateDirectories `
             -bor [System.Security.AccessControl.FileSystemRights]::Traverse `
             -bor [System.Security.AccessControl.FileSystemRights]::ReadPermissions

$acl.AddAccessRule( (New-Object System.Security.AccessControl.FileSystemAccessRule(
    $auth, $rightsAuth, $NoneInherit, $NoneProp, "Allow"
)))

# CREATOR OWNER – Full Control (inherit to new folders only)
$acl.AddAccessRule( (New-Object System.Security.AccessControl.FileSystemAccessRule(
    $creator, "FullControl", $CI -bor $OI, $InheritOnly, "Allow"
)))

# Apply NTFS ACLs
$root.SetAccessControl($acl)

Write-Output "NTFS permissions applied successfully."
Write-Output "Home folder share root setup completed."