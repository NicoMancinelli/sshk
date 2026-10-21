@echo off
rem Use the same upgrade-preserving implementation as the PowerShell installer.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-to-kindle.ps1"
exit /b %errorlevel%
