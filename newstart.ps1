#variables for later use
#these variables will be used to set the ip address and computer name
#this is the prework for the domain controller
$varipadress = Read-Host "Enter the IP address"
$varComputername = Read-Host "Enter the computer name"
$deafaultgateway = Read-Host "Enter the default gateway"
#when i promt the server
$DOMAIN = Read-Host "Enter the domain name for organization"
$NETBIOSDOMAIN = Read-Host "Enter the NetBIOS name for the domain. MAKE IT THE SAME ALL UPPER CASE AND NO DOTS OR TOP DOMAIN"

#scheduled task to renamaing and setting ip address
$Action = (New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-command `"New-NetIPAddress -InterfaceAlias 'Ethernet' -IPAddress '$varipadress' -PrefixLength 24 -DefaultGateway '$deafaultgateway'"), (New-ScheduledTaskAction -Execute "powershell2.exe" -Argument"-command `"Rename-Computer -NewName '$varComputername' -Force -Restart`"")
$acions = (New-ScheduledTaskAction -Execute powershell3.exe -Argument "-command `"Install-WindowsFeature -Name AD-Domain-Services, DNS -IncludeManagementTools`""), (New-ScheduledTaskAction -Execute powershell4.exe -Argument "-command `"Install-Module ADDSDeployment`""), (New-ScheduledTaskAction -Execute powershell5.exe -Argument "-command `"Install-ADDSForest -DomainName '$DOMAIN' -DomainNetbiosName '$NETBIOSDOMAIN' -SafeModeAdministratorPassword (Read-Host -AsSecureString 'Enter the DSRM password') -Force -NoRebootOnCompletion`""), (New-ScheduledTaskAction -Execute powershell6.exe -Argument "-command `"Restart-Computer`"")
# Define the trigger: run once, 1 minute from now
$Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1)
# Define the principal: run as the current user
$Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
# Register the scheduled task
Register-ScheduledTask -TaskName "NewStartTask" -Action $Action -Trigger $Trigger -Principal $Principal
Register-ScheduledTask -TaskName "NewStartTask2" -Action $acions -Trigger $Trigger -Principal $Principal