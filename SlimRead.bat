@echo off
title SlimRead
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0' -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0SlimRead.ps1"

echo.
echo ------------------------------------------------------------
echo  Finished (exit code %ERRORLEVEL%).
echo  This window stays open on purpose so you can read any errors.
echo ------------------------------------------------------------
pause
