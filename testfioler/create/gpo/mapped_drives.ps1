<#
.SYNOPSIS
    Create a Group Policy that maps a network drive at user logon by adding a Run entry (net use).

.DESCRIPTION
    This script creates a GPO, adds a user-run registry entry so Windows runs a net use command at logon,
    and links the GPO to the specified AD target (OU or domain). It uses the GroupPolicy module (RSAT).
    This is a simple, reliable way to deploy mapped drives without fiddling with GPO Preferences XML.

.REQUIREMENTS
    - Run as a user with permissions to create GPOs and link them (Domain Admin or delegated R/W on the OU).
    - RSAT Group Policy Management Tools installed (GroupPolicy PowerShell module).
    - Example OU target: "OU=Staff,DC=contoso,DC=com" or domain root "contoso.com"

.PARAMETER GPOName
    Name of the GPO to create (if exists, the GPO will be reused).

.PARAMETER Target
    Active Directory target to link the GPO to. Can be an OU distinguishedName or domain DNS (e.g. contoso.com).

.PARAMETER DriveLetter
    Drive letter to assign (e.g. "Z:").

.PARAMETER SharePath
    UNC path to the share (e.g. "\\fileserver\share").

.PARAMETER Persistent
    $true to use /persistent:yes, $false for /persistent:no (default $false).

.EXAMPLE
    .\mapped_drives.ps1 -GPOName "Map Z Drive" -Target "OU=Staff,DC=contoso,DC=com" -DriveLetter "Z:" -SharePath "\\fs01\users" -Persistent $false
#>

param(
        [Parameter(Mandatory=$true)]
        [string]$GPOName,

        [Parameter(Mandatory=$true)]
        [string]$Target,

        [Parameter(Mandatory=$true)]
        [ValidatePattern('^[A-Z]:$','IgnoreCase')]
        [string]$DriveLetter,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SharePath,

        [bool]$Persistent = $false
)

# Ensure GroupPolicy module available
if (-not (Get-Module -ListAvailable -Name GroupPolicy)) {
        Write-Error "GroupPolicy module not available. Install RSAT Group Policy Management Tools and run from a machine with RSAT."
        exit 1
}

Import-Module GroupPolicy -ErrorAction Stop

# Build net use command
$persistArg = if ($Persistent) { "yes" } else { "no" }
# Use /HOME or /USER when needed; the command below uses basic net use. Adjust for credentials if needed.
$netUseCmd = "cmd.exe /c ""net use $DriveLetter `"$SharePath`" /persistent:$persistArg"""

# Create or get GPO
$gpo = Get-GPO -Name $GPOName -ErrorAction SilentlyContinue
if (-not $gpo) {
        Write-Output "Creating GPO '$GPOName'..."
        $gpo = New-GPO -Name $GPOName -Comment "Maps $DriveLetter to $SharePath via Run key (net use)" -ErrorAction Stop
} else {
        Write-Output "Using existing GPO '$GPOName' (Id: $($gpo.Id))"
}

# Add a User registry Run key entry in the GPO
# This will cause the net use command to run at user logon.
$runValueName = "MapDrive_$($DriveLetter.TrimEnd(':'))"
try {
        Write-Output "Writing Run registry entry to GPO..."
        Set-GPRegistryValue -Name $GPOName `
                                                -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" `
                                                -ValueName $runValueName `
                                                -Type String `
                                                -Value $netUseCmd -ErrorAction Stop
} catch {
        Write-Error "Failed to set registry value in GPO: $_"
        exit 2
}

# Link GPO to the specified target
# Target must be a domain DNS name (e.g. contoso.com) or an AD path (OU=...,DC=...,DC=...)
try {
        Write-Output "Linking GPO '$GPOName' to target '$Target'..."
        # If already linked, this will update the link; Set-GPLink will create link if missing.
        Set-GPLink -Name $GPOName -Target $Target -LinkEnabled Yes -ErrorAction Stop
} catch {
        Write-Error "Failed to link GPO. Verify the target is correct and you have permission: $_"
        exit 3
}

Write-Output "Done. Users in '$Target' will run: $netUseCmd at next logon (or after gpupdate /force)."
Write-Output "Notes:"
Write-Output " - If credentials are required to access the share, consider using Group Policy Preferences Drive Maps or handle credentials via domain authentication."
Write-Output " - To remove the mapping later, remove the Run value from the GPO (Remove-GPRegistryValue)."