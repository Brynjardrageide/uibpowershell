# This script creates a simple scheduled task that writes "Hello World" to a text file

# Define the action: run PowerShell to write "Hello World" to a file
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-Command `"Add-Content -Path '$env:USERPROFILE\hello.txt' -Value 'Hello World'`""

# Define the trigger: run once, 1 minute from now
$Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1)

# Define the principal: run as the current user
$Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive

# Register the scheduled task
Register-ScheduledTask -TaskName "HelloWorldTask" -Action $Action -Trigger $Trigger -Principal $Principal

# The scheduled task will run once and create hello.txt with "Hello World" in your user folder