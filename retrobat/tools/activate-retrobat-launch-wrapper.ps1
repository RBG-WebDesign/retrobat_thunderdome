$ErrorActionPreference = 'Stop'

$startupDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
$desktopDir = Join-Path $env:USERPROFILE 'Desktop'
$startupShortcut = Join-Path $startupDir 'RetroBat.lnk'
$desktopShortcut = Join-Path $desktopDir 'RetroBat.lnk'
$wrapperPath = 'C:\RetroBat\tools\launch-retrobat-with-controller-order.cmd'
$workingDir = 'C:\RetroBat'
$iconPath = 'C:\RetroBat\retrobat.exe,0'

if (-not (Test-Path $wrapperPath)) {
    throw "Launch wrapper not found: $wrapperPath"
}

$wsh = New-Object -ComObject WScript.Shell

function Set-ShortcutTarget {
    param(
        [Parameter(Mandatory=$true)][string]$ShortcutPath,
        [Parameter(Mandatory=$true)][bool]$CreateIfMissing
    )

    $dir = Split-Path -Parent $ShortcutPath
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path $ShortcutPath) -and -not $CreateIfMissing) {
        return "Skipped missing shortcut: $ShortcutPath"
    }

    $shortcut = $wsh.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $wrapperPath
    $shortcut.Arguments = ''
    $shortcut.WorkingDirectory = $workingDir
    $shortcut.IconLocation = $iconPath
    $shortcut.Save()

    return "Shortcut set: $ShortcutPath -> $wrapperPath"
}

Write-Output (Set-ShortcutTarget -ShortcutPath $startupShortcut -CreateIfMissing $true)
Write-Output (Set-ShortcutTarget -ShortcutPath $desktopShortcut -CreateIfMissing $false)
