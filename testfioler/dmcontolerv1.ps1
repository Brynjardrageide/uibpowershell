# place fotr variables wich i wil use later

#this variables will be used to set the ip adress and computer name

#dette er forhonds arbeide til domene controlleren

$varipadress = Read-Host "Enter the IP address" 
$varComputername = Read-Host "Enter the computer name"
$deafaultgateway = Read-Host "Enter the default gateway"

# Iimens jeg promonterer serveren
$DOMAIN = Read-Host "Enter the domain name for organization"
$NETBIOSDOMAIN = Read-Host "Enter the NetBIOS name for the domain. SÅ DET SAME ALL UPPER CASE OG INGEN PUNKTUM NOE TOP DOMENE"

#PROMENTERING AV SEREVER

#this will set the computer name and ip adress sammen med default gateway
Rename-Computer -NewName $varComputername -Force -Restart
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress $varipadress -PrefixLength 24 -DefaultGateway $deafaultgateway

# klargjør serveren for å bli en domene controller

#Install the AD DS role
Install-WindowsFeature -Name AD-Domain-Services, DNS -IncludeManagementTools 

# import the ADDSDeployment module før seting av domenet
Install-Module ADDSDeployment

#Promote the server to a domain controller
Install-ADDSForest`
    -DomainName $DOMAIN `
    -DomainNetbiosName $NETBIOSDOMAIN `
    -SafeModeAdministratorPassword (Read-Host -AsSecureString "Enter the DSRM password") `
    -Force `
    -NoRebootOnCompletion`


# Wait for the promotion process to complete
foreach ($i in 1..20) {
    Write-Host "Waiting for 10 seconds to ensure the promotion process completes..."
    Start-Sleep -Seconds 10
}


#Restart the server to complete the promotion
Restart-Computer
# End of script