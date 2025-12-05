# importererbrukere fra CSV-fil og legger dem til i Active Directory
# csv-filen skal ha kolonnene: eployeeid, FirstName, LastName
function Get-eployeeFromCsv {
    [cmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$filePath,
        [Parameter(Mandatory)]
        [string]$Delimiter,
        [Parameter(Mandatory)]
        [hashtable]$SyncfieldMap
    )
    
    try {
        $SyncProperties=$SyncfieldMap.GetEnumerator()
        $properties=foreach($property in $SyncProperties){
            @{Name=$property.Value;Expression=[scriptblock]::Create("`$_.$($property.Key)")}
        }

        Import-Csv -Path $filePath -Delimiter $Delimiter | Select-Object -Property $properties
    }
    catch {
        <#Do this if a terminating exception happens#>
        write-error "An error occurred: $_.Exception.Message"
    }

}
$SyncfieldMap = @{
    EmployeeID="EmployeeID"
    FirstName="GivenName"
    LastName="Surname"
}
Get-eployeeFromCsv -filePath ".\testfioler\create\users.csv" -Delimiter "," -SyncfieldMap $SyncfieldMap