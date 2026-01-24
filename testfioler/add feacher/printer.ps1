Install-WindowsFeature -name  Print-Services -IncludeManagementTools

# Ensure Print and Document Services role is installed
$feature = Get-WindowsFeature -Name Print-Services -ErrorAction SilentlyContinue
if ($null -eq $feature) {
    Write-Host "Print-Services feature not available on this system." -ForegroundColor Yellow
} elseif (-not $feature.Installed) {
    Install-WindowsFeature -Name Print-Services -IncludeManagementTools -Verbose
}

# Variables - adjust to your environment
$PrinterName = "OfficePrinter"
$PrinterIP = "192.168.1.100"
$PortName = "IP_$PrinterIP"
$DriverName = "HP Universal Printing PCL 6"    # must match the installed driver name
$DriverInfPath = "C:\Drivers\HP\hpcu.inf"     # optional: path to .inf to install driver
$ShareName = "OfficePrinter"

# Create TCP/IP port if it doesn't exist
if (-not (Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue)) {
    Add-PrinterPort -Name $PortName -PrinterHostAddress $PrinterIP
}

# Install printer driver if not present and INF path is given
if (-not (Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue)) {
    if (Test-Path $DriverInfPath) {
        pnputil /add-driver $DriverInfPath /install | Out-Null
        Start-Sleep -Seconds 2
    } else {
        Write-Host "Driver '$DriverName' not found and no valid INF provided. Please install driver manually." -ForegroundColor Yellow
    }
}

# Add printer and share it (published in AD for discovery)
if (-not (Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue)) {
    Add-Printer -Name $PrinterName -DriverName $DriverName -PortName $PortName -Shared -ShareName $ShareName -Published
} else {
    Write-Host "Printer '$PrinterName' already exists." -ForegroundColor Cyan
}