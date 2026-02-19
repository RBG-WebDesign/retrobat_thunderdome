@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\RetroBat\tools\enforce-controller-order.ps1"
exit /b %ERRORLEVEL%
