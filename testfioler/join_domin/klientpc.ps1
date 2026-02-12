# Define variables
$domain = "drageide.com"
$username = "Administrator"
$password = "Passord01!" | ConvertTo-SecureString -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($username, $password)
$pupath = "ou=klienter,ou=computers,ou=drageideou,dc=drageide,dc=com"

# Join the domain
Add-Computer -DomainName $domain -Credential $credential -Restart -OUPath $pupath
