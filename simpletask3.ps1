# Variables
$DOMAIN = "example.com"
$NETBIOSDOMAIN = "EXAMPLE"
$SecurePass = ConvertTo-SecureString "Passord01!" -AsPlainText -Force
function tasklaterdm {
    # Install AD DS and DNS roles
    Install-WindowsFeature -Name AD-Domain-Services, DNS -IncludeManagementTools 

    # Promote the server to a domain controller
    Install-ADDSForest `
        -DomainName $DOMAIN `
        -DomainNetbiosName $NETBIOSDOMAIN `
        -SafeModeAdministratorPassword $SecurePass `
        -Force `
        -NoRebootOnCompletion

    # Remove the scheduled task after promotion
    Unregister-ScheduledTask -TaskName "Promote to DC" -Confirm:$false
    shutdown.exe /r /t 0 
}

# Call the function
tasklaterdm