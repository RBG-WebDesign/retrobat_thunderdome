$ErrorActionPreference = 'Stop'

$taskName = 'RetroBat-EnforceControllerOrder'
$legacyTaskName = 'RetroBat-EnforceControllerOrder-Startup'
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$scriptPath = 'C:\RetroBat\tools\enforce-controller-order.ps1'
$action = ('"{0}" -NoProfile -ExecutionPolicy Bypass -File "{1}"' -f $psExe, $scriptPath)

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error 'Run this script from an elevated PowerShell session (Administrator).'
}

function Invoke-SchTasks {
    param([string[]]$Arguments)
    $prev = $ErrorActionPreference
    try {
        # schtasks writes operational messages to stderr; use exit code for control flow.
        $ErrorActionPreference = 'Continue'
        $output = & schtasks.exe @Arguments 2>&1
        foreach ($line in @($output)) {
            Write-Host $line
        }
        return [int]$LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $prev
    }
}

$deleteLegacyArgs = @('/Delete', '/TN', $legacyTaskName, '/F')
$legacyDeleteCode = Invoke-SchTasks -Arguments $deleteLegacyArgs
if ($legacyDeleteCode -eq 0) {
    Write-Output "Deleted legacy task: $legacyTaskName"
}

$createArgs = @(
    '/Create'
    '/TN', $taskName
    '/SC', 'ONSTART'
    '/DELAY', '0000:05'
    '/TR', $action
    '/RU', 'SYSTEM'
    '/RL', 'HIGHEST'
    '/F'
)

$createCode = Invoke-SchTasks -Arguments $createArgs
if ($createCode -ne 0) {
    throw "Failed to create task '$taskName'. schtasks.exe exit code: $createCode"
}

$queryArgs = @('/Query', '/TN', $taskName, '/FO', 'LIST', '/V')
$queryCode = Invoke-SchTasks -Arguments $queryArgs
if ($queryCode -ne 0) {
    throw "Task '$taskName' creation may have failed verification. schtasks.exe /Query exit code: $queryCode"
}

Write-Output "Created and verified task: $taskName"
