# Define variables
$domain = "drageide.com"
$username = "Administrator"
$password = "Passord01!" | ConvertTo-SecureString -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($username, $password)

# Join the domain
Add-Computer -DomainName $domain -Credential $credential -Restart

<#
    System.Management.Automation.PSCredential is a PowerShell object that stores security credentials, specifically a username and a secure password. It is used to authenticate and authorize actions, allowing scripts to run under the identity of the user associated with the credentials. You can create a PSCredential object using cmdlets like Get-Credential or programmatically, and it can be stored in a variable for repeated use. 
    https://www.youtube.com/watch?v=j3PVxkzkGx0
    got it from ai
#>