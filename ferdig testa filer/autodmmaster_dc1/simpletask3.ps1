# Variables¨
# Domain and NetBIOS names change as needed | i changed it to what it will be in production soon
$DOMAIN = "drageide.com"
$NETBIOSDOMAIN = "DRAGEIDE"
# Secure password for Dc1 promotion chould change | and not be hardcoded in production environment
$SecurePass = ConvertTo-SecureString "Passord01!" -AsPlainText -Force


# Function to promote to domain controller
function tasklaterdm {
    # Install AD DS and DNS roles | change as needed | and or other servers
    Install-WindowsFeature -Name AD-Domain-Services, DNS -IncludeManagementTools 

    # Promote the server to a domain controller | change as needed | and or other servers
    # does not require reboot on completion as we will handle it later
    Install-ADDSForest `
        -DomainName $DOMAIN `
        -DomainNetbiosName $NETBIOSDOMAIN `
        -SafeModeAdministratorPassword $SecurePass `
        -Force `
        -NoRebootOnCompletion

    # Remove the scheduled task after promotion | needed for stoping it from running again
    Unregister-ScheduledTask -TaskName "Promote to DC" -Confirm:$false
    shutdown.exe /r /t 0 # Restart the server to complete the promotion
}

# Call the function
tasklaterdm