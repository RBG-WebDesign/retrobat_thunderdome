# RetroBat Controller Port Lock (Windows)

## Objective
Guarantee deterministic player order for identical DragonRise encoders.

- Front-left USB port -> Player 1
- Front-right USB port -> Player 2

## Primary identity model
Identity is **LocationPath-first**.

1. Match by `LocationPath` (primary, stable physical-port identity)
2. Match by `DevicePath` (fallback only, degraded mode)

If LocationPath cannot be read for one or both players, enforcement logs degraded mode explicitly.

## Files
- Map: `C:\RetroBat\system\controller-port-map.json`
- Enforcement script: `C:\RetroBat\tools\enforce-controller-order.ps1`
- Module: `C:\RetroBat\tools\modules\ControllerOrder.psm1`
- Log: `C:\RetroBat\logs\controller-order.log`
- Enforce-only wrapper: `C:\RetroBat\tools\run-controller-order-enforcement.cmd`
- Pre-launch RetroBat wrapper: `C:\RetroBat\tools\launch-retrobat-with-controller-order.cmd`
- Startup task installer (admin): `C:\RetroBat\tools\install-controller-order-startup-task.ps1`
- Startup launch-wrapper activator: `C:\RetroBat\tools\activate-retrobat-launch-wrapper.ps1`
- Setup verifier: `C:\RetroBat\tools\verify-controller-order-setup.ps1`

## Map schema
```json
{
  "SchemaVersion": 2,
  "IdentityPriority": ["LocationPath", "DevicePath"],
  "Player1": {
    "LocationPath": "PCIROOT(...)#USB(...)",
    "DevicePath": "USB\\VID_0079&PID_0006\\...",
    "Guid": "03000000790000000600000000000000",
    "Name": "Generic USB Joystick"
  },
  "Player2": {
    "LocationPath": "PCIROOT(...)#USB(...)",
    "DevicePath": "USB\\VID_0079&PID_0006\\...",
    "Guid": "03000000790000000600000000000000",
    "Name": "Generic USB Joystick"
  },
  "DegradedMode": false,
  "DegradedReason": "",
  "LastUpdated": "2026-02-17T20:00:00-08:00"
}
```

## Validation rules
Before assignment rewrite, enforcement validates:

- Player1 and Player2 map entries exist
- P1 and P2 are not identical LocationPath values
- Both target devices are present and resolve to distinct controllers
- If fewer than two controllers are present, assignments are preserved and rewrite is skipped

## RetroArch enforcement
`C:\RetroBat\emulators\retroarch\retroarch.cfg` is normalized to one canonical line per key:

- `input_player1_joypad_index = "0"`
- `input_player2_joypad_index = "1"`
- `input_autodetect_enable = "true"`
- `input_remap_binds_enable = "false"`

## Launcher verification
Enforcement parses `C:\RetroBat\emulationstation\emulatorLauncher.log` and checks latest:

- `-p1path`
- `-p2path`

against expected mapped players. On mismatch:

1. Re-run discovery and validation once
2. If mismatch persists, fail enforcement (non-zero exit)

## Startup timing options
### Option A (preferred): Scheduled Task at startup, highest privileges
Run from elevated PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\RetroBat\tools\install-controller-order-startup-task.ps1
```

Creates:
- Task name: `RetroBat-EnforceControllerOrder`
- Trigger: `ONSTART`
- Account: `SYSTEM`
- Privilege: `HIGHEST`
- Delay: `5 seconds`

### Option B: Launch RetroBat through strict wrapper
Use:

`C:\RetroBat\tools\launch-retrobat-with-controller-order.cmd`

Behavior:
- Runs enforcement first
- Launches `retrobat.exe` only if enforcement succeeds

## Initial map population
1. Connect both controllers in final physical ports
2. Launch and exit one game so `emulatorLauncher.log` contains latest `-p1path/-p2path`
3. Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\RetroBat\tools\enforce-controller-order.ps1
```

4. Confirm map and logs

## Finalize startup/launch wiring
1. Run (elevated):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\RetroBat\tools\install-controller-order-startup-task.ps1
```

2. Run (normal user session):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\RetroBat\tools\activate-retrobat-launch-wrapper.ps1
```

This ensures Startup `RetroBat.lnk` launches:

`C:\RetroBat\tools\launch-retrobat-with-controller-order.cmd`

instead of direct `retrobat.exe`.

The activator also rewrites `Desktop\RetroBat.lnk` (if present) to the same wrapper target.

## Verification procedure
Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\RetroBat\tools\verify-controller-order-setup.ps1 -RunEnforcement
```

Expected checks:
- Scheduled task `RetroBat-EnforceControllerOrder` exists
- Trigger = At startup, Delay = 5s
- Principal = SYSTEM, RunLevel = Highest
- Startup shortcut target is launch wrapper
- Desktop shortcut target is launch wrapper (if shortcut exists)
- Map contains distinct P1/P2 LocationPaths
- Latest launcher `-p1path` and `-p2path` match mapped device paths
- Controller log exists

## Cold boot persistence test
1. Power off fully (cold boot), then boot to Windows.
2. Do not swap USB ports.
3. Launch RetroBat via Startup or wrapper.
4. Launch a game, then exit.
5. Check:

```powershell
Get-Content C:\RetroBat\logs\controller-order.log -Tail 120
Select-String -Path C:\RetroBat\emulationstation\emulatorLauncher.log -Pattern '-p1path\\s+\"[^\"]+\".*-p2path\\s+\"[^\"]+\"' | Select-Object -Last 1
```

Pass criteria:
- No degraded-mode warning
- Launcher verification pass in controller log
- Latest launcher line keeps same P1/P2 paths as map

## Diagnostics
Check latest run:

```powershell
Get-Content C:\RetroBat\logs\controller-order.log -Tail 80
```

If degraded mode appears:
- It means LocationPath is missing/unreadable for one or both players
- Fallback matching may still work via DevicePath, but should be treated as less robust
- Reconnect both controllers and rerun enforcement to hydrate LocationPaths

## Notes
- No RetroBat binaries are modified
- No AntiMicroX dependency
- Map format is backward-compatible via in-script migration to schema v2
