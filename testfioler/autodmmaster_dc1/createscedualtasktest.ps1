
$Action = New-ScheduledTaskAction -Execute "cmd.exe"
$Trigger = New-ScheduledTaskTrigger -Daily -At 9am
$TaskName = "test"
$descripion = "this is a test"

# registre the scheduled task action and trigger
Register-ScheduledTask -Action $Action -Trigger $Trigger -TaskName $TaskName -Description $descripion 