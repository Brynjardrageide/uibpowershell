# place fotr variables wich i wil use later

#this variables will be used to set the ip adress and computer name

#dette er forhonds arbeide til domene controlleren

$varipadress = "192.168.1.30"
$varComputername = "DC1"
$deafaultgateway  = "192.168.1.1"


$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "C:\windows\setup\files\simpletask3.ps1"
$Trigger = New-ScheduledTaskTrigger -AtLogOn
$TaskName = "Promote to DC"
Register-ScheduledTask -Action $Action -Trigger $Trigger -TaskName $TaskName -Description "Promote server to domain controller at startup"

#PROMENTERING AV SEREVER

#this will set the computer name and ip adress sammen med default gateway
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress $varipadress -PrefixLength 24 -DefaultGateway $deafaultgateway 
Rename-Computer -NewName $varComputername -Force -Restart
# klargjør serveren for å bli en domene controller



#Restart the server to complete the promotion
Restart-Computer
# End of script