<#
Script: Create-DepartmentShare.ps1
Purpose: Create the root folder and share for department directories with correct permissions.
Run on: The FILE SERVER (as Administrator)
#>

param(
    [string]$FolderPath = 'C:\Shares\FELLES',
    [string]$ShareName  = 'felles$',
    [switch]$HideFolder
)

# Department folder names (change as needed)
$children = @(
    'IT',
    'Salg',   
    'adm'
)

# Accounts
$admins     = New-Object System.Security.Principal.NTAccount('BUILTIN','Administrators')
$system     = New-Object System.Security.Principal.NTAccount('NT AUTHORITY','SYSTEM')
$auth       = New-Object System.Security.Principal.NTAccount('NT AUTHORITY','Authenticated Users')
$itTeam     = New-Object System.Security.Principal.NTAccount('DRAGEIDE','ITTeam')
$salesTeam  = New-Object System.Security.Principal.NTAccount('DRAGEIDE','salg')
$admTeam    = New-Object System.Security.Principal.NTAccount('DRAGEIDE','adm')

# Map each folder to its group
$folderToGroup = @{
    'IT'  = $itTeam
    'Salg' = $salesTeam
    'adm' = $admTeam
}

# Ensure admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Run as Administrator."
    exit 1
}

# Create root folder
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
        -Description "Department Share Root" | Out-Null
} else {
    Set-SmbShare -Name $ShareName -FolderEnumerationMode AccessBased -CachingMode None
    Revoke-SmbShareAccess -Name $ShareName -AccountName Everyone -Force -ErrorAction SilentlyContinue
    Grant-SmbShareAccess  -Name $ShareName -AccountName "BUILTIN\Administrators" -AccessRight Full   -Force
    Grant-SmbShareAccess  -Name $ShareName -AccountName "NT AUTHORITY\SYSTEM"   -AccessRight Full   -Force
    Grant-SmbShareAccess  -Name $ShareName -AccountName "NT AUTHORITY\Authenticated Users" -AccessRight Change -Force
}

# =========================
# NTFS ACLs on ROOT (clean)
# =========================
$root = Get-Item -Path $FolderPath
$acl  = $root.GetAccessControl('Access')

# Disable inheritance and remove existing explicit ACEs to start clean
$acl.SetAccessRuleProtection($true, $false)
foreach ($rule in @($acl.Access)) { $acl.RemoveAccessRule($rule) | Out-Null }

# Admins + SYSTEM: Full (inherit to all from root only if we want; safe to inherit)
$inheritAll = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit `
            -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit

$acl.AddAccessRule( (New-Object System.Security.AccessControl.FileSystemAccessRule(
    $admins,
    [System.Security.AccessControl.FileSystemRights]::FullControl,
    $inheritAll,
    [System.Security.AccessControl.PropagationFlags]::None,
    [System.Security.AccessControl.AccessControlType]::Allow
)))
$acl.AddAccessRule( (New-Object System.Security.AccessControl.FileSystemAccessRule(
    $system,
    [System.Security.AccessControl.FileSystemRights]::FullControl,
    $inheritAll,
    [System.Security.AccessControl.PropagationFlags]::None,
    [System.Security.AccessControl.AccessControlType]::Allow
)))

# Authenticated Users: THIS FOLDER ONLY (allow listing and creating department subfolders if desired)
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

Write-Output "Root '$FolderPath' created and NTFS permissions applied."

# ===========================================================
# Create child folders and APPLY EXPLICIT ACLs (NO INHERIT)
# ===========================================================
# Department rights (match your screenshot)
$deptRights =
    [System.Security.AccessControl.FileSystemRights]::Read `
    -bor [System.Security.AccessControl.FileSystemRights]::ReadPermissions `
    -bor [System.Security.AccessControl.FileSystemRights]::WriteAttributes `
    -bor [System.Security.AccessControl.FileSystemRights]::Delete

foreach ($name in $children) {
    $childPath = Join-Path $FolderPath $name
    if (-not (Test-Path $childPath)) {
        New-Item -Path $childPath -ItemType Directory -Force | Out-Null
        Write-Output "Created child folder: $childPath"
    }

    $childItem = Get-Item $childPath
    $childAcl  = $childItem.GetAccessControl('Access')

    # 1) BREAK inheritance on the CHILD and do NOT keep inherited ACEs
    $childAcl.SetAccessRuleProtection($true, $false)

    # 2) Remove any existing explicit ACEs
    foreach ($r in @($childAcl.Access)) { $childAcl.RemoveAccessRule($r) | Out-Null }

    # 3) Add EXPLICIT ACEs for Admins + SYSTEM (FullControl on this folder, subfolders, files)
    $childAcl.AddAccessRule( (New-Object System.Security.AccessControl.FileSystemAccessRule(
        $admins,
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        $inheritAll,
        [System.Security.AccessControl.PropagationFlags]::None,
        [System.Security.AccessControl.AccessControlType]::Allow
    )))
    $childAcl.AddAccessRule( (New-Object System.Security.AccessControl.FileSystemAccessRule(
        $system,
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        $inheritAll,
        [System.Security.AccessControl.PropagationFlags]::None,
        [System.Security.AccessControl.AccessControlType]::Allow
    )))

    # 4) Add EXPLICIT ACE for the department group (exact rights from your screenshot)
    $deptGroup = $folderToGroup[$name]
    if (-not $deptGroup) {
        Write-Warning "No mapped group for '$name' – skipping department ACE."
    } else {
        $childAcl.AddAccessRule( (New-Object System.Security.AccessControl.FileSystemAccessRule(
            $deptGroup,
            $deptRights,
            $inheritAll,  # applies to this folder, subfolders and files
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Allow
        )))
    }

    # 5) Do NOT add Authenticated Users here
    # (Root AU is this folder only; children have no AU unless you explicitly add it.)

    $childItem.SetAccessControl($childAcl)
    Write-Output "Applied EXPLICIT ACLs to '$childPath' (no inheritance from parent)."
}

Write-Output "Department subfolders created and permissions applied."