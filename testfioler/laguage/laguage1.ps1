# laguage1.ps1
# Installs Norwegian (Bokmål) keyboard for the current user if not already present.
# Uses Get/Set-WinUserLanguageList (available in modern Windows PowerShell).

$desiredTag = 'nb-NO'  # Norwegian Bokmål

try {
    $current = Get-WinUserLanguageList -ErrorAction Stop
} catch {
    Write-Error "Unable to read current user language list: $_"
    exit 1
}

if ($current.LanguageTag -contains $desiredTag) {
    Write-Output "Norwegian ($desiredTag) is already installed."
    exit 0
}

# Create language entry and append to existing list
try {
    $toAdd = New-WinUserLanguageList $desiredTag
    $merged = $current + $toAdd
    Set-WinUserLanguageList -LanguageList $merged -Force -ErrorAction Stop
    Write-Output "Norwegian ($desiredTag) added. Verifying..."
} catch {
    Write-Error "Failed to add Norwegian language: $_"
    exit 1
}

# Verify installation
try {
    $after = Get-WinUserLanguageList -ErrorAction Stop
    if ($after.LanguageTag -contains $desiredTag) {
        Write-Output "Verified: Norwegian ($desiredTag) is installed."
        exit 0
    } else {
        Write-Error "Verification failed: Norwegian not found after installation."
        exit 1
    }
} catch {
    Write-Error "Unable to verify language list: $_"
    exit 1
}