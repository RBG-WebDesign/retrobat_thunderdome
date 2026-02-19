@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\RetroBat\tools\enforce-controller-order.ps1"
if errorlevel 1 (
  echo Controller enforcement failed. RetroBat launch cancelled.
  exit /b 1
)
start "" "C:\RetroBat\retrobat.exe"
exit /b 0
