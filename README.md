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
3. Copy the `retrobat\` folder contents from this repo onto `C:\RetroBat` (merge/overwrite).
4. Copy `windows-startup\RetroBat-Controller-Order.cmd` to:
   `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\`
5. Launch RetroBat.

## Notes
- Controller order map is stored in:
  `C:\RetroBat\system\controller-port-map.json`
- Enforcer script is:
  `C:\RetroBat\tools\enforce-controller-order.ps1`
- This repo is intentionally light and portable for version control.
