<#
    Publish-Update.ps1 - MAINTAINER ONLY.

    Run it by double-clicking "Publish Update.bat".

    End users never touch this file. They run SlimRead.bat, which downloads whatever
    you last published.

    What it does:
      1. installs Git and the GitHub CLI if missing (winget optional)
      2. signs you in to GitHub
      3. commits and pushes your changes
      4. builds on a GitHub macOS runner
      5. optionally publishes a release, which is what end users download

    Remember: changes to tweaks/ do NOT need any of this. Push them and every
    installed copy picks them up on next launch. Only native code needs a release.
#>

$ErrorActionPreference = 'Stop'
$ProjectDir = $PSScriptRoot

function Line { param([string]$t = '') Write-Host $t -ForegroundColor Gray }
function Head { param([string]$t) Write-Host ''; Write-Host "  $t" -ForegroundColor Cyan; Write-Host ('  ' + ('-' * 60)) -ForegroundColor DarkGray }
function Good { param([string]$t) Write-Host "    [ok] $t" -ForegroundColor Green }
function Warn { param([string]$t) Write-Host "    [!] $t" -ForegroundColor Yellow }
function Info { param([string]$t) Write-Host "    $t" -ForegroundColor Gray }
function Ask  { param([string]$q) return ((Read-Host "    $q (Y/n)") -notmatch '^[Nn]') }

function Stop-With {
    param([string]$What, [string[]]$Fix)
    Write-Host ''
    Write-Host '  ============================================================' -ForegroundColor Red
    Write-Host "   STOPPED: $What" -ForegroundColor Red
    Write-Host '  ============================================================' -ForegroundColor Red
    Write-Host ''
    Write-Host '   How to fix it:' -ForegroundColor Yellow
    foreach ($f in $Fix) { Write-Host "     - $f" -ForegroundColor Yellow }
    Write-Host ''
    exit 1
}

function Update-PathFromRegistry {
    $m = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $u = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$m;$u"
}
function Have { param([string]$exe) return [bool](Get-Command $exe -ErrorAction SilentlyContinue) }
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

Clear-Host
Write-Host ''
Write-Host '  ============================================================' -ForegroundColor Magenta
Write-Host '   SlimRead - publish an update (maintainer)' -ForegroundColor Magenta
Write-Host '  ============================================================' -ForegroundColor Magenta
Line

Head '0. Folder check'
if (-not (Test-Path (Join-Path $ProjectDir 'SlimRead.xcodeproj'))) {
    Stop-With 'This script is not in the SlimRead project folder' @(
        "It is in: $ProjectDir",
        'It must sit beside SlimRead.xcodeproj and tweaks/.',
        'Never run it from C:\Windows\System32 - that is where an admin PowerShell',
        '  window opens, and Git refuses to operate on system folders.'
    )
}
Good "Project: $ProjectDir"

try {
    Get-ChildItem $ProjectDir -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
} catch { }

Head '1. Tools'

function Install-WingetIfPossible {
    if (Have 'winget') { return }
    Info 'winget missing - trying to register the App Installer already on Windows...'
    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop
        Update-PathFromRegistry
        if (Have 'winget') { Good 'winget registered'; return }
    } catch { }
    if (Test-Admin) {
        try {
            $progressPreference = 'silentlyContinue'
            Install-PackageProvider -Name NuGet -Force -ErrorAction Stop | Out-Null
            Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery -ErrorAction Stop | Out-Null
            Repair-WinGetPackageManager -AllUsers -ErrorAction Stop
            Update-PathFromRegistry
            if (Have 'winget') { Good 'winget installed'; return }
        } catch { Warn 'winget install failed - continuing without it' }
    }
    Info 'Continuing without winget; installers can be fetched directly.'
}

function Get-LatestAsset {
    param([string]$Repo, [string]$Pattern)
    $r = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ 'User-Agent' = 'SlimRead' } -TimeoutSec 30
    $a = $r.assets | Where-Object { $_.name -like $Pattern } | Select-Object -First 1
    if (-not $a) { throw "No asset matching $Pattern" }
    return $a.browser_download_url
}

