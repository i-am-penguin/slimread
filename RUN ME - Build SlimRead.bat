@echo off
title SlimRead builder
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-SlimRead.ps1"
echo.
echo ---
echo Script finished (exit code %ERRORLEVEL%). This window stays open so you can read any errors above.
pause
