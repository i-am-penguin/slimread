<#
    Publish-Update.ps1 - MAINTAINER ONLY. Run via "Publish Update.bat".

    Users never touch this. They run SlimRead.bat, which downloads whatever you
    last published.

    Assumes git and gh are installed and signed in - if you have pushed this repo
    once, they are. Anything missing is reported rather than silently installed.

    Reminder: changes to tweaks/ need only a push. Every installed copy picks them
    up on next launch. A release is only for native code.
#>

$ErrorActionPreference = 'Stop'
$ProjectDir = $PSScriptRoot

function Say  { param([string]$t = '', [string]$c = 'Gray') Write-Host "  $t" -ForegroundColor $c }
function Step { param([string]$t) Write-Host ''; Write-Host "  $t" -ForegroundColor Cyan }
function Ask  { param([string]$q) return ((Read-Host "  $q (Y/n)") -notmatch '^[Nn]') }

function Stop-With {
    param([string]$What, [string[]]$Fix)
    Write-Host ''
    Say "STOPPED: $What" Red
    Write-Host ''
    Say 'How to fix it:' Yellow
    foreach ($f in $Fix) { Say "  - $f" Yellow }
    Write-Host ''
    exit 1
}

Clear-Host
Write-Host ''
Say 'SlimRead - publish an update' Magenta
Write-Host ''

if (-not (Test-Path (Join-Path $ProjectDir 'SlimRead.xcodeproj'))) {
    Stop-With 'Not in the SlimRead project folder' @(
        "This script is in: $ProjectDir",
        'It must sit beside SlimRead.xcodeproj and tweaks/.'
    )
}

foreach ($tool in 'git', 'gh') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Stop-With "$tool is not installed" @(
            'Git         https://git-scm.com/download/win',
            'GitHub CLI  https://cli.github.com',
            'After installing, open a NEW window - PATH does not refresh in place.'
        )
    }
}

& gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
    Stop-With 'Not signed in to GitHub' @('Run: gh auth login --web', 'Choose HTTPS when asked about the Git protocol.')
}

Push-Location $ProjectDir
try {
    Step 'Pushing your changes'

    # Files earlier versions of this project shipped and no longer uses.
    foreach ($old in 'Build-SlimRead.ps1', 'RUN ME - Build SlimRead.bat', 'Build and Download IPA.bat',
                     '.write_test', '__t', 'SlimRead.swiftpm', 'source.json') {
        if (Test-Path (Join-Path $ProjectDir $old)) {
            & git rm -r --cached --quiet -- $old *> $null
            Remove-Item (Join-Path $ProjectDir $old) -Recurse -Force -ErrorAction SilentlyContinue
            Say "removed obsolete: $old"
        }
    }

    & git add -A | Out-Null
    & git commit -m "SlimRead update" --allow-empty | Out-Null
    & git push
    if ($LASTEXITCODE -ne 0) {
        Stop-With 'Push failed' @(
            'Expired login?  gh auth login --web',
            'Remote ahead?   git pull --rebase, then run again.'
        )
    }
    Say 'pushed' Green

    Write-Host ''
    Say 'If you only changed tweaks/, you are done - every installed copy picks'
    Say 'those up on its next launch.'
    Write-Host ''

    if (-not (Ask 'Publish a new app build too? (only for native code changes)')) {
        Write-Host ''
        Say 'Done. Tweaks are live.' Green
        Write-Host ''
        exit 0
    }

    Step 'Publishing a release'
    $version = Read-Host '  Version number (e.g. 1.1)'
    if (-not $version) { Stop-With 'No version given' @('Run again and enter something like 1.1') }

    & gh workflow run 'release-ipa.yml' -f version=$version
    if ($LASTEXITCODE -ne 0) {
        Stop-With 'Could not start the release build' @(
            'Start it by hand: repo > Actions > Publish release > Run workflow.'
        )
    }

    Say 'building, usually 2-4 minutes...'
    Start-Sleep -Seconds 8
    $runId = (& gh run list --workflow release-ipa.yml --limit 1 --json databaseId --jq '.[0].databaseId' 2>$null)
    if ($runId) {
        $runId = $runId.Trim()
        & gh run watch $runId --exit-status
        if ((& gh run view $runId --json conclusion --jq '.conclusion' 2>$null) -ne 'success') {
            & gh run view $runId --log-failed
            Stop-With 'Release build failed' @('The compiler output is above.')
        }
    }

    Write-Host ''
    Say "Published v$version. Anyone running SlimRead.bat now gets this build." Green
    Write-Host ''
}
finally { Pop-Location }
