$ErrorActionPreference = 'Stop'

$root = 'C:\RetroBat'
$modulePath = Join-Path $root 'tools\modules\ControllerOrder.psm1'
$mapPath = Join-Path $root 'system\controller-port-map.json'
$raPath = Join-Path $root 'emulators\retroarch\retroarch.cfg'
$raCoreOptionsPath = Join-Path $root 'emulators\retroarch\retroarch-core-options.cfg'
$raRemapRootPath = Join-Path $root 'emulators\retroarch\config\remaps'
$esSettingsPath = Join-Path $root 'emulationstation\.emulationstation\es_settings.cfg'
$launcherLogPath = Join-Path $root 'emulationstation\emulatorLauncher.log'
$logPath = Join-Path $root 'logs\controller-order.log'

Import-Module $modulePath -Force

Write-ControllerLog -LogPath $logPath -Message '--- Enforcement run started ---' | Out-Null

$controllers = @(Get-DragonRiseControllers)
if ($controllers.Count -eq 0) {
    Write-ControllerLog -LogPath $logPath -Level 'WARN' -Message 'No DragonRise controllers detected via PnP at enforcement time.' | Out-Null
} else {
    Write-ControllerLog -LogPath $logPath -Message ("Detected {0} DragonRise controller(s)." -f $controllers.Count) | Out-Null
    foreach ($c in $controllers) {
        Write-ControllerLog -LogPath $logPath -Message ("Detected: Class='{0}', Name='{1}', InstanceId='{2}', DevicePath='{3}', LocationPath='{4}'" -f $c.Class, $c.FriendlyName, $c.InstanceId, $c.DevicePath, $c.LocationPath) | Out-Null
    }
}

$assignment = Get-LatestRetroBatLauncherAssignment -LauncherLogPath $launcherLogPath
if ($assignment) {
    Write-ControllerLog -LogPath $logPath -Message ("Latest launcher paths: P1='{0}', P2='{1}'" -f $assignment.Player1Path, $assignment.Player2Path) | Out-Null
}

$map = Read-ControllerPortMap -MapPath $mapPath
if (-not $map) {
    if (-not $assignment) {
        Write-ControllerLog -LogPath $logPath -Level 'ERROR' -Message 'Cannot create controller map: no existing map and no launcher assignment found.' | Out-Null
        exit 1
    }

    $map = New-ControllerPortMapFromAssignment -Assignment $assignment -Controllers $controllers
    Write-ControllerLog -LogPath $logPath -Message 'Created new controller map from launcher assignment.' | Out-Null
} else {
    Write-ControllerLog -LogPath $logPath -Message 'Loaded existing controller map.' | Out-Null
    $map = Update-MapWithDiscoveredControllers -Map $map -Controllers $controllers -Assignment $assignment
}

Write-ControllerPortMap -Map $map -MapPath $mapPath

if ($map.DegradedMode) {
    Write-ControllerLog -LogPath $logPath -Level 'WARN' -Message ("Degraded mode enabled: {0}" -f $map.DegradedReason) | Out-Null
}

$validation = Test-ControllerMapValidation -Map $map -Controllers $controllers
if ($validation.HasTwoControllers -and $validation.Issues.Count -gt 0) {
    foreach ($issue in $validation.Issues) {
        Write-ControllerLog -LogPath $logPath -Level 'ERROR' -Message ("Validation issue: {0}" -f $issue) | Out-Null
    }
}

$resolvedP1Index = '0'
$resolvedP2Index = '1'

if ($assignment -and $assignment.RawLine) {
    $p1IndexMatch = [regex]::Match([string]$assignment.RawLine, '-p1index\s+(\d+)')
    $p2IndexMatch = [regex]::Match([string]$assignment.RawLine, '-p2index\s+(\d+)')

    if ($p1IndexMatch.Success -and $p2IndexMatch.Success) {
        $pathToIndex = @{}
        if (-not [string]::IsNullOrWhiteSpace([string]$assignment.Player1Path)) {
            $pathToIndex[[string]$assignment.Player1Path] = [string]$p1IndexMatch.Groups[1].Value
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$assignment.Player2Path)) {
            $pathToIndex[[string]$assignment.Player2Path] = [string]$p2IndexMatch.Groups[1].Value
        }

        $mapP1Path = [string]$map.Player1.DevicePath
        $mapP2Path = [string]$map.Player2.DevicePath

        if ($pathToIndex.ContainsKey($mapP1Path)) {
            $resolvedP1Index = [string]$pathToIndex[$mapP1Path]
        }
        if ($pathToIndex.ContainsKey($mapP2Path)) {
            $resolvedP2Index = [string]$pathToIndex[$mapP2Path]
        }
    }
}

