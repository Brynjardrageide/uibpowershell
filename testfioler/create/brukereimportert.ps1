
# Krever Active Directory-modulen
Import-Module ActiveDirectory -ErrorAction Stop

function Get-EmployeeFromCsv {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$Delimiter,

        # Kart: CSV-kolonnenavn -> ønsket egenskapsnavn i objektet
        [Parameter(Mandatory)]
        [hashtable]$SyncfieldMap
    )

    try {
        # Gjør Select-Object-kalkulerte egenskaper basert på kartet
        $properties = foreach ($kv in $SyncfieldMap.GetEnumerator()) {
            @{
                Name      = $kv.Value
                Expression = [scriptblock]::Create("`$_.$($kv.Key)")
            }
        }

        Import-Csv -Path $FilePath -Delimiter $Delimiter -ErrorAction Stop |
            Select-Object -Property $properties
    }
    catch {
        Write-Error "Det oppstod en feil ved lesing av CSV: $($_.Exception.Message)"
        throw
    }
}

# >>> Sørg for at disse CSV-kolonnene faktisk finnes i filen:
# EmployeeID, FirstName, LastName
$SyncfieldMap = @{
    EmployeeID = "EmployeeID"  # CSV -> objekt.Property
    FirstName  = "GivenName"
    LastName   = "Surname"
}

# Konfigurasjon
$OU     = "OU=brukere,OU=users,OU=drageideou's,DC=drageide,DC=com"
$Domain = "drageide.com"

# Valider at OU finnes (valgfritt, men nyttig)
try {
    $ouObj = Get-ADOrganizationalUnit -LDAPFilter "(distinguishedName=$OU)" -ErrorAction Stop
} catch {
    throw "Fant ikke OU: $OU. Kontroller staving og hierarki. Feil: $($_.Exception.Message)"
}

# Les CSV
$userinfo = Get-EmployeeFromCsv -FilePath ".\testfioler\create\users.csv" -Delimiter "," -SyncfieldMap $SyncfieldMap

foreach ($user in $userinfo) {

    # Bygg e-post og UPN (rens for mellomrom og spesialtegn, og lower-case)
    $given   = ($user.GivenName -replace '\s+', '').ToLower()
    $sur     = ($user.Surname   -replace '\s+', '').ToLower()
    $email   = "$given.$sur@$Domain"
    
    # Lag en samAccountName (maks 20 tegn typisk). Her: fornavn.etternavn trunkert.
    $samBase = "$given.$sur"
    $sam     = if ($samBase.Length -gt 20) { $samBase.Substring(0,20) } else { $samBase }

    $upn     = "$sam@$Domain"  # alternativt $email hvis UPN skal matche e-post

    $newUserParams = @{
        EmployeeID            = $user.EmployeeID
        GivenName             = $user.GivenName
        Surname               = $user.Surname
        Name                  = "$($user.GivenName) $($user.Surname)"
        DisplayName           = "$($user.GivenName) $($user.Surname)"
        Path                  = $OU
        EmailAddress          = $email
        SamAccountName        = $sam
        UserPrincipalName     = $upn
        AccountPassword       = (ConvertTo-SecureString "Passord01!" -AsPlainText -Force)
        Enabled               = $true
        PasswordNeverExpires  = $false
        ChangePasswordAtLogon = $false
    }

    try {
        New-ADUser @newUserParams -ErrorAction Stop
        Write-Host "Opprettet bruker: $($newUserParams.Name) (SAM: $sam, UPN: $upn)" -ForegroundColor Green
    }
    catch {
        Write-Error "Feil ved oppretting av bruker $($newUserParams.Name): $($_.Exception.Message)"
       }
}