# RetroBat Thunderdome Config Backup

This repository contains a **config-only backup** of a working RetroBat setup.

## Included
- EmulationStation settings and controller bindings
- RetroArch global config and core options
- Controller order enforcement scripts and map
- `gamelist.xml` files for systems
- Active theme overrides for `Hypermax-Plus-PixN` (XML files only)
- Startup helper script for controller enforcement

## Excluded
- ROMs, BIOS, saves, states
- Videos, images, manuals, music
- Large theme media assets

## Restore Steps (Windows)
1. Install RetroBat to `C:\RetroBat`.
2. Install/download the base theme `Hypermax-Plus-PixN` from RetroBat Theme Downloader.
3. Run the restore script from this repo:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Restore-RetroBatConfig.ps1
```

4. Launch RetroBat.

## Restore Script Options
Preview only (no file changes):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Restore-RetroBatConfig.ps1 -WhatIf
```

Skip backup copy of existing files:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Restore-RetroBatConfig.ps1 -SkipBackup
```

Skip Startup folder helper install:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Restore-RetroBatConfig.ps1 -SkipStartupShortcut
```

## Notes
- Controller order map is stored in:
  `C:\RetroBat\system\controller-port-map.json`
- Enforcer script is:
  `C:\RetroBat\tools\enforce-controller-order.ps1`
- Automated restore script is:
  `.\scripts\Restore-RetroBatConfig.ps1`
- This repo is intentionally light and portable for version control.
