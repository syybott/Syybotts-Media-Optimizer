@echo off
setlocal
cd /d "%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-SYYBOTTS-Media-Optimizer-EXE-v1.0.0-beta.1.ps1"
exit /b %errorlevel%
