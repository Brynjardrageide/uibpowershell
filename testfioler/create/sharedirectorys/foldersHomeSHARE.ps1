<#
Script: foldersHomeSHARE.ps1
Purpose: Create a folder, optionally create a local user, set NTFS permissions and create a hidden SMB share (share name ends with $).
Run as Administrator.
#>

param(
    [string]$FolderPath = 'C:\Shares\HomeShare',       # Path on disk to create the folder
    [string]$ShareName = 'HomeShare$'                # SMB share name (ending with $ makes it hidden)
)

# Ensure script is running elevated (required for creating shares and ACL changes).
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator."
    exit 1
}

# Create the folder on disk (if it already exists -Force will not error).
New-Item -Path $FolderPath -ItemType Directory -Force | Out-Null

# Optionally mark the folder with the Hidden attribute on the filesystem.
# Note: the trailing $ in the share name makes the SMB share hidden; setting the Hidden attribute hides the folder in Explorer.
$folderItem = Get-Item -LiteralPath $FolderPath
$folderItem.Attributes = $folderItem.Attributes -bor [System.IO.FileAttributes]::Hidden

# here we will share the folder with SMB share
New-SmbShare -Name $ShareName -Path $FolderPath -Description "Home Share for Users" -ErrorAction Stop