function Ensure-Tool {
    param([string]$Exe, [string]$WingetId, [string]$Repo, [string]$Pattern, [string]$SilentArgs, [string[]]$Fallbacks)
    if (Have $Exe) { Good "$Exe present"; return }
    Info "Installing $Exe..."
    if (Have 'winget') {
        try {
            winget install --id $WingetId --exact --silent --accept-source-agreements --accept-package-agreements | Out-Null
            Update-PathFromRegistry
        } catch { }
    }
    if (-not (Have $Exe)) {
        try {
            $url = Get-LatestAsset -Repo $Repo -Pattern $Pattern
            $file = Join-Path $env:TEMP (Split-Path $url -Leaf)
            $progressPreference = 'silentlyContinue'
            Invoke-WebRequest -Uri $url -OutFile $file -UseBasicParsing -TimeoutSec 600
            Info 'Approve the Windows prompt if it appears.'
            if ($file -like '*.msi') { Start-Process msiexec.exe -ArgumentList "/i `"$file`" $SilentArgs" -Wait }
            else { Start-Process $file -ArgumentList $SilentArgs -Wait }
            Update-PathFromRegistry
        } catch { Warn "Direct install failed: $($_.Exception.Message)" }
    }
    if (-not (Have $Exe)) {
        foreach ($p in $Fallbacks) { if (Test-Path $p) { $env:Path = "$env:Path;$(Split-Path $p)"; break } }
    }
    if (-not (Have $Exe)) {
        Stop-With "$Exe is not available" @(
            'Install by hand then run again:',
            '  Git         https://git-scm.com/download/win',
            '  GitHub CLI  https://cli.github.com',
            'If you just installed it, open a NEW window - PATH does not refresh in place.'
        )
    }
    Good "$Exe installed"
}

Install-WingetIfPossible
Ensure-Tool -Exe 'git' -WingetId 'Git.Git' -Repo 'git-for-windows/git' -Pattern 'Git-*-64-bit.exe' `
    -SilentArgs '/VERYSILENT /NORESTART /NOCANCEL /SP-' -Fallbacks @("$env:ProgramFiles\Git\cmd\git.exe")
Ensure-Tool -Exe 'gh' -WingetId 'GitHub.cli' -Repo 'cli/cli' -Pattern 'gh_*_windows_amd64.msi' `
    -SilentArgs '/qn /norestart' -Fallbacks @("$env:ProgramFiles\GitHub CLI\gh.exe")

Head '2. GitHub'
& gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
    Info 'A browser will open. Choose HTTPS when asked about the Git protocol.'
    & gh auth login --hostname github.com --git-protocol https --web
    if ($LASTEXITCODE -ne 0) { Stop-With 'Sign-in did not complete' @('Run again and finish the browser step.') }
}
$account = (& gh api user --jq '.login').Trim()
Good "Signed in as $account"

Push-Location $ProjectDir
try {
    Head '3. Pushing your changes'

    if (-not (Test-Path (Join-Path $ProjectDir '.git'))) { & git init -b main | Out-Null }
    if (-not (& git config user.email)) { & git config user.email "$account@users.noreply.github.com" }
    if (-not (& git config user.name))  { & git config user.name  "$account" }

    $obsolete = @('Build-SlimRead.ps1', 'RUN ME - Build SlimRead.bat', 'Build and Download IPA.bat',
                  '.write_test', '__t', 'SlimRead.swiftpm', 'source.json')
    foreach ($o in $obsolete) {
        $full = Join-Path $ProjectDir $o
        if (Test-Path $full) {
            & git rm -r --cached --quiet -- $o *> $null
            Remove-Item $full -Recurse -Force -ErrorAction SilentlyContinue
            Info "Removed obsolete: $o"
        }
    }

    & git add -A | Out-Null
    & git commit -m "SlimRead update" --allow-empty | Out-Null
    & git branch -M main | Out-Null

    $origin = (& git remote get-url origin 2>$null)
    if ($LASTEXITCODE -eq 0 -and $origin) {
        & git push origin main
        if ($LASTEXITCODE -ne 0) {
            Stop-With 'Push failed' @(
                'Usually an expired login: gh auth login --web',
                'Or the remote is ahead: git pull --rebase, then run again.'
            )
        }
        Good 'Pushed'
    } else {
        Info 'PUBLIC repos get unlimited macOS build minutes; private bill at 10x.'
        $vis = if (Ask 'Make the repository public?') { '--public' } else { '--private' }
        & gh repo create slimread $vis --source . --remote origin --push
        if ($LASTEXITCODE -ne 0) { Stop-With 'Could not create the repository' @('See the message above.') }
        Good "Created github.com/$account/slimread"
    }

    Line
    Info 'If you only changed tweaks/, you are already done - every installed copy'
    Info 'picks those up on its next launch. No release needed.'
    Line
    if (-not (Ask 'Publish a new app build as well? (only needed for native code changes)')) {
        Write-Host ''
        Write-Host '  ============================================================' -ForegroundColor Green
        Write-Host '   Pushed. Tweaks are live.' -ForegroundColor Green
        Write-Host '  ============================================================' -ForegroundColor Green
        Line
        exit 0
    }

    Head '4. Publishing a release'

    $version = Read-Host '    Version number (e.g. 1.1)'
    if (-not $version) { Stop-With 'No version given' @('Run again and enter something like 1.1') }

    & gh workflow run 'release-ipa.yml' -f version=$version
    if ($LASTEXITCODE -ne 0) {
        Stop-With 'Could not start the release build' @(
            "Start it by hand at https://github.com/$account/slimread/actions",
            'Choose "Publish release", then Run workflow.'
        )
    }

    Info 'Building and publishing. Usually 2-4 minutes.'
    Start-Sleep -Seconds 8
    $runId = (& gh run list --workflow release-ipa.yml --limit 1 --json databaseId --jq '.[0].databaseId' 2>$null)
    if ($runId) {
        & gh run watch $runId.Trim() --exit-status
        $conclusion = (& gh run view $runId.Trim() --json conclusion --jq '.conclusion' 2>$null)
        if ($conclusion -ne 'success') {
            Warn 'The build failed. Log follows.'
            & gh run view $runId.Trim() --log-failed
            Stop-With 'Release build failed' @(
                "Full log: https://github.com/$account/slimread/actions/runs/$($runId.Trim())"
            )
        }
    }

    Write-Host ''
    Write-Host '  ============================================================' -ForegroundColor Green
    Write-Host "   Published v$version." -ForegroundColor Green
    Write-Host '  ============================================================' -ForegroundColor Green
    Line
    Info 'Anyone who runs SlimRead.bat now gets this build. Existing users pick it'
    Info 'up automatically the next time they re-run it to renew their certificate.'
    Line
}
finally { Pop-Location }
