$ErrorActionPreference = 'Stop'

# Self-elevating installer for RetroBat controller order startup task
$taskName = 'RetroBat-EnforceControllerOrder'
$scriptPath = 'C:\RetroBat\tools\enforce-controller-order.ps1'
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Self elevate if needed
if (-not (Test-IsAdmin)) {
    Write-Host 'Elevating to Administrator...'
    Start-Process $psExe `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
        -Verb RunAs
    exit
}

Write-Host 'Running with Administrator privileges.'

if (-not (Test-Path $scriptPath)) {
    throw "Missing enforcement script: $scriptPath"
}

# Build task action
$action = New-ScheduledTaskAction `
    -Execute $psExe `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""

# Build trigger (at startup + 5 second delay for parity with existing verifier)
$trigger = New-ScheduledTaskTrigger -AtStartup
$trigger.Delay = 'PT5S'

# Build principal (SYSTEM)
$principal = New-ScheduledTaskPrincipal `
    -UserId 'SYSTEM' `
    -LogonType ServiceAccount `
    -RunLevel Highest

# Build settings
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable

# Remove existing task if present
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Removing existing task: $taskName"
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# Register task
Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings | Out-Null

Write-Host "SUCCESS: Scheduled task created: $taskName"

# Verify
Get-ScheduledTask -TaskName $taskName | Format-List TaskName, State, Principal
