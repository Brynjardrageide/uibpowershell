<#
WSUS configuration script

What this script does (safe defaults):
- Sets the WSUS server to synchronize from Microsoft Update (http://windowsupdate.microsoft.com)
- Attempts to set synchronization to manual (no scheduled automatic sync)
- Enables products matching "Windows 10" and "Windows 11" (includes dynamic updates)
- Enables classifications: Critical Updates and Definition Updates
- Attempts to disable storing update files locally (if the WSUS API exposes a property for that)

Usage examples:
    .\wsus.ps1 -ServerName WSUS-SERVER
    .\wsus.ps1 -WhatIf    # show what would happen

Note: run this on the WSUS server (or against a remote WSUS server with WinRM/permissions). Some configuration changes require administrative privileges.
See: https://learn.microsoft.com/powershell/module/updateservices
#>
Install-WindowsFeature -name windows-server-update-services -IncludeManagementTools
Install-WindowsFeature -name UpdateServices
param(
    [string]$ServerName = $env:COMPUTERNAME,
    [int]$Port = 8530,
    [switch]$UseSsl,
    [switch]$WhatIf
)

# ---------------------------
#  Functions
# ---------------------------
function Info ($msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Warn ($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Err ($msg)  { Write-Host "[ERROR] $msg" -ForegroundColor Red }

# ---------------------------
#  Load WSUS module
# ---------------------------
Info "Loading UpdateServices module..."
try {
    Import-Module UpdateServices -ErrorAction Stop
}
catch {
    Err "UpdateServices module not available. Make sure WSUS role + management tools are installed."
    exit 1
}

# ---------------------------
#  Connect to WSUS server
# ---------------------------
Info "Connecting to WSUS server: $ServerName (Port $Port, SSL: $UseSsl)..."

try {
    $wsus = Get-WsusServer -Name $ServerName -PortNumber $Port -UseSsl:$UseSsl
}
catch {
    Err "Failed to connect to WSUS server: $_"
    exit 2
}

# ---------------------------
#  Configure Sync Source
# ---------------------------
Info "Configuring synchronization source: Microsoft Update..."

if ($WhatIf) {
    Info "WhatIf: Would run Set-WsusServerSynchronization -SyncFromMU"
}
else {
    try {
        Set-WsusServerSynchronization -UpdateServer $wsus -SyncFromMU -ErrorAction Stop
        Info "Synchronization set to Microsoft Update."
    }
    catch {
        Err "Failed to configure upstream source: $_"
    }
}

# ---------------------------
#  Manual Sync (Remove schedule)
# ---------------------------
Info "Setting synchronization schedule to MANUAL..."

try {
    $subscription = $wsus.GetSubscription()

    # Many WSUS versions use this property
    if ($subscription -and $subscription.SynchronizeAutomatically -ne $null) {
        if ($WhatIf) {
            Info "WhatIf: Would disable automatic sync schedule."
        }
        else {
            $subscription.SynchronizeAutomatically = $false
            $subscription.Save()
            Info "Automatic synchronizations disabled (manual mode)."
        }
    }
    else {
        Warn "Automatic sync property not found. Use WSUS console if needed."
    }
}
catch {
    Warn "Could not modify sync schedule: $_"
}

# ---------------------------
#  Enable Product Categories
# ---------------------------
Info "Enabling products: Windows 10, Windows 11, Dynamic Updates..."

try {
    $products = Get-WsusProduct -UpdateServer $wsus |
        Where-Object {
            $_.Product.Title -match 'Windows 10' -or
            $_.Product.Title -match 'Windows 11' -or
            $_.Product.Title -match 'Dynamic Update'
        }

    if ($products.Count -gt 0) {
        if ($WhatIf) {
            $products | ForEach-Object { Info "WhatIf: Would enable product $($_.Product.Title)" }
        }
        else {
            $products | Set-WsusProduct
            Info "Enabled products: $($products.Product.Title -join ', ')"
        }
    }
    else {
        Warn "No matching products found. Run Get-WsusProduct manually to inspect available ones."
    }
}
catch {
    Err "Error enabling products: $_"
}

# ---------------------------
#  Enable Update Classifications
# ---------------------------
Info "Enabling classifications: Critical, Security, Definition Updates..."

$desired = @(
    "Critical Updates",
    "Definition Updates",
    "Security Updates"
)

try {
    $class = Get-WsusClassification -UpdateServer $wsus |
        Where-Object { $desired -contains $_.Classification.Title }

    if ($class.Count -gt 0) {
        if ($WhatIf) {
            $class | ForEach-Object { Info "WhatIf: Would enable classification $($_.Classification.Title)" }
        }
        else {
            $class | Set-WsusClassification
            Info "Enabled: $($class.Classification.Title -join ', ')"
        }
    }
    else {
        Warn "No matching classifications found."
    }
}
catch {
    Err "Could not set classifications: $_"
}

# ---------------------------
#  Disable Local Update Storage
# ---------------------------
Info "Disabling 'store updates locally' (download-from-Microsoft mode)..."

try {
    $config = $wsus.GetConfiguration()
    if ($config) {
        if ($WhatIf) {
            Info "WhatIf: Would set StoreUpdateFilesLocally = $false"
        }
        else {
            $config.StoreUpdateFilesLocally = $false
            $config.Save()
            Info "Local storage disabled. WSUS will not download updates."
        }
    }
}
catch {
    Warn "Failed to disable local file storage: $_"
}

Info "WSUS configuration completed!"