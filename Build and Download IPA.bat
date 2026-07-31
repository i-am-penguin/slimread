@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo ==================================================
echo   SlimRead - build on GitHub and download the IPA
echo ==================================================
echo.

where git >nul 2>&1
if errorlevel 1 ( echo Git is not on PATH. Open a new terminal and try again. & goto :end )
where gh >nul 2>&1
if errorlevel 1 ( echo GitHub CLI is not on PATH. Open a new terminal and try again. & goto :end )

if not exist "SlimRead.xcodeproj" (
    echo This file must sit in the SlimRead folder, next to SlimRead.xcodeproj.
    goto :end
)

echo Saving your changes...
git add -A
git commit -m "update" --allow-empty
echo.

echo Pushing to GitHub...
git push
if errorlevel 1 ( echo. & echo Push failed - see the message above. & goto :end )
echo.

echo Finding the build that just started...
set "RUNID="
for /f "delims=" %%i in ('gh run list --limit 1 --json databaseId --jq ".[0].databaseId"') do set "RUNID=%%i"
if "%RUNID%"=="" ( echo Could not find the build run. Check the Actions tab on GitHub. & goto :end )

echo Building on a macOS runner - about 4 minutes. Leave this window open...
echo.
gh run watch %RUNID% --exit-status
if errorlevel 1 (
    echo.
    echo ==================================================
    echo   BUILD FAILED
    echo ==================================================
    echo To see exactly what broke, run this in the same folder:
    echo.
    echo     gh run view %RUNID% --log-failed
    echo.
    echo Copy that output to me and I'll fix it.
    goto :end
)

echo.
echo Build succeeded. Downloading the IPA...
gh run download %RUNID% --name SlimRead-ipa
echo.

echo ==================================================
echo   Done. IPA files in this folder:
echo ==================================================
dir /b *.ipa 2>nul
echo.
echo Next: drag SlimRead.ipa onto Sideloadly with your phone plugged in.

:end
echo.
echo ---
pause
