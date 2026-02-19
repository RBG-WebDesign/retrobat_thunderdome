param(
    [switch]$RunEnforcement
)

$ErrorActionPreference = 'Stop'

$taskName = 'RetroBat-EnforceControllerOrder'
$root = 'C:\RetroBat'
$enforceScript = Join-Path $root 'tools\enforce-controller-order.ps1'
$wrapperPath = Join-Path $root 'tools\launch-retrobat-with-controller-order.cmd'
$mapPath = Join-Path $root 'system\controller-port-map.json'
$launcherLogPath = Join-Path $root 'emulationstation\emulatorLauncher.log'
$controllerLogPath = Join-Path $root 'logs\controller-order.log'
$raPath = Join-Path $root 'emulators\retroarch\retroarch.cfg'
$raCoreOptionsPath = Join-Path $root 'emulators\retroarch\retroarch-core-options.cfg'
$raRemapRootPath = Join-Path $root 'emulators\retroarch\config\remaps'
$startupShortcut = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\RetroBat.lnk'
$desktopShortcut = Join-Path $env:USERPROFILE 'Desktop\RetroBat.lnk'

function New-CheckResult {
    param(
        [string]$Name,
        [bool]$Pass,
        [string]$Detail
    )

    [pscustomobject]@{
        Name = $Name
        Pass = $Pass
        Detail = $Detail
    }
}

function Get-LatestLauncherPaths {
    param([string]$Path)

    if (-not (Test-Path $Path)) { return $null }
    $line = Select-String -Path $Path -Pattern '-p1path\s+"[^"]+".*-p2path\s+"[^"]+"' | Select-Object -Last 1
    if (-not $line) { return $null }

    $text = $line.Line
    $p1 = ([regex]::Match($text, '-p1path\s+"([^"]+)"')).Groups[1].Value
    $p2 = ([regex]::Match($text, '-p2path\s+"([^"]+)"')).Groups[1].Value

    [pscustomobject]@{
        RawLine = $text
        Player1Path = $p1
        Player2Path = $p2
    }
}

function Get-ConfigValue {
    param(
        [string]$Path,
        [string]$Key
    )

    if (-not (Test-Path $Path)) { return $null }
    $line = Select-String -Path $Path -Pattern ('^\s*' + [regex]::Escape($Key) + '\s*=\s*(.+)\s*$') | Select-Object -Last 1
    if (-not $line) { return $null }
    return ([regex]::Match($line.Line, '^\s*[^=]+\s*=\s*"?([^"]*)"?\s*$')).Groups[1].Value
}

$results = New-Object System.Collections.Generic.List[object]

if ($RunEnforcement) {
    $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $enforceScript) -Wait -PassThru
    $results.Add((New-CheckResult -Name 'Enforcement run' -Pass ($proc.ExitCode -eq 0) -Detail ("ExitCode={0}" -f $proc.ExitCode)))
}

$wrapperExists = Test-Path $wrapperPath
$results.Add((New-CheckResult -Name 'Launch wrapper exists' -Pass $wrapperExists -Detail $wrapperPath))

$task = $null
try {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
} catch {
    $task = $null
}

