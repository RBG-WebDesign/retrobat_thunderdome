[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$RepoRoot = '',
    [string]$TargetRoot = 'C:\RetroBat',
    [switch]$SkipStartupShortcut,
    [switch]$SkipBackup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $scriptPath = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($scriptPath)) {
        $scriptPath = $MyInvocation.MyCommand.Path
    }
    if ([string]::IsNullOrWhiteSpace($scriptPath)) {
        throw 'Unable to resolve script path. Pass -RepoRoot explicitly.'
    }

    $scriptDir = Split-Path -Parent $scriptPath
    $RepoRoot = Split-Path -Parent $scriptDir
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Warn {
    param([string]$Message)
    Write-Warning $Message
}

$sourceRoot = Join-Path $RepoRoot 'retrobat'
$startupSource = Join-Path $RepoRoot 'windows-startup\RetroBat-Controller-Order.cmd'
$startupTargetDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
$startupTarget = Join-Path $startupTargetDir 'RetroBat-Controller-Order.cmd'

if (-not (Test-Path -LiteralPath $sourceRoot)) {
    throw "Source folder not found: $sourceRoot"
}

$requiredFiles = @(
    'retrobat.ini',
    'system\controller-port-map.json',
    'emulationstation\.emulationstation\es_settings.cfg',
    'emulators\retroarch\retroarch.cfg',
    'tools\enforce-controller-order.ps1'
)

foreach ($requiredRel in $requiredFiles) {
    $requiredPath = Join-Path $sourceRoot $requiredRel
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required file missing in backup: $requiredPath"
    }
}

$sourceFiles = Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Force
if ($sourceFiles.Count -eq 0) {
    throw "No files found under source folder: $sourceRoot"
}

if (-not (Test-Path -LiteralPath $TargetRoot)) {
    if ($PSCmdlet.ShouldProcess($TargetRoot, 'Create RetroBat target root folder')) {
        New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null
    }
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $RepoRoot ("backup\restore-{0}" -f $timestamp)
$copyCount = 0
$backupCount = 0

if (-not $SkipBackup) {
    foreach ($sourceFile in $sourceFiles) {
        $relativePath = $sourceFile.FullName.Substring($sourceRoot.Length).TrimStart('\')
        $targetPath = Join-Path $TargetRoot $relativePath

        if (Test-Path -LiteralPath $targetPath) {
            $backupPath = Join-Path $backupRoot $relativePath
            $backupParent = Split-Path -Parent $backupPath
            if ($PSCmdlet.ShouldProcess($backupPath, "Backup existing file from $targetPath")) {
                New-Item -ItemType Directory -Path $backupParent -Force | Out-Null
                Copy-Item -LiteralPath $targetPath -Destination $backupPath -Force
                $backupCount++
            }
        }
    }
}

foreach ($sourceFile in $sourceFiles) {
    $relativePath = $sourceFile.FullName.Substring($sourceRoot.Length).TrimStart('\')
    $targetPath = Join-Path $TargetRoot $relativePath
    $targetParent = Split-Path -Parent $targetPath

    if ($PSCmdlet.ShouldProcess($targetPath, "Copy $relativePath")) {
        New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
        Copy-Item -LiteralPath $sourceFile.FullName -Destination $targetPath -Force
        $copyCount++
    }
}

if (-not $SkipStartupShortcut -and (Test-Path -LiteralPath $startupSource)) {
    if ($PSCmdlet.ShouldProcess($startupTarget, 'Install startup controller-order helper')) {
        New-Item -ItemType Directory -Path $startupTargetDir -Force | Out-Null
        Copy-Item -LiteralPath $startupSource -Destination $startupTarget -Force
    }
}
elseif (-not $SkipStartupShortcut) {
    Write-Warn "Startup helper not found in repo: $startupSource"
}

$themePath = Join-Path $TargetRoot 'emulationstation\.emulationstation\themes\Hypermax-Plus-PixN'
if (-not (Test-Path -LiteralPath $themePath)) {
    Write-Warn "Theme base folder missing: $themePath"
    Write-Warn "Install the base theme first from RetroBat Theme Downloader, then rerun this script."
}

Write-Info ("Restore complete. Files copied: {0}" -f $copyCount)
if (-not $SkipBackup) {
    Write-Info ("Backups created: {0}" -f $backupCount)
    Write-Info ("Backup folder: {0}" -f $backupRoot)
}
else {
    Write-Info 'Backups skipped by request (-SkipBackup).'
}

if (-not $SkipStartupShortcut) {
    Write-Info ("Startup helper path: {0}" -f $startupTarget)
}