if ($resolvedP1Index -eq $resolvedP2Index) {
    $resolvedP1Index = '0'
    $resolvedP2Index = '1'
}

try {
    if (Test-Path $esSettingsPath) {
        [xml]$esXml = Get-Content -Raw $esSettingsPath

        $arcadeModeNode = $esXml.config.string | Where-Object { $_.name -eq 'global.arcade_stick' } | Select-Object -First 1
        $p1StickNode = $esXml.config.string | Where-Object { $_.name -eq 'global.p1_stick_index' } | Select-Object -First 1
        $p2StickNode = $esXml.config.string | Where-Object { $_.name -eq 'global.p2_stick_index' } | Select-Object -First 1

        $arcadeModeEnabled = $arcadeModeNode -and ([string]$arcadeModeNode.value -eq '1')
        $p1StickValue = if ($p1StickNode) { [string]$p1StickNode.value } else { '' }
        $p2StickValue = if ($p2StickNode) { [string]$p2StickNode.value } else { '' }

        if (
            $arcadeModeEnabled -and
            ($p1StickValue -match '^\d+$') -and
            ($p2StickValue -match '^\d+$') -and
            ($p1StickValue -ne $p2StickValue)
        ) {
            $resolvedP1Index = $p1StickValue
            $resolvedP2Index = $p2StickValue
            Write-ControllerLog -LogPath $logPath -Message ("Using EmulationStation global arcade stick indices: P1={0}, P2={1}" -f $resolvedP1Index, $resolvedP2Index) | Out-Null
        }
    }
}
catch {
    Write-ControllerLog -LogPath $logPath -Level 'WARN' -Message ("Failed to read arcade stick index settings from es_settings.cfg: {0}" -f $_.Exception.Message) | Out-Null
}

$raValues = @{
    'input_player1_joypad_index' = $resolvedP1Index
    'input_player2_joypad_index' = $resolvedP2Index
    'input_autodetect_enable'    = 'true'
    'input_remap_binds_enable'   = 'false'
}
Set-UniqueRetroArchKeys -ConfigPath $raPath -Values $raValues
Write-ControllerLog -LogPath $logPath -Message 'RetroArch keys enforced with canonical single entries.' | Out-Null
Write-ControllerLog -LogPath $logPath -Message ("RetroArch launch override prepared: input_player1_joypad_index={0}, input_player2_joypad_index={1}, input_autodetect_enable=true, input_remap_binds_enable=false" -f $resolvedP1Index, $resolvedP2Index) | Out-Null

$coreOptionValues = @{
    'genesis_plus_gx_player1_device' = 'auto'
    'genesis_plus_gx_player2_device' = 'auto'
}
Set-UniqueRetroArchCoreOptionKeys -ConfigPath $raCoreOptionsPath -Values $coreOptionValues
Write-ControllerLog -LogPath $logPath -Message 'RetroArch core options enforced for Genesis Plus GX player device auto assignment.' | Out-Null

$remapCleanup = Remove-ConflictingRetroArchRemapAssignments -RemapRootPath $raRemapRootPath
Write-ControllerLog -LogPath $logPath -Message ("RetroArch remap scan complete: scanned={0}, modified={1}, deleted={2}" -f $remapCleanup.ScannedFiles, $remapCleanup.ModifiedFiles, $remapCleanup.DeletedFiles) | Out-Null
foreach ($path in $remapCleanup.ModifiedPaths) {
    Write-ControllerLog -LogPath $logPath -Message ("Remap adjusted: {0}" -f $path) | Out-Null
}
foreach ($path in $remapCleanup.DeletedPaths) {
    Write-ControllerLog -LogPath $logPath -Message ("Remap deleted (only conflicting keys): {0}" -f $path) | Out-Null
}

if (-not $validation.HasTwoControllers) {
    Write-ControllerLog -LogPath $logPath -Level 'WARN' -Message 'Fewer than two DragonRise controllers detected; skipping assignment rewrite.' | Out-Null
    Write-ControllerLog -LogPath $logPath -Message '--- Enforcement run completed (preserved map due missing controllers) ---' | Out-Null
    exit 0
}

if (-not $validation.CanEnforce) {
    Write-ControllerLog -LogPath $logPath -Level 'ERROR' -Message 'Controller validation failed with two controllers present; refusing to rewrite assignments.' | Out-Null
    Write-ControllerLog -LogPath $logPath -Message '--- Enforcement run completed (failed validation) ---' | Out-Null
    exit 1
}

Write-ControllerLog -LogPath $logPath -Message ("Detected controller assignment: Assigned Player=1, MatchType='{0}', GUID='{1}', LocationPath='{2}', DevicePath='{3}', Name='{4}', InstanceId='{5}'" -f $validation.P1Match.MatchType, [string]$validation.Map.Player1.Guid, [string]$validation.P1Match.Controller.LocationPath, [string]$validation.P1Match.Controller.DevicePath, [string]$validation.P1Match.Controller.FriendlyName, [string]$validation.P1Match.Controller.InstanceId) | Out-Null
Write-ControllerLog -LogPath $logPath -Message ("Detected controller assignment: Assigned Player=2, MatchType='{0}', GUID='{1}', LocationPath='{2}', DevicePath='{3}', Name='{4}', InstanceId='{5}'" -f $validation.P2Match.MatchType, [string]$validation.Map.Player2.Guid, [string]$validation.P2Match.Controller.LocationPath, [string]$validation.P2Match.Controller.DevicePath, [string]$validation.P2Match.Controller.FriendlyName, [string]$validation.P2Match.Controller.InstanceId) | Out-Null

Set-EsSettingsPlayerBindings -EsSettingsPath $esSettingsPath -Map $validation.Map
Write-ControllerLog -LogPath $logPath -Message 'EmulationStation INPUT P1/P2 bindings enforced from validated map.' | Out-Null

$expected = Get-ExpectedPlayerDevicePaths -Map $validation.Map -P1Match $validation.P1Match -P2Match $validation.P2Match
if ([string]::IsNullOrWhiteSpace($expected.Player1) -or [string]::IsNullOrWhiteSpace($expected.Player2)) {
    Write-ControllerLog -LogPath $logPath -Level 'WARN' -Message 'Expected DevicePath values are incomplete; launcher verification is running in degraded mode.' | Out-Null
}

$check = Test-LauncherAssignmentMatchesExpectedPaths -Assignment $assignment -ExpectedP1 $expected.Player1 -ExpectedP2 $expected.Player2
if ($check.Matches) {
    Write-ControllerLog -LogPath $logPath -Message 'Launcher verification passed on first check.' | Out-Null
}
else {
    Write-ControllerLog -LogPath $logPath -Level 'WARN' -Message ("Launcher verification mismatch on first check: {0}" -f $check.Reason) | Out-Null
    Write-ControllerLog -LogPath $logPath -Level 'WARN' -Message 'Re-running discovery and verification pass.' | Out-Null

    Start-Sleep -Milliseconds 800
    $controllers2 = @(Get-DragonRiseControllers)
    $map2 = Update-MapWithDiscoveredControllers -Map $validation.Map -Controllers $controllers2 -Assignment $assignment
    $validation2 = Test-ControllerMapValidation -Map $map2 -Controllers $controllers2

    if ($validation2.CanEnforce) {
        $expected2 = Get-ExpectedPlayerDevicePaths -Map $validation2.Map -P1Match $validation2.P1Match -P2Match $validation2.P2Match
        $latest2 = Get-LatestRetroBatLauncherAssignment -LauncherLogPath $launcherLogPath
        $check2 = Test-LauncherAssignmentMatchesExpectedPaths -Assignment $latest2 -ExpectedP1 $expected2.Player1 -ExpectedP2 $expected2.Player2

        if (-not $check2.Matches) {
            Write-ControllerLog -LogPath $logPath -Level 'ERROR' -Message 'Launcher verification mismatch persists after retry; refusing to proceed.' | Out-Null
            Write-ControllerLog -LogPath $logPath -Message '--- Enforcement run completed (mismatch persists) ---' | Out-Null
            exit 1
        }

        Write-ControllerLog -LogPath $logPath -Message 'Launcher verification passed after retry.' | Out-Null
    }
    else {
        Write-ControllerLog -LogPath $logPath -Level 'ERROR' -Message 'Retry validation failed; refusing to proceed.' | Out-Null
        Write-ControllerLog -LogPath $logPath -Message '--- Enforcement run completed (retry validation failed) ---' | Out-Null
        exit 1
    }
}

Write-ControllerPortMap -Map $validation.Map -MapPath $mapPath
Write-ControllerLog -LogPath $logPath -Message '--- Enforcement run completed ---' | Out-Null
exit 0