if (-not $task) {
    $results.Add((New-CheckResult -Name 'Scheduled task exists' -Pass $false -Detail "Missing task '$taskName'"))
} else {
    $startupTrigger = @($task.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskBootTrigger' })
    $taskAction = @($task.Actions | Where-Object { $_.Execute -match 'powershell\.exe' -and $_.Arguments -match [regex]::Escape($enforceScript) })
    $isSystem = ($task.Principal.UserId -eq 'SYSTEM')
    $isHighest = ([string]$task.Principal.RunLevel -eq 'Highest')
    $hasDelay = ($startupTrigger.Count -gt 0 -and [string]$startupTrigger[0].Delay -eq 'PT5S')

    $results.Add((New-CheckResult -Name 'Scheduled task exists' -Pass $true -Detail $taskName))
    $results.Add((New-CheckResult -Name 'Task trigger is AtStartup' -Pass ($startupTrigger.Count -gt 0) -Detail ("TriggerCount={0}" -f $startupTrigger.Count)))
    $results.Add((New-CheckResult -Name 'Task delay is 5 seconds' -Pass $hasDelay -Detail ("Delay={0}" -f $(if ($startupTrigger.Count -gt 0) { [string]$startupTrigger[0].Delay } else { 'N/A' }))))
    $results.Add((New-CheckResult -Name 'Task runs as SYSTEM' -Pass $isSystem -Detail ("UserId={0}" -f $task.Principal.UserId)))
    $results.Add((New-CheckResult -Name 'Task runs highest privileges' -Pass $isHighest -Detail ("RunLevel={0}" -f $task.Principal.RunLevel)))
    $results.Add((New-CheckResult -Name 'Task action uses enforcement script' -Pass ($taskAction.Count -gt 0) -Detail ("ActionCount={0}" -f $taskAction.Count)))
}

$startupPass = $false
$startupDetail = "Missing startup shortcut: $startupShortcut"
if (Test-Path $startupShortcut) {
    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($startupShortcut)
    $startupPass = ([string]$shortcut.TargetPath -ieq $wrapperPath)
    $startupDetail = ("TargetPath={0}" -f $shortcut.TargetPath)
}
$results.Add((New-CheckResult -Name 'Startup shortcut uses launch wrapper' -Pass $startupPass -Detail $startupDetail))

$desktopPass = $true
$desktopDetail = "Desktop shortcut missing (acceptable): $desktopShortcut"
if (Test-Path $desktopShortcut) {
    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($desktopShortcut)
    $desktopPass = ([string]$shortcut.TargetPath -ieq $wrapperPath)
    $desktopDetail = ("TargetPath={0}" -f $shortcut.TargetPath)
}
$results.Add((New-CheckResult -Name 'Desktop shortcut uses launch wrapper' -Pass $desktopPass -Detail $desktopDetail))

$mapValid = $false
$mapDetail = "Missing map: $mapPath"
$map = $null
if (Test-Path $mapPath) {
    $map = Get-Content -Raw $mapPath | ConvertFrom-Json
    $hasP1 = -not [string]::IsNullOrWhiteSpace([string]$map.Player1.LocationPath)
    $hasP2 = -not [string]::IsNullOrWhiteSpace([string]$map.Player2.LocationPath)
    $distinct = ([string]$map.Player1.LocationPath -ne [string]$map.Player2.LocationPath)
    $mapValid = $hasP1 -and $hasP2 -and $distinct
    $mapDetail = ("P1={0}; P2={1}; Distinct={2}" -f [string]$map.Player1.LocationPath, [string]$map.Player2.LocationPath, $distinct)
}
$results.Add((New-CheckResult -Name 'Map has distinct Player1/Player2 LocationPaths' -Pass $mapValid -Detail $mapDetail))

$raAutoDetect = Get-ConfigValue -Path $raPath -Key 'input_autodetect_enable'
$results.Add((New-CheckResult -Name 'RetroArch autodetect enabled' -Pass ($raAutoDetect -eq 'true') -Detail ("input_autodetect_enable={0}" -f $(if ($null -eq $raAutoDetect) { 'missing' } else { $raAutoDetect }))))

$raP1Index = Get-ConfigValue -Path $raPath -Key 'input_player1_joypad_index'
$raP2Index = Get-ConfigValue -Path $raPath -Key 'input_player2_joypad_index'
$results.Add((New-CheckResult -Name 'RetroArch Player1 index pinned' -Pass ($raP1Index -eq '0') -Detail ("input_player1_joypad_index={0}" -f $(if ($null -eq $raP1Index) { 'missing' } else { $raP1Index }))))
$results.Add((New-CheckResult -Name 'RetroArch Player2 index pinned' -Pass ($raP2Index -eq '1') -Detail ("input_player2_joypad_index={0}" -f $(if ($null -eq $raP2Index) { 'missing' } else { $raP2Index }))))

$gp1Device = Get-ConfigValue -Path $raCoreOptionsPath -Key 'genesis_plus_gx_player1_device'
$gp2Device = Get-ConfigValue -Path $raCoreOptionsPath -Key 'genesis_plus_gx_player2_device'
$results.Add((New-CheckResult -Name 'Genesis Plus GX Player1 device is auto' -Pass ($gp1Device -eq 'auto') -Detail ("genesis_plus_gx_player1_device={0}" -f $(if ($null -eq $gp1Device) { 'missing' } else { $gp1Device }))))
$results.Add((New-CheckResult -Name 'Genesis Plus GX Player2 device is auto' -Pass ($gp2Device -eq 'auto') -Detail ("genesis_plus_gx_player2_device={0}" -f $(if ($null -eq $gp2Device) { 'missing' } else { $gp2Device }))))

$remapConflicts = @()
if (Test-Path $raRemapRootPath) {
    $remapFiles = @(Get-ChildItem -Path $raRemapRootPath -File -Recurse -ErrorAction SilentlyContinue)
    if ($remapFiles.Count -gt 0) {
        $remapConflicts = @($remapFiles | Select-String -Pattern '^\s*(input_player1_joypad_index|input_player2_joypad_index|input_autodetect_enable|input_remap_binds_enable)\s*=' -CaseSensitive -ErrorAction SilentlyContinue)
    }
}
$results.Add((New-CheckResult -Name 'No remap files override controller assignment keys' -Pass ($remapConflicts.Count -eq 0) -Detail ("Conflicts={0}" -f $remapConflicts.Count)))

$launcher = Get-LatestLauncherPaths -Path $launcherLogPath
if (-not $launcher) {
    $results.Add((New-CheckResult -Name 'Launcher log has p1/p2 paths' -Pass $false -Detail "No -p1path/-p2path line in $launcherLogPath"))
} else {
    $results.Add((New-CheckResult -Name 'Launcher log has p1/p2 paths' -Pass $true -Detail ("P1={0}; P2={1}" -f $launcher.Player1Path, $launcher.Player2Path)))
    if ($map) {
        $matches = ([string]$launcher.Player1Path -eq [string]$map.Player1.DevicePath) -and ([string]$launcher.Player2Path -eq [string]$map.Player2.DevicePath)
        $results.Add((New-CheckResult -Name 'Launcher p1/p2 match mapped devices' -Pass $matches -Detail ("MapP1={0}; MapP2={1}" -f [string]$map.Player1.DevicePath, [string]$map.Player2.DevicePath)))
    }
}

$logPass = Test-Path $controllerLogPath
$results.Add((New-CheckResult -Name 'Controller log exists' -Pass $logPass -Detail $controllerLogPath))

foreach ($result in $results) {
    $status = if ($result.Pass) { 'PASS' } else { 'FAIL' }
    Write-Output ("[{0}] {1}: {2}" -f $status, $result.Name, $result.Detail)
}

$failed = @($results | Where-Object { -not $_.Pass })
if ($failed.Count -gt 0) {
    exit 1
}

exit 0
