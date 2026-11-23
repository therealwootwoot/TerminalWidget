@echo off
rem Terminal Widget v4.0 launcher
rem Runs TerminalWidget.ps1 (same folder) with Windows PowerShell 5.1, hidden.
rem Full path, so a broken or redirected PATH cannot pick a different host.
set "PSEXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PSEXE%" set "PSEXE=powershell.exe"
if not exist "%~dp0TerminalWidget.ps1" (
  echo TerminalWidget.ps1 not found in %~dp0
  pause
  exit /b 1
)
if not exist "%~dp0TerminalWidget.Core.ps1" (
  echo TerminalWidget.Core.ps1 not found in %~dp0
  pause
  exit /b 1
)
start "" /min "%PSEXE%" -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0TerminalWidget.ps1"
