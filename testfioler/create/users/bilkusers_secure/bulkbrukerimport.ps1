<# -----------------------------------------------------------
 Bulk create AD users from CSV and save username/password list
 Author: Brynjar (cleaned & fixed)
------------------------------------------------------------ #>

# Ensure AD cmdlets are loaded
Import-Module ActiveDirectory

# ----------------- SETTINGS -----------------
# CSV to read FROM
$CsvPath      = "C:\Users\Administrator\Documents\csv\brukere.csv"
$Delimiter    = ","

# CSV to write TO (username/password documentation)
$filePathCsv  = "C:\Users\Administrator\Documents\csv\brukere_created_credentials.csv"

# Domain + base OU
$Domain       = "drageide.com"
$BaseOU       = "OU=users,OU=drageideou,DC=drageide,DC=com"   # must exist

# ----------------- HELPER: safe substring -----------------
function Get-SafeSubstring {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][int]$Length
    )
    if ([string]::IsNullOrEmpty($Text)) { return "" }
    if ($Text.Length -lt $Length) { return $Text } else { return $Text.Substring(0,$Length) }
}

# ----------------- HELPER: map CSV -> object -----------------
# csv-filen skal ha kolonnene (eksempel): EmployeeID, FirstName, LastName, phone, ou, password
function Get-EmployeeFromCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string]$Delimiter,
        [Parameter(Mandatory)][hashtable]$SyncfieldMap
    )

    try {
        $SyncProperties = $SyncfieldMap.GetEnumerator()
        $properties = foreach ($property in $SyncProperties) {
            @{ Name = $property.Value; Expression = [scriptblock]::Create("`$_.$($property.Key)") }
        }
        Import-Csv -Path $FilePath -Delimiter $Delimiter | Select-Object -Property $properties
    }
    catch {
        Write-Error "An error occurred while reading CSV: $($_.Exception.Message)"
        throw
    }
}

# Map CSV columns (left side) => Output property names (right side)
$SyncfieldMap = @{
    EmployeeID = "EmployeeID"        # CSV: EmployeeID
    FirstName  = "GivenName"         # CSV: FirstName
    LastName   = "Surname"           # CSV: LastName
    phone      = "telephoneNumber"   # CSV: phone
    ou         = "ou"                # CSV: ou (optional)
    password   = "password"          # CSV: password (optional)
}

# ----------------- READ USERS -----------------
if (-not (Test-Path -Path $CsvPath)) {
    throw "CSV file not found: $CsvPath"
}

$users = Get-EmployeeFromCsv -FilePath $CsvPath -Delimiter $Delimiter -SyncfieldMap $SyncfieldMap

if (-not $users) {
    throw "No rows returned from CSV. Check delimiter and column names."
}

# ----------------- PREPARE RESULT LIST -----------------
$results = New-Object System.Collections.Generic.List[object]

# ----------------- CREATE USERS -----------------
foreach ($user in $users) {

    # Default OU if none supplied
    if ([string]::IsNullOrEmpty($user.ou)) {
        $user.ou = "brukere"
    }

    # Build full OU path and UPN/email
    $OU     = "OU=$($user.ou),$BaseOU"
    $upn    = "$($user.GivenName).$($user.Surname)@$Domain"
    $email  = $upn

    # Generate password if not provided
    $randPassword = if ([string]::IsNullOrEmpty($user.password)) {
        # At least 12 chars, include special characters; append extra digits and specials
        $base = [System.Web.Security.Membership]::GeneratePassword(12,2)
        $digits = -join ((48..57) | Get-Random -Count 2 | ForEach-Object {[char]$_})
        $specials = (33..47) + (58..64) + (91..96) + (123..126)
        $sp = -join ($specials | Get-Random -Count 2 | ForEach-Object {[char]$_})
        $base + $digits + $sp
    } else {
        $user.password
    }

    # Username (sAMAccountName) = 2 first of GivenName + 3 first of Surname (guarded)
    $sam = (Get-SafeSubstring -Text $user.GivenName -Length 2) + (Get-SafeSubstring -Text $user.Surname -Length 3)
    $sam = $sam.ToLower()

    # Ensure uniqueness: if exists, append a number
    $originalSam = $sam
    $i = 1
    while (Get-ADUser -LDAPFilter "(sAMAccountName=$sam)" -ErrorAction SilentlyContinue) {
        $sam = "{0}{1}" -f $originalSam, $i
        $i++
    }

    # Build hashtable for optional attributes
    $otherAttributes = @{}
    if ($user.telephoneNumber) { $otherAttributes['telephoneNumber'] = $user.telephoneNumber }

    try {
        New-ADUser `
            -EmployeeID $user.EmployeeID `
            -UserPrincipalName $upn `
            -GivenName $user.GivenName `
            -Surname $user.Surname `
            -Name "$($user.GivenName) $($user.Surname)" `
            -SamAccountName $sam `
            -Path $OU `
            -EmailAddress $email `
            -OtherAttributes $otherAttributes `
            -AccountPassword (ConvertTo-SecureString $randPassword -AsPlainText -Force) `
            -Enabled $true `
            -PasswordNeverExpires $false `
            -ChangePasswordAtLogon $false

        $results.Add([PSCustomObject]@{
            GivenName = $user.GivenName
            Surname   = $user.Surname
            Username  = $sam
            UPN       = $upn
            OU        = $OU
            Password  = $randPassword
            Created   = Get-Date
            Status    = "Created"
        })
    }
    catch {
        $results.Add([PSCustomObject]@{
            GivenName = $user.GivenName
            Surname   = $user.Surname
            Username  = $sam
            UPN       = $upn
            OU        = $OU
            Password  = $randPassword
            Created   = Get-Date
            Status    = "FAILED: $($_.Exception.Message)"
        })
        Write-Warning "Failed to create user [$($user.GivenName) $($user.Surname)]: $($_.Exception.Message)"
    }
}

# ----------------- WRITE RESULT CSV -----------------
# Ensure target folder exists
$dir = Split-Path -Path $filePathCsv -Parent
if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }

# Write results (header included automatically)
$results | Export-Csv -Path $filePathCsv -NoTypeInformation -Encoding UTF8 -Force

# ----------------- LOCK DOWN RESULT FILE PERMISSIONS -----------------
try {
    # Remove inheritance
    icacls "$filePathCsv" /inheritance:r | Out-Null

    # Grant full control ONLY to local Administrator and SYSTEM
    icacls "$filePathCsv" /grant:r "Administrator:(F)" "SYSTEM:(F)" | Out-Null

    # Remove broad groups if present
    icacls "$filePathCsv" /remove "Users" "Authenticated Users" "Everyone" | Out-Null
}
catch {
    Write-Warning "Failed to set file ACL on $filePathCsv : $($_.Exception.Message)"
}

Write-Host "`nDone. Results saved to: $filePathCsv" -ForegroundColor Green