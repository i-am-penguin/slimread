@echo off
title SlimRead - publish update (maintainer)
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0' -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Publish-Update.ps1"
echo.
echo ------------------------------------------------------------
echo  Finished (exit code %ERRORLEVEL%).
echo  Window kept open so you can read any errors above.
echo ------------------------------------------------------------
pause
