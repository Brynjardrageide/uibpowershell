<#
.SYNOPSIS
    Create a new GPO and link it to an OU or domain.

.DESCRIPTION
    This script creates a Group Policy Object (GPO) and links it to the target you specify.
    It requires the GroupPolicy module and domain admin (or equivalent) privileges.

.PARAMETER GpoName
    Name of the GPO to create. Default: "ShareFoldersGPO"

.PARAMETER LinkTarget
    Distinguished name (DN) of the container to link the GPO to. Example:
        "OU=Users,OU=Dept,DC=contoso,DC=com"
    To link to the domain root use: "DC=contoso,DC=com"

.PARAMETER Domain
    DNS name of the domain. If omitted the script will try to infer it from the environment.

.PARAMETER Comment
    Optional comment stored with the GPO.

.PARAMETER Enforced
    $true to enforce the link, $false otherwise. Default: $false

.EXAMPLE
    .\sharefolders.ps1 -GpoName "MapHomeDrive" -LinkTarget "OU=Staff,DC=contoso,DC=com" -Domain contoso.com

#>

param(
        [string]$GpoName = "ShareFoldersGPO",
        [Parameter(Mandatory=$true)][string]$LinkTarget,
        [string]$Domain = $env:USERDNSDOMAIN,
        [string]$Comment = "Created by script",
        [bool]$Enforced = $false
)

# Ensure GroupPolicy module is available
if (-not (Get-Module -ListAvailable -Name GroupPolicy)) {
        Write-Error "GroupPolicy module not found. Run this on a domain-joined management machine with RSAT installed."
        exit 1
}
Import-Module GroupPolicy

try {
        Write-Output "Creating GPO '$GpoName' in domain '$Domain'..."
        $gpo = New-GPO -Name $GpoName -Domain $Domain -Comment $Comment -ErrorAction Stop

        Write-Output "Linking GPO '$GpoName' to '$LinkTarget'..."
        # New-GPLink accepts a target like "OU=Sales,DC=contoso,DC=com" or "DC=contoso,DC=com"
        New-GPLink -Name $gpo.DisplayName -Target $LinkTarget -LinkEnabled Yes -Enforced:$Enforced -ErrorAction Stop

        Write-Output "GPO created and linked successfully."
        Write-Output "GPO DisplayName : $($gpo.DisplayName)"
        Write-Output "GPO Id          : $($gpo.Id.Guid)"
        Write-Output "Link target     : $LinkTarget"
        Write-Output "Enforced        : $Enforced"

        Write-Output ""
        Write-Output "Next steps (common tasks you may want to do):"
        Write-Output " - Use the Group Policy Management Console (GPMC) to edit the GPO and configure:"
        Write-Output "     * User Configuration -> Preferences -> Windows Settings -> Drive Maps (map home drive)"
        Write-Output "     * User Configuration -> Windows Settings -> Folder Redirection (Documents, Desktop, etc.)"
        Write-Output " - Or prepare a logon script and place it under the GPO's SysVol Scripts folder and add it as a Logon script."

} catch {
        Write-Error "Failed: $_"
        exit 1
}
try {
        # Optional: Verify the GPO and link exist
        $gpoCheck = Get-GPO -Name $GpoName -Domain $Domain -ErrorAction Stop
        $links = Get-GPLink -Guid $gpoCheck.Id.Guid -Domain $Domain -ErrorAction Stop
        if ($links.Target -notcontains $LinkTarget) {
                Write-Warning "GPO created but link to '$LinkTarget' not found. Please verify in GPMC."
        }
} catch {
        Write-Warning "Could not verify GPO/link: $_"
}
