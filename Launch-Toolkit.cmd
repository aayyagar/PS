@echo off
rem AD and DNS Toolkit - double-click to start. Right-click and "Run as administrator" for changes that need it.
rem Uses PowerShell 7 when installed, otherwise Windows PowerShell 5.1.
setlocal
set "TK=%~dp0Start-Toolkit.ps1"
where pwsh >nul 2>nul
if %ERRORLEVEL%==0 (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%TK%" %*
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%TK%" %*
)
if errorlevel 1 pause
endlocal
