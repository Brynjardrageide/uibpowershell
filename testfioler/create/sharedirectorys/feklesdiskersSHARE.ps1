<#
Script:     Create-DeptShareRoot.ps1
Purpose:    Create root share and department subfolders with proper share + NTFS permissions.
Run on:     The FILE SERVER (as Administrator)
#>

param(
    [string]$FolderPath = 'C:\Shares\FELLES',
    [string]$ShareName  = 'felles$',
    [switch]$HideFolder
)

# Department children (adjust casing to your preference)
$children = @('IT','SAlg','adm')

# Accounts / Groups
$admins     = New-Object System.Security.Principal.NTAccount('BUILTIN','Administrators')
$system     = New-Object System.Security.Principal.NTAccount('NT AUTHORITY','SYSTEM')
$auth       = New-Object System.Security.Principal.NTAccount('NT AUTHORITY','Authenticated Users')
$itTeam     = New-Object System.Security.Principal.NTAccount('DRAGEIDE','ITTeam')
$salesTeam  = New-Object System.Security.Principal.NTAccount('DRAGEIDE','salg')
$admTeam    = New-Object System.Security.Principal.NTAccount('DRAGEIDE','adm')

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

# Create / Fix share
if (-not (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue)) {
    New-SmbShare `
        -Name $ShareName `
        -Path $FolderPath `
        -FullAccess "BUILTIN\Administrators","NT AUTHORITY\SYSTEM" `
        -ChangeAccess "NT AUTHORITY\Authenticated Users" `
        -FolderEnumerationMode AccessBased `
        -CachingMode None `
        -Description "Department Root" | Out-Null
} else {
    Set-SmbShare -Name $ShareName -FolderEnumerationMode AccessBased -CachingMode None
    Revoke-SmbShareAccess -Name $ShareName -AccountName Everyone -Force -ErrorAction SilentlyContinue
    Grant-SmbShareAccess  -Name $ShareName -AccountName "BUILTIN\Administrators"          -AccessRight Full   -Force
    Grant-SmbShareAccess  -Name $ShareName -AccountName "NT AUTHORITY\SYSTEM"             -AccessRight Full   -Force
    Grant-SmbShareAccess  -Name $ShareName -AccountName "NT AUTHORITY\Authenticated Users"-AccessRight Change -Force
}

# ---------------------------
# NTFS: Root folder
# ---------------------------
$root = Get-Item -Path $FolderPath
$acl  = $root.GetAccessControl('Access')

# Start clean: disable inheritance and remove existing explicit ACEs
$acl.SetAccessRuleProtection($true, $false)
foreach ($rule in $acl.Access) { $null = $acl.RemoveAccessRule($rule) }

# Admins + SYSTEM: Full Control (inherit to all)
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

# Authenticated Users: THIS FOLDER ONLY (to allow creating dept subfolders at the root, optional)
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

Write-Output "Root NTFS permissions applied."

# ---------------------------
# Create department subfolders
# ---------------------------
foreach ($child in $children) {
    $childPath = Join-Path $FolderPath $child
    if (-not (Test-Path $childPath)) {
        New-Item -Path $childPath -ItemType Directory -Force | Out-Null
        Write-Output "Created child folder: $childPath"
    } else {
        Write-Output "Child folder already exists: $childPath"
    }
}

# ---------------------------
# NTFS: Department ACLs
# ---------------------------

# Build a hashtable of department -> group
$deptMap = @{
    'IT'   = $itTeam
    'SAlg' = $salesTeam
    'adm'  = $admTeam
}

# Define Modify rights (canonical Modify mask)
$modifyRights =
      [System.Security.AccessControl.FileSystemRights]::Modify
# If you prefer explicit expansion instead of Modify:
# $modifyRights =
#     [System.Security.AccessControl.FileSystemRights]::ReadAndExecute `
#   -bor [System.Security.AccessControl.FileSystemRights]::ListDirectory `
#   -bor [System.Security.AccessControl.FileSystemRights]::ReadAttributes `
#   -bor [System.Security.AccessControl.FileSystemRights]::ReadExtendedAttributes `
#   -bor [System.Security.AccessControl.FileSystemRights]::ReadPermissions `
#   -bor [System.Security.AccessControl.FileSystemRights]::Write `
#   -bor [System.Security.AccessControl.FileSystemRights]::WriteAttributes `
#   -bor [System.Security.AccessControl.FileSystemRights]::WriteExtendedAttributes `
#   -bor [System.Security.AccessControl.FileSystemRights]::AppendData `
#   -bor [System.Security.AccessControl.FileSystemRights]::Delete `
#   -bor [System.Security.AccessControl.FileSystemRights]::Synchronize

$propNone = [System.Security.AccessControl.PropagationFlags]::None

foreach ($child in $children) {
    $childPath = Join-Path $FolderPath $child
    $childItem = Get-Item $childPath
    $acl = $childItem.GetAccessControl('Access')

    # Break inheritance, COPY existing ACEs so Admins/SYSTEM stay; then we'll prune AU if present
    $acl.SetAccessRuleProtection($true, $true)

    # Remove any Authenticated Users ACEs that may have flowed down
    foreach ($rule in $acl.Access | Where-Object { $_.IdentityReference -eq $auth }) {
        $null = $acl.RemoveAccessRuleSpecific($rule)
    }

    # Ensure Admins + SYSTEM Full Control (inherit to all)
    $acl.AddAccessRule( (New-Object System.Security.AccessControl.FileSystemAccessRule(
        $admins,
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        $inheritAll,
        $propNone,
        [System.Security.AccessControl.AccessControlType]::Allow
    )))
    $acl.AddAccessRule( (New-Object System.Security.AccessControl.FileSystemAccessRule(
        $system,
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        $inheritAll,
        $propNone,
        [System.Security.AccessControl.AccessControlType]::Allow
    )))

    # Department group: Modify (inherit to all)
    $deptGroup = $deptMap[$child]
    if ($null -eq $deptGroup) {
        Write-Warning "No group mapped for child '$child' – skipping dept ACL."
    } else {
        $acl.AddAccessRule( (New-Object System.Security.AccessControl.FileSystemAccessRule(
            $deptGroup,
            $modifyRights,
            $inheritAll,
            $propNone,
            [System.Security.AccessControl.AccessControlType]::Allow
        )))
    }

    # Optional: CREATOR OWNER Full Control on subfolders/files only (good practice)
    $creatorOwner = New-Object System.Security.Principal.NTAccount('CREATOR OWNER')
    $acl.AddAccessRule( (New-Object System.Security.AccessControl.FileSystemAccessRule(
        $creatorOwner,
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        # Files and subfolders only:
        ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
        [System.Security.AccessControl.PropagationFlags]::InheritOnly,
        [System.Security.AccessControl.AccessControlType]::Allow
    )))

    $childItem.SetAccessControl($acl)
    Write-Output "Applied ACLs to: $childPath"
}

Write-Output "Department subfolders created and permissions applied (Admins=Full, Dept=Modify)."
