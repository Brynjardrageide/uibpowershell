Import-Module ActiveDirectory

# INPUT CSV
$CsvPath = "C:\Users\Administrator\Documents\csv\brukere.csv"
$Delimiter = ","

# OUTPUT CSV
$OutputCsv = "C:\Users\Administrator\Documents\csv\brukere_output.csv"

# Strong password generator tidliere brukte askii tegn med (39..) til (126..) men det fungerte ikke coden var basert på .net framework som ai ga meg eg lagde det på nytt og etter det passordene ble laget men det var veldig lange fordi den og koden var c# og en string blir set på som en object og alt ble hentet så nå er det fikset med å bruke .ToCharArray() slik at det blir en array og da funker Get-Random -Count number 
function New-StrongPassword {
    param([int]$Length = 12)

    $upper="ABCDEFGHIJKLMNOPQRSTUVWXYZ".ToCharArray()
    $lower="abcdefghijklmnopqrstuvwxyz".ToCharArray()
    $digits="0123456789".ToCharArray()
    $special="!@#$%^&*()-_=+[]{}:;.?".ToCharArray()

    $password = ""
    $password += ($upper | Get-Random -Count 1)
    $password += ($lower | Get-Random -Count 1)
    $password += ($digits | Get-Random -Count 1)
    $password += ($special | Get-Random -Count 1)

    $all = $upper + $lower + $digits + $special
    $password += -join ($all | Get-Random -Count ($Length - 4))

    return -join ($password.ToCharArray() | Sort-Object {Get-Random})
}

# MAP CSV FIELDS
$SyncfieldMap = @{
    EmployeeID="EmployeeID"
    FirstName="GivenName"
    LastName="Surname"
    phone="telephoneNumber"
    ou="ou"
    password="password"
}

# CSV MAPPING FUNCTION
function Get-eployeeFromCsv {
    param ($filePath,$Delimiter,$SyncfieldMap)
    $SyncProperties=$SyncfieldMap.GetEnumerator()
    $properties=foreach($property in $SyncProperties){
        @{Name=$property.Value;Expression=[scriptblock]::Create("`$_.$($property.Key)") }
    }
    Import-Csv -Path $filePath -Delimiter $Delimiter | Select-Object -Property $properties
}

# Read CSV
$Users = Get-eployeeFromCsv -filePath $CsvPath -Delimiter "," -SyncfieldMap $SyncfieldMap

# Prepare output CSV
$OutputData = @()
$OutputData += "GivenName,Surname,Username,Password,Timestamp`n"

foreach ($user in $Users) {
    if (Get-ADUser -LDAPFilter "(employeeID=$($user.EmployeeID))" -ErrorAction SilentlyContinue) {
        Write-Host "User with EmployeeID $($user.EmployeeID) already exists. Skipping..." -ForegroundColor Yellow
        $OutputData += "$($user.GivenName),$($user.Surname),EXISTS,EXISTS,$(Get-Date)`n"
        continue
    }else {
        Write-Host "Creating user: $($user.GivenName) $($user.Surname)" -ForegroundColor Green
        # Default OU
        if ([string]::IsNullOrWhiteSpace($user.ou)) {
            $user.ou = "brukere"
        }
      
        $OU = "OU=$($user.ou),OU=users,OU=drageideou,DC=drageide,DC=com"
        $Domain = "drageide.com"
      
        # Username: first 2 + first 3
        $sam = ($user.GivenName.Substring(0,[Math]::Min(2,$user.GivenName.Length)) +
                $user.Surname.Substring(0,[Math]::Min(3,$user.Surname.Length)) ).ToLower()
      
        # Unique username handling
        $originalSam = $sam
        $i = 1
        while (Get-ADUser -LDAPFilter "(sAMAccountName=$sam)" -ErrorAction SilentlyContinue) {
            $sam = "$originalSam$i"
            $i++
        }
      
        # PASSWORD SELECTION
        if ([string]::IsNullOrWhiteSpace($user.password)) {
            $Password = New-StrongPassword 
        } else {
            $Password = $user.password
        }
      
        # Create user
        New-ADUser `
            -EmployeeID $user.EmployeeID `
            -Name "$($user.GivenName) $($user.Surname)" `
            -UserPrincipalName "$($user.GivenName).$($user.Surname)@$Domain" `
            -GivenName $user.GivenName `
            -Surname $user.Surname `
            -SamAccountName $sam `
            -Path $OU `
            -EmailAddress "$($user.GivenName).$($user.Surname)@$Domain" `
            -AccountPassword (ConvertTo-SecureString $Password -AsPlainText -Force) `
            -Enabled $true
      
        # Log output
        $OutputData += "$($user.GivenName),$($user.Surname),$sam,$Password,$(Get-Date)`n"
    }
    
}

# Write output file
$dir = Split-Path $OutputCsv -Parent
if (!(Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force }

$OutputData | Out-File -FilePath $OutputCsv -Encoding UTF8 -Force

# Secure output file
icacls $OutputCsv /inheritance:r | Out-Null
icacls $OutputCsv /grant:r "*S-1-5-32-544:(F)" "SYSTEM:(F)" | Out-Null
icacls $OutputCsv /remove "Users" "Authenticated Users" "Everyone" | Out-Null

Write-Host "Done! Output saved to $OutputCsv" -ForegroundColor Green