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

param(
    [string]$ServerName = $env:COMPUTERNAME,
    [int]$Port = 8530,
    [switch]$UseSsl,
    [switch]$WhatIf
)

Set-StrictMode -Version Latest

function Write-Info { param($m) Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Write-Warn { param($m) Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host "[ERROR] $m" -ForegroundColor Red }

Write-Info "Loading UpdateServices module..."
if (-not (Get-Module -ListAvailable -Name UpdateServices)) {
    try {
        Import-Module UpdateServices -ErrorAction Stop
    } catch {
        Write-Err "UpdateServices module not found or could not be imported. Ensure WSUS management tools are installed. $_"
        exit 1
    }
} else {
    Import-Module UpdateServices -ErrorAction SilentlyContinue
}

try {
    Write-Info "Getting WSUS server object for '$ServerName' (port $Port, UseSsl=$UseSsl)..."
    if ($ServerName -and ($ServerName -ne $env:COMPUTERNAME)) {
        $wsus = Get-WsusServer -Name $ServerName -PortNumber $Port -UseSsl:$UseSsl
    } else {
        $wsus = Get-WsusServer -PortNumber $Port -UseSsl:$UseSsl
    }
} catch {
    Write-Err "Failed to get WSUS server object: $_"
    exit 2
}

Write-Info "Configuring upstream synchronization: Microsoft Update (SyncFromMU)..."
if ($WhatIf) {
    Write-Info "WhatIf: would run Set-WsusServerSynchronization -UpdateServer <wsus> -SyncFromMU"
} else {
    try {
        Set-WsusServerSynchronization -UpdateServer $wsus -SyncFromMU -ErrorAction Stop
        Write-Info "WSUS configured to synchronize from Microsoft Update."
    } catch {
        Write-Err "Failed to set synchronization to Microsoft Update: $_"
    }
}

# Try to remove an automatic synchronization schedule so syncs are manual
Write-Info "Ensuring synchronization is manual (no scheduled automatic sync)..."
try {
    $subscription = $wsus.GetSubscription()
    if ($subscription -ne $null) {
        # Inspect for a schedule property and attempt to clear it. Exact API names differ between versions
        $props = ($subscription | Get-Member -MemberType *Property | Select-Object -ExpandProperty Name)
        if ($props -contains 'SynchronizationSchedule') {
            if ($WhatIf) {
                Write-Info "WhatIf: would clear SynchronizationSchedule on subscription (make manual)."
            } else {
                $subscription.SynchronizationSchedule = $null
                $subscription.Save()
                Write-Info "Cleared SynchronizationSchedule (synchronization set to manual)."
            }
        } else {
            Write-Warn "Could not find a 'SynchronizationSchedule' property on the subscription object. If the schedule remains, remove it in the WSUS console (Options -> Synchronization) to make syncs manual."
        }
    } else {
        Write-Warn "Subscription object is null; could not modify schedule."
    }
} catch {
    Write-Warn "Could not modify synchronization schedule via the API: $_. You can set manual sync from the WSUS console (Options -> Synchronization)."
}

# Enable products (Windows 10 and Windows 11)
Write-Info "Enabling product categories: Windows 10 and Windows 11 (matched by title)..."
try {
    $products = Get-WsusProduct -UpdateServer $wsus | Where-Object { $_.product.title -match 'Windows 10|Windows 11' }
    if ($products -and $products.Count -gt 0) {
        if ($WhatIf) {
            $products | ForEach-Object { Write-Info "WhatIf: would enable product: $($_.product.title)" }
        } else {
            $products | Set-WsusProduct
            Write-Info "Enabled products: $((($products | ForEach-Object { $_.product.title }) -join ', '))"
        }
    } else {
        Write-Warn "No products matched 'Windows 10' or 'Windows 11'. Run Get-WsusProduct to list available titles."
    }
} catch {
    Write-Err "Failed to enable products: $_"
}

# Enable classifications: Critical Updates and Definition Updates
Write-Info "Enabling classifications: Critical Updates and Definition Updates..."
try {
    $wanted = @('Critical Updates','Definition Updates','security updates')
    $classes = Get-WsusClassification -UpdateServer $wsus | Where-Object { $wanted -contains $_.Classification.Title }
    if ($classes -and $classes.Count -gt 0) {
        if ($WhatIf) {
            $classes | ForEach-Object { Write-Info "WhatIf: would enable classification: $($_.Classification.Title)" }
        } else {
            $classes | Set-WsusClassification
            Write-Info "Enabled classifications: $((($classes | ForEach-Object { $_.Classification.Title }) -join ', '))"
        }
    } else {
        Write-Warn "Could not find the requested classifications. Run Get-WsusClassification to see available values."
    }
} catch {
    Write-Err "Failed to enable classifications: $_"
}

# Attempt to disable storing update files locally
Write-Info "Attempting to disable storing update files locally on this WSUS server (if supported by the API)..."
try {
    $config = $wsus.GetConfiguration()
    if ($config -ne $null) {
        $configProps = ($config | Get-Member -MemberType *Property | Select-Object -ExpandProperty Name)
        $candidates = @('UpdateFilesStoredLocally','StoreUpdatesLocally','StoreUpdateFilesLocally','ContentLocalPublishingEnabled')
        $found = $configProps | Where-Object { $candidates -contains $_ }
        if ($found -and $found.Count -gt 0) {
            foreach ($p in $found) {
                if ($WhatIf) {
                    Write-Info "WhatIf: would set configuration property '$p' = $false"
                } else {
                    try {
                        $config.$p = $false
                        Write-Info "Set $p = false"
                    } catch {
                        Write-Warn "Could not set property '$p': $_"
                    }
                }
            }
            if (-not $WhatIf) {
                try { $config.Save(); Write-Info "Saved WSUS configuration changes." } catch { Write-Warn "Failed saving configuration: $_" }
            }
        } else {
            Write-Warn "No direct configuration property found to disable local update file storage. Please disable 'Store update files locally on this server' in the WSUS console under Options -> Update Files and Languages."
        }
    } else {
        Write-Warn "Unable to retrieve WSUS configuration object."
    }
} catch {
    Write-Warn "Error while attempting to change WSUS configuration: $_"
}

Write-Info "Configuration script finished."
Write-Info "If you want to run an immediate manual sync, run: Start-WsusSynchronization -UpdateServer (Get-WsusServer -Name '$ServerName' -PortNumber $Port -UseSsl:$UseSsl)"

# End of script
