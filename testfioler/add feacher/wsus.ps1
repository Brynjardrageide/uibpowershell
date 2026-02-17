#requires -RunAsAdministrator
<#
.SYNOPSIS
  One-file WSUS setup for Windows Server 2022 using your requested installer command.
  Phase 1: Creates a self-scheduling task and runs Install-WindowsFeature ... -Restart (auto reboot).
  Phase 2: After reboot, completes WSUS postinstall + configuration and removes the task.

.PARAMETER PostConfig
  Internal switch used by the Scheduled Task to run the post-reboot configuration phase.

.PARAMETER NetFx35Source
  (Optional) Path to the Windows installation sources for .NET 3.5 (e.g., D:\sources\sxs).
  If provided, the script will attempt to install .NET 3.5 (useful for legacy reporting).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File C:\WSUS\wsus-one-script.ps1
#>

param(
    [switch] $PostConfig,
    [string] $NetFx35Source
)

# -------------------- Constants & Paths --------------------
$BaseDir            = "C:\WSUS"
$ContentDir         = Join-Path $BaseDir "Content"       # Required by wsusutil postinstall even if we don't store locally
$LogDir             = Join-Path $BaseDir "Logs"
$LogFile            = Join-Path $LogDir ("wsus_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
$TaskName           = "WSUS-OneScript-PostConfig"
$ThisScriptPath     = $PSCommandPath
$WsusUtil           = Join-Path "$env:ProgramFiles\Update Services\Tools" "wsusutil.exe"
$WsusPort           = 8530  # default HTTP port
$ProductsWanted     = @("Windows 10", "Windows 11 Dynamic Update")
$ClassWanted        = @("Critical Updates", "Security Updates", "Definition Updates")
$LanguageCodes      = @("en")
# ----------------------------------------------------------

# Ensure base folders exist
New-Item -Path $BaseDir -ItemType Directory -Force | Out-Null
New-Item -Path $ContentDir -ItemType Directory -Force | Out-Null
New-Item -Path $LogDir -ItemType Directory -Force | Out-Null

# Helper: Write status to console with color
function Write-Info($msg){ Write-Host $msg -ForegroundColor Cyan }
function Write-Warn($msg){ Write-Host $msg -ForegroundColor Yellow }
function Write-Ok($msg)  { Write-Host $msg -ForegroundColor Green }
function Write-Err($msg) { Write-Host $msg -ForegroundColor Red }

# ---------------------- Phase 1 ---------------------------
if (-not $PostConfig) {
    Write-Info "Phase 1: Registering a one-time Scheduled Task to complete WSUS configuration after reboot..."

    # Create scheduled task that runs THIS script with -PostConfig
    $action    = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ThisScriptPath`" -PostConfig"
    $trigger   = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    # Replace existing task if present
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal | Out-Null
    Write-Ok "Scheduled Task '$TaskName' registered to run after reboot."

    Write-Info "Installing WSUS role with your exact command (this will reboot automatically)..."
    # Your requested installer command:
    Install-WindowsFeature -Name UpdateServices -IncludeManagementTools -Restart

    # If the server didn't restart for any reason, force it (normally not needed).
    Write-Warn "Install-WindowsFeature did not trigger a restart; forcing reboot now..."
    Restart-Computer -Force
    return
}

# ---------------------- Phase 2 ---------------------------
Start-Transcript -Path $LogFile -Force | Out-Null
try {
    Write-Info "Phase 2: Post-reboot WSUS postinstall and configuration starting..."

    # Ensure wsusutil exists
    if (-not (Test-Path $WsusUtil)) {
        throw "wsusutil.exe not found at '$WsusUtil'. Verify WSUS role installed correctly."
    }

    # Run wsusutil postinstall (even if we don't store binaries locally, this step initializes DB & IIS)
    Write-Info "Running wsusutil postinstall with CONTENT_DIR='$ContentDir'..."
    & "$WsusUtil" postinstall CONTENT_DIR="$ContentDir"
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "wsusutil postinstall returned exit code $LASTEXITCODE. Continuing, but WSUS may not be fully initialized."
    }

    # Wait briefly for WSUS services to settle
    Start-Sleep -Seconds 8

    # Import module and connect to WSUS
    Import-Module UpdateServices -ErrorAction Stop
    $wsus   = Get-WsusServer -Name "localhost" -PortNumber $WsusPort
    $config = $wsus.GetConfiguration()

    # Core configuration
    Write-Info "Configuring: source=Microsoft Update, no proxy, manual sync, no local content..."
    $config.SyncFromMicrosoftUpdate           = $true
    $config.UseProxy                          = $false
    $config.AutomaticSynchronizationEnabled   = $false
    $config.NumberOfSynchronizationsPerDay    = 0
    $config.HostBinariesOnMicrosoftUpdate     = $true
    if ($config.PSObject.Properties.Name -contains 'DownloadExpressPackages') {
        $config.DownloadExpressPackages       = $false
    }

    # Language (English only per your example)
    Write-Info "Setting languages: $($LanguageCodes -join ', ')"
    $config.AllUpdateLanguagesEnabled = $false
    $config.SetEnabledUpdateLanguages($LanguageCodes)

    # Mark OOBE complete
    $config.OobeInitialized = $true
    $config.Save()

    # Initial category-only sync (to populate product/classification catalogs)
    $subscription = $wsus.GetSubscription()
    Write-Info "Starting initial Category-Only synchronization..."
    $subscription.StartSynchronizationForCategoryOnly()

    # Wait until the category-only sync finishes (timeout: ~45 minutes)
    $timeout = [TimeSpan]::FromMinutes(45)
    $start   = Get-Date
    do {
        Start-Sleep -Seconds 15
        $status = $subscription.GetSynchronizationStatus()
        $progress = $subscription.GetSynchronizationProgress()
        Write-Host ("  Status: {0}; Progress: {1}%" -f $status, $progress.PercentComplete)
        if ($status -ne 'Running') { break }
    } while ((Get-Date) - $start -lt $timeout)

    if ($status -eq 'Running') {
        Write-Warn "Category-only sync still running after timeout; proceeding, but product list may be incomplete."
    } else {
        Write-Ok "Category-only sync completed."
    }

    # Enable only the products you want; disable the rest
    Write-Info "Configuring Products: enabling only -> $($ProductsWanted -join ', ')"
    $allProducts = Get-WsusProduct
    $enabledAny = $false

    foreach ($p in $allProducts) {
        $title = $p.Product.Title
        if ($ProductsWanted -contains $title) {
            Set-WsusProduct -InputObject $p -Enable
            $enabledAny = $true
        } else {
            Set-WsusProduct -InputObject $p -Disable
        }
    }
    if (-not $enabledAny) {
        Write-Warn "None of the requested products were found. Available product titles:"
        $allProducts | ForEach-Object { $_.Product.Title } | Sort-Object | ForEach-Object { Write-Host "  - $_" }
    }

    # Enable only the classifications you want; disable the rest
    Write-Info "Configuring Classifications: enabling only -> $($ClassWanted -join ', ')"
    $allClasses = Get-WsusClassification
    foreach ($c in $allClasses) {
        $title = $c.Classification.Title
        if ($ClassWanted -contains $title) {
            Set-WsusClassification -InputObject $c -Enable
        } else {
            Set-WsusClassification -InputObject $c -Disable
        }
    }

    # DO NOT start a full sync automatically (manual schedule as requested).
    # If you want to kick off a sync manually later, run:
    #   Import-Module UpdateServices
    #   $wsus = Get-WsusServer -Name "localhost" -PortNumber 8530
    #   Sync-WsusServer -Asynchronous

    # Create Computer Target Groups (Servers, and child General) per your example
    Write-Info "Creating Computer Target Groups: 'Servers' and child 'General'..."
    $groups = $wsus.GetComputerTargetGroups()
    if (-not ($groups | Where-Object Name -eq 'Servers')) {
        $wsus.CreateComputerTargetGroup('Servers') | Out-Null
    }
    $parent = ($wsus.GetComputerTargetGroups() | Where-Object Name -eq 'Servers')
    if (-not ($groups | Where-Object Name -eq 'General')) {
        $wsus.CreateComputerTargetGroup("General", $parent) | Out-Null
    }

    # Optional: IIS App Pool stability settings (as in your starter)
    try {
        Write-Info "Applying optional IIS WsusPool recycling tweaks..."
        Import-Module WebAdministration -ErrorAction Stop
        Set-ItemProperty IIS:\AppPools\WsusPool -Name recycling.periodicrestart.privateMemory -Value 2100000
        $time = New-TimeSpan -Hours 4
        Set-ItemProperty IIS:\AppPools\WsusPool -Name recycling.periodicrestart.time -Value $time
        Restart-WebAppPool -Name WsusPool
    } catch {
        Write-Warn "IIS WebAdministration tweaks skipped/failed: $($_.Exception.Message)"
    }

    # Optional (commented): Approve a couple of updates for All Computers (from your starter)
    # Get-WsusUpdate | Select-Object -Skip 100 -First 2 | Approve-WsusUpdate -Action Install -TargetGroupName 'All Computers'

    # Optional (commented): Install .NET 3.5 if source provided (useful for legacy reporting)
    if ($NetFx35Source) {
        try {
            Write-Info "Installing .NET Framework 3.5 from '$NetFx35Source'..."
            Install-WindowsFeature NET-Framework-Core -Source $NetFx35Source -ErrorAction Stop | Out-Null
            Write-Ok ".NET Framework 3.5 installed."
        } catch {
            Write-Warn "Failed to install .NET 3.5: $($_.Exception.Message)"
        }
    } else {
        Write-Info "Skipping .NET 3.5 (no -NetFx35Source provided)."
    }

    Write-Ok "WSUS configuration completed successfully."

    # Remove the one-time Scheduled Task so it doesn't re-run
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Ok "Removed Scheduled Task '$TaskName'."
    }
}
catch {
    Write-Err "FATAL: $($_.Exception.Message)"
    throw
}
finally {
    Stop-Transcript | Out-Null
}