Set-StrictMode -Version Latest

function Write-ControllerLog {
    param(
        [Parameter(Mandatory=$true)][string]$LogPath,
        [Parameter(Mandatory=$true)][string]$Message,
        [string]$Level = 'INFO'
    )

    $dir = Split-Path -Parent $LogPath
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $line = "{0} [{1}] {2}" -f $stamp, $Level.ToUpperInvariant(), $Message
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
    return $line
}

function Get-LocationPathForInstanceId {
    param([Parameter(Mandatory=$true)][string]$InstanceId)

    try {
        $prop = Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName 'DEVPKEY_Device_LocationPaths' -ErrorAction SilentlyContinue
        if (-not $prop -or -not $prop.Data) { return '' }

        if ($prop.Data -is [System.Array]) {
            return [string]$prop.Data[0]
        }

        return [string]$prop.Data
    } catch {
        return ''
    }
}

function Get-LatestRetroBatLauncherAssignment {
    param([Parameter(Mandatory=$true)][string]$LauncherLogPath)

    if (-not (Test-Path $LauncherLogPath)) { return $null }

    $line = Select-String -Path $LauncherLogPath -Pattern '-p1path\s+"[^"]+".*-p2path\s+"[^"]+"' | Select-Object -Last 1
    if (-not $line) { return $null }

    $text = $line.Line

    function ExtractValue([string]$src, [string]$pattern) {
        $m = [regex]::Match($src, $pattern)
        if ($m.Success) { return $m.Groups[1].Value }
        return ''
    }

    [pscustomobject]@{
        RawLine      = $text
        Player1Path  = ExtractValue $text '-p1path\s+"([^"]+)"'
        Player2Path  = ExtractValue $text '-p2path\s+"([^"]+)"'
        Player1Guid  = ExtractValue $text '-p1guid\s+([0-9A-Fa-f]+)'
        Player2Guid  = ExtractValue $text '-p2guid\s+([0-9A-Fa-f]+)'
        Player1Name  = ExtractValue $text '-p1name\s+"([^"]+)"'
        Player2Name  = ExtractValue $text '-p2name\s+"([^"]+)"'
    }
}

function Get-DragonRiseControllers {
    $results = @()

    if (-not (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue)) {
        return $results
    }

    $present = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue
    if (-not $present) { return $results }

    $usbDevices = $present | Where-Object { $_.InstanceId -like 'USB\VID_0079&PID_0006*' }
    $hidDevices = $present | Where-Object {
        $_.InstanceId -like 'HID\VID_0079&PID_0006*' -or
        $_.FriendlyName -like '*DragonRise*' -or
        $_.FriendlyName -like '*Generic USB Joystick*'
    }

    $seen = @{}
    foreach ($d in @($usbDevices + $hidDevices)) {
        if (-not $d) { continue }

        $id = [string]$d.InstanceId
        if (-not $id) { continue }
        if ($seen.ContainsKey($id)) { continue }
        $seen[$id] = $true

        $devicePath = ''
        if ($id -like 'USB\VID_0079&PID_0006*') {
            $devicePath = $id
        }

        $results += [pscustomobject]@{
            FriendlyName = [string]$d.FriendlyName
            Class        = [string]$d.Class
            InstanceId   = $id
            DevicePath   = $devicePath
            LocationPath = Get-LocationPathForInstanceId -InstanceId $id
            Status       = [string]$d.Status
        }
    }

    return $results
}

function New-EmptyPlayerIdentity {
    [pscustomobject]@{
        LocationPath = ''
        DevicePath   = ''
        Guid         = ''
        Name         = ''
    }
}

function ConvertTo-NormalizedControllerPortMap {
    param($Map)

    $p1 = New-EmptyPlayerIdentity
    $p2 = New-EmptyPlayerIdentity

    if ($Map) {
        $isV2 = ($Map.PSObject.Properties.Name -contains 'SchemaVersion') -and
            ($Map.PSObject.Properties.Name -contains 'Player1') -and
            ($Map.Player1 -and ($Map.Player1.PSObject.Properties.Name -contains 'DevicePath'))

        if ($isV2) {
            $p1.LocationPath = [string]$Map.Player1.LocationPath
            $p1.DevicePath   = [string]$Map.Player1.DevicePath
            $p1.Guid         = [string]$Map.Player1.Guid
            $p1.Name         = [string]$Map.Player1.Name

            $p2.LocationPath = [string]$Map.Player2.LocationPath
            $p2.DevicePath   = [string]$Map.Player2.DevicePath
            $p2.Guid         = [string]$Map.Player2.Guid
            $p2.Name         = [string]$Map.Player2.Name
        }
        else {
            $p1.DevicePath   = [string]$Map.Player1
            $p2.DevicePath   = [string]$Map.Player2
            $p1.LocationPath = [string]$Map.Player1LocationPath
            $p2.LocationPath = [string]$Map.Player2LocationPath
            $p1.Guid         = [string]$Map.Player1Guid
            $p2.Guid         = [string]$Map.Player2Guid
            $p1.Name         = [string]$Map.Player1Name
            $p2.Name         = [string]$Map.Player2Name
        }
    }

    $missingLocation = [string]::IsNullOrWhiteSpace($p1.LocationPath) -or [string]::IsNullOrWhiteSpace($p2.LocationPath)

    [pscustomobject]@{
        SchemaVersion    = 2
        IdentityPriority = @('LocationPath', 'DevicePath')
        Player1          = $p1
        Player2          = $p2
        DegradedMode     = [bool]$missingLocation
        DegradedReason   = if ($missingLocation) { 'LocationPath missing for one or more players; fallback matching may be used.' } else { '' }
        LastUpdated      = if ($Map -and ($Map.PSObject.Properties.Name -contains 'LastUpdated') -and $Map.LastUpdated) { [string]$Map.LastUpdated } else { Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK' }
    }
}

function Read-ControllerPortMap {
    param([Parameter(Mandatory=$true)][string]$MapPath)

    if (-not (Test-Path $MapPath)) { return $null }

    try {
        $raw = Get-Content -Raw $MapPath | ConvertFrom-Json
        return (ConvertTo-NormalizedControllerPortMap -Map $raw)
    } catch {
        return $null
    }
}

function Write-ControllerPortMap {
    param(
        [Parameter(Mandatory=$true)]$Map,
        [Parameter(Mandatory=$true)][string]$MapPath
    )

    $dir = Split-Path -Parent $MapPath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $normalized = ConvertTo-NormalizedControllerPortMap -Map $Map
    $normalized.LastUpdated = Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK'

    $payload = [ordered]@{
        SchemaVersion    = 2
        IdentityPriority = @('LocationPath', 'DevicePath')
        Player1          = [ordered]@{
            LocationPath = [string]$normalized.Player1.LocationPath
            DevicePath   = [string]$normalized.Player1.DevicePath
            Guid         = [string]$normalized.Player1.Guid
            Name         = [string]$normalized.Player1.Name
        }
        Player2          = [ordered]@{
            LocationPath = [string]$normalized.Player2.LocationPath
            DevicePath   = [string]$normalized.Player2.DevicePath
            Guid         = [string]$normalized.Player2.Guid
            Name         = [string]$normalized.Player2.Name
        }
        DegradedMode     = [bool]$normalized.DegradedMode
        DegradedReason   = [string]$normalized.DegradedReason
        LastUpdated      = [string]$normalized.LastUpdated
    }

    $json = $payload | ConvertTo-Json -Depth 8
    $json = $json -replace '\\u0026', '&'
    Set-Content -Path $MapPath -Value $json -Encoding UTF8
}

function Find-ControllerByDevicePath {
    param(
        [Parameter(Mandatory=$true)][string]$DevicePath,
        [Parameter(Mandatory=$true)]$Controllers
    )

    if ([string]::IsNullOrWhiteSpace($DevicePath)) { return @() }

    $exact = @($Controllers | Where-Object { $_.DevicePath -and $_.DevicePath -eq $DevicePath })
    if ($exact.Count -gt 0) { return $exact }

    $token = ($DevicePath -split '\\')[-1]
    if ([string]::IsNullOrWhiteSpace($token)) { return @() }

    @($Controllers | Where-Object {
        ($_.InstanceId -and $_.InstanceId -like ('*' + $token + '*')) -or
        ($_.DevicePath -and $_.DevicePath -like ('*' + $token + '*'))
    })
}

function Resolve-ControllerMatch {
    param(
        [Parameter(Mandatory=$true)]$Entry,
        [Parameter(Mandatory=$true)]$Controllers
    )

    $result = [pscustomobject]@{
        Controller = $null
        MatchType  = 'none'
        Reason     = ''
    }

    if ([string]::IsNullOrWhiteSpace([string]$Entry.LocationPath) -eq $false) {
        $byLocation = @($Controllers | Where-Object { $_.LocationPath -and $_.LocationPath -eq [string]$Entry.LocationPath })
        if ($byLocation.Count -eq 1) {
            $result.Controller = $byLocation[0]
            $result.MatchType = 'LocationPath'
            $result.Reason = 'Matched by LocationPath'
            return $result
        }
        if ($byLocation.Count -gt 1) {
            $result.Reason = 'Ambiguous LocationPath match'
            return $result
        }
    }

    $byDevicePath = @(Find-ControllerByDevicePath -DevicePath ([string]$Entry.DevicePath) -Controllers $Controllers)
    if ($byDevicePath.Count -eq 1) {
        $result.Controller = $byDevicePath[0]
        $result.MatchType = 'DevicePathFallback'
        $result.Reason = 'Matched by DevicePath fallback'
        return $result
    }

    if ($byDevicePath.Count -gt 1) {
        $result.Reason = 'Ambiguous DevicePath fallback match'
        return $result
    }

    $result.Reason = 'No match for entry'
    return $result
}

function Update-MapWithDiscoveredControllers {
    param(
        [Parameter(Mandatory=$true)]$Map,
        [Parameter(Mandatory=$true)]$Controllers,
        $Assignment
    )

    $normalized = ConvertTo-NormalizedControllerPortMap -Map $Map

    if ($Assignment) {
        if ([string]::IsNullOrWhiteSpace($normalized.Player1.DevicePath) -and $Assignment.Player1Path) { $normalized.Player1.DevicePath = [string]$Assignment.Player1Path }
        if ([string]::IsNullOrWhiteSpace($normalized.Player2.DevicePath) -and $Assignment.Player2Path) { $normalized.Player2.DevicePath = [string]$Assignment.Player2Path }
        if ([string]::IsNullOrWhiteSpace($normalized.Player1.Guid) -and $Assignment.Player1Guid) { $normalized.Player1.Guid = [string]$Assignment.Player1Guid }
        if ([string]::IsNullOrWhiteSpace($normalized.Player2.Guid) -and $Assignment.Player2Guid) { $normalized.Player2.Guid = [string]$Assignment.Player2Guid }
        if ([string]::IsNullOrWhiteSpace($normalized.Player1.Name) -and $Assignment.Player1Name) { $normalized.Player1.Name = [string]$Assignment.Player1Name }
        if ([string]::IsNullOrWhiteSpace($normalized.Player2.Name) -and $Assignment.Player2Name) { $normalized.Player2.Name = [string]$Assignment.Player2Name }
    }

    foreach ($slot in @('Player1', 'Player2')) {
        $entry = $normalized.$slot
        if ([string]::IsNullOrWhiteSpace([string]$entry.LocationPath) -and [string]::IsNullOrWhiteSpace([string]$entry.DevicePath) -eq $false) {
            $candidates = @(Find-ControllerByDevicePath -DevicePath ([string]$entry.DevicePath) -Controllers $Controllers)
            if ($candidates.Count -eq 1 -and $candidates[0].LocationPath) {
                $entry.LocationPath = [string]$candidates[0].LocationPath
            }
        }
    }

    $missingLocation = [string]::IsNullOrWhiteSpace($normalized.Player1.LocationPath) -or [string]::IsNullOrWhiteSpace($normalized.Player2.LocationPath)
    $normalized.DegradedMode = [bool]$missingLocation
    $normalized.DegradedReason = if ($missingLocation) { 'LocationPath missing for one or more players; fallback matching may be used.' } else { '' }

    return $normalized
}

function New-ControllerPortMapFromAssignment {
    param(
        [Parameter(Mandatory=$true)]$Assignment,
        [Parameter(Mandatory=$true)]$Controllers
    )

    $map = ConvertTo-NormalizedControllerPortMap -Map $null
    $map.Player1.DevicePath = [string]$Assignment.Player1Path
    $map.Player2.DevicePath = [string]$Assignment.Player2Path
    $map.Player1.Guid = [string]$Assignment.Player1Guid
    $map.Player2.Guid = [string]$Assignment.Player2Guid
    $map.Player1.Name = [string]$Assignment.Player1Name
    $map.Player2.Name = [string]$Assignment.Player2Name

    return (Update-MapWithDiscoveredControllers -Map $map -Controllers $Controllers -Assignment $Assignment)
}

function Test-ControllerMapValidation {
    param(
        [Parameter(Mandatory=$true)]$Map,
        [Parameter(Mandatory=$true)]$Controllers
    )

    $issues = New-Object System.Collections.Generic.List[string]
    $normalized = ConvertTo-NormalizedControllerPortMap -Map $Map

    if (-not $normalized.Player1 -or -not $normalized.Player2) {
        $issues.Add('Player1 or Player2 entry is missing in map.')
    }

    if ([string]::IsNullOrWhiteSpace([string]$normalized.Player1.DevicePath)) {
        $issues.Add('Player1.DevicePath is missing.')
    }

    if ([string]::IsNullOrWhiteSpace([string]$normalized.Player2.DevicePath)) {
        $issues.Add('Player2.DevicePath is missing.')
    }

    if ([string]::IsNullOrWhiteSpace([string]$normalized.Player1.LocationPath) -eq $false -and
        [string]::IsNullOrWhiteSpace([string]$normalized.Player2.LocationPath) -eq $false -and
        ([string]$normalized.Player1.LocationPath -eq [string]$normalized.Player2.LocationPath)) {
        $issues.Add('Player1.LocationPath and Player2.LocationPath are identical.')
    }

    if ([string]::IsNullOrWhiteSpace([string]$normalized.Player1.LocationPath)) {
        $issues.Add('Player1.LocationPath is missing.')
    }

    if ([string]::IsNullOrWhiteSpace([string]$normalized.Player2.LocationPath)) {
        $issues.Add('Player2.LocationPath is missing.')
    }

    $p1Match = Resolve-ControllerMatch -Entry $normalized.Player1 -Controllers $Controllers
    $p2Match = Resolve-ControllerMatch -Entry $normalized.Player2 -Controllers $Controllers

    if (-not $p1Match.Controller) {
        $issues.Add(("Player1 did not resolve to a connected controller ({0})." -f $p1Match.Reason))
    }

    if (-not $p2Match.Controller) {
        $issues.Add(("Player2 did not resolve to a connected controller ({0})." -f $p2Match.Reason))
    }

    if ($p1Match.Controller -and $p2Match.Controller) {
        if ([string]$p1Match.Controller.InstanceId -eq [string]$p2Match.Controller.InstanceId) {
            $issues.Add('Player1 and Player2 resolve to the same physical controller.')
        }
    }

    $physicalControllers = @(
        $Controllers | Where-Object {
            $_.DevicePath -and $_.InstanceId -like 'USB\VID_0079&PID_0006*'
        }
    )

    $hasTwoControllers = (@($physicalControllers).Count -ge 2)
    $canEnforce = ($issues.Count -eq 0) -and $hasTwoControllers -and $p1Match.Controller -and $p2Match.Controller

    [pscustomobject]@{
        Map               = $normalized
        Issues            = $issues
        HasTwoControllers = $hasTwoControllers
        P1Match           = $p1Match
        P2Match           = $p2Match
        CanEnforce        = [bool]$canEnforce
    }
}

function Get-ExpectedPlayerDevicePaths {
    param(
        [Parameter(Mandatory=$true)]$Map,
        $P1Match,
        $P2Match
    )

    $normalized = ConvertTo-NormalizedControllerPortMap -Map $Map

    $p1 = ''
    $p2 = ''

    if ($P1Match -and $P1Match.Controller -and $P1Match.Controller.DevicePath) {
        $p1 = [string]$P1Match.Controller.DevicePath
    }
    elseif ($normalized.Player1.DevicePath) {
        $p1 = [string]$normalized.Player1.DevicePath
    }

    if ($P2Match -and $P2Match.Controller -and $P2Match.Controller.DevicePath) {
        $p2 = [string]$P2Match.Controller.DevicePath
    }
    elseif ($normalized.Player2.DevicePath) {
        $p2 = [string]$normalized.Player2.DevicePath
    }

    [pscustomobject]@{
        Player1 = $p1
        Player2 = $p2
    }
}

function Test-LauncherAssignmentMatchesExpectedPaths {
    param(
        $Assignment,
        [Parameter(Mandatory=$true)][string]$ExpectedP1,
        [Parameter(Mandatory=$true)][string]$ExpectedP2
    )

    if (-not $Assignment) {
        return [pscustomobject]@{ Matches = $false; Reason = 'No launcher assignment found in log.'; P1Match = $false; P2Match = $false }
    }

    $p1ok = ([string]$ExpectedP1 -eq [string]$Assignment.Player1Path)
    $p2ok = ([string]$ExpectedP2 -eq [string]$Assignment.Player2Path)

    [pscustomobject]@{
        Matches = ($p1ok -and $p2ok)
        P1Match = $p1ok
        P2Match = $p2ok
        Reason  = if ($p1ok -and $p2ok) { 'Launcher paths match expected paths.' } else { 'Launcher paths do not match expected paths.' }
    }
}

function Set-UniqueRetroArchKeys {
    param(
        [Parameter(Mandatory=$true)][string]$ConfigPath,
        [Parameter(Mandatory=$true)][hashtable]$Values
    )

    $lines = @()
    if (Test-Path $ConfigPath) {
        $lines = Get-Content -Path $ConfigPath
    }

    $keys = @($Values.Keys)
    $filtered = New-Object System.Collections.Generic.List[string]

    foreach ($line in $lines) {
        $drop = $false
        foreach ($key in $keys) {
            if ($line -match ('^\s*' + [regex]::Escape($key) + '\s*=\s*.*$')) {
                $drop = $true
                break
            }
        }

        if (-not $drop) { $filtered.Add($line) }
    }

    foreach ($key in $keys) {
        $filtered.Add(('{0} = "{1}"' -f $key, [string]$Values[$key]))
    }

    Set-Content -Path $ConfigPath -Value $filtered -Encoding UTF8
}

function Set-UniqueRetroArchCoreOptionKeys {
    param(
        [Parameter(Mandatory=$true)][string]$ConfigPath,
        [Parameter(Mandatory=$true)][hashtable]$Values
    )

    $lines = @()
    if (Test-Path $ConfigPath) {
        $lines = Get-Content -Path $ConfigPath
    }

    $keys = @($Values.Keys)
    $filtered = New-Object System.Collections.Generic.List[string]

    foreach ($line in $lines) {
        $drop = $false
        foreach ($key in $keys) {
            if ($line -match ('^\s*' + [regex]::Escape($key) + '\s*=\s*.*$')) {
                $drop = $true
                break
            }
        }

        if (-not $drop) { $filtered.Add($line) }
    }

    foreach ($key in $keys) {
        $filtered.Add(('{0} = "{1}"' -f $key, [string]$Values[$key]))
    }

    Set-Content -Path $ConfigPath -Value $filtered -Encoding UTF8
}

function Remove-ConflictingRetroArchRemapAssignments {
    param(
        [Parameter(Mandatory=$true)][string]$RemapRootPath,
        [string[]]$ForbiddenKeys = @(
            'input_player1_joypad_index',
            'input_player2_joypad_index',
            'input_autodetect_enable',
            'input_remap_binds_enable'
        )
    )

    if (-not (Test-Path $RemapRootPath)) {
        return [pscustomobject]@{
            ScannedFiles   = 0
            ModifiedFiles  = 0
            DeletedFiles   = 0
            ModifiedPaths  = @()
            DeletedPaths   = @()
        }
    }

    $files = @(Get-ChildItem -Path $RemapRootPath -File -Recurse -ErrorAction SilentlyContinue)
    $modifiedPaths = New-Object System.Collections.Generic.List[string]
    $deletedPaths = New-Object System.Collections.Generic.List[string]
    $modifiedCount = 0
    $deletedCount = 0

    foreach ($file in $files) {
        $orig = @()
        try {
            $orig = @(Get-Content -Path $file.FullName -ErrorAction Stop)
        } catch {
            continue
        }

        $filtered = New-Object System.Collections.Generic.List[string]
        $changed = $false

        foreach ($line in $orig) {
            $isForbidden = $false
            foreach ($key in $ForbiddenKeys) {
                if ($line -match ('^\s*' + [regex]::Escape($key) + '\s*=')) {
                    $isForbidden = $true
                    break
                }
            }

            if ($isForbidden) {
                $changed = $true
                continue
            }

            $filtered.Add($line)
        }

        if (-not $changed) { continue }

        if ($filtered.Count -eq 0) {
            Remove-Item -Path $file.FullName -Force
            $deletedCount++
            $deletedPaths.Add([string]$file.FullName) | Out-Null
            continue
        }

        Set-Content -Path $file.FullName -Value $filtered -Encoding UTF8
        $modifiedCount++
        $modifiedPaths.Add([string]$file.FullName) | Out-Null
    }

    return [pscustomobject]@{
        ScannedFiles   = [int]$files.Count
        ModifiedFiles  = [int]$modifiedCount
        DeletedFiles   = [int]$deletedCount
        ModifiedPaths  = @($modifiedPaths)
        DeletedPaths   = @($deletedPaths)
    }
}

function Set-EsSettingsPlayerBindings {
    param(
        [Parameter(Mandatory=$true)][string]$EsSettingsPath,
        [Parameter(Mandatory=$true)]$Map
    )

    if (-not (Test-Path $EsSettingsPath)) { return }

    $normalized = ConvertTo-NormalizedControllerPortMap -Map $Map
    $xml = Get-Content -Raw $EsSettingsPath

    function UpsertXmlString([string]$source, [string]$name, [string]$value) {
        $escaped = $value -replace '&', '&amp;'
        $replacement = ('<string name="{0}" value="{1}" />' -f $name, $escaped)
        $pattern = '(?m)^\s*<string name="' + [regex]::Escape($name) + '" value="[^"]*"\s*/>\s*$'

        if ([regex]::IsMatch($source, $pattern)) {
            return [regex]::Replace($source, $pattern, $replacement, 1)
        }

        return $source -replace '</config>', ($replacement + "`r`n</config>")
    }

    if ($normalized.Player1.DevicePath) { $xml = UpsertXmlString $xml 'INPUT P1PATH' ([string]$normalized.Player1.DevicePath) }
    if ($normalized.Player2.DevicePath) { $xml = UpsertXmlString $xml 'INPUT P2PATH' ([string]$normalized.Player2.DevicePath) }
    if ($normalized.Player1.Guid) { $xml = UpsertXmlString $xml 'INPUT P1GUID' ([string]$normalized.Player1.Guid) }
    if ($normalized.Player2.Guid) { $xml = UpsertXmlString $xml 'INPUT P2GUID' ([string]$normalized.Player2.Guid) }
    if ($normalized.Player1.Name) { $xml = UpsertXmlString $xml 'INPUT P1NAME' ([string]$normalized.Player1.Name) }
    if ($normalized.Player2.Name) { $xml = UpsertXmlString $xml 'INPUT P2NAME' ([string]$normalized.Player2.Name) }

    Set-Content -Path $EsSettingsPath -Value $xml -Encoding UTF8
}

Export-ModuleMember -Function Write-ControllerLog, Get-LatestRetroBatLauncherAssignment, Get-DragonRiseControllers, Read-ControllerPortMap, Write-ControllerPortMap, New-ControllerPortMapFromAssignment, Update-MapWithDiscoveredControllers, Test-ControllerMapValidation, Get-ExpectedPlayerDevicePaths, Test-LauncherAssignmentMatchesExpectedPaths, Set-UniqueRetroArchKeys, Set-UniqueRetroArchCoreOptionKeys, Remove-ConflictingRetroArchRemapAssignments, Set-EsSettingsPlayerBindings
