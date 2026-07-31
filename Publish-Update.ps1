<#
    Publish-Update.ps1 - MAINTAINER ONLY. Run via "Publish Update.bat".

    Users never touch this. They run SlimRead.bat, which downloads whatever you
    last published.

    Assumes git and gh are installed and signed in - if you have pushed this repo
    once, they are. Anything missing is reported rather than silently installed.

    Reminder: changes to tweaks/ need only a push. Every installed copy picks them
    up on next launch. A release is only for native code.
#>

# Native tools (git, gh) write ordinary output to stderr, and 'Stop' would treat
# that as fatal. Exit codes are checked explicitly after every call instead.
$ErrorActionPreference = 'Continue'
$ProjectDir = $PSScriptRoot

# Where this publishes to. Keep in step with the same two lines in SlimRead.ps1.
$Owner = 'llllllllllllllppppppppppp'
$Repo  = 'slimread'

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

    # A stale index.lock blocks every git command. It is left behind when a git
    # process is killed, a tool crashes, or an editor holds the repo open.
    # Safe to clear as long as nothing is actually using it right now.
    $lock = Join-Path $ProjectDir '.git\index.lock'
    if (Test-Path $lock) {
        if (Get-Process git -ErrorAction SilentlyContinue) {
            Stop-With 'A git process is already running' @(
                'Wait for it to finish, or close any editor with this folder open,',
                'then run this file again.'
            )
        }
        Remove-Item $lock -Force -ErrorAction SilentlyContinue
        if (Test-Path $lock) {
            Stop-With 'Could not clear a stale git lock file' @(
                "Delete it by hand:  Remove-Item `"$lock`" -Force",
                'Then run this file again.'
            )
        }
        Say 'cleared a stale git lock'
    }

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

    $summary = (& git diff --cached --shortstat 2>$null)
    if ($summary) { Say "changes: $($summary.Trim())" } else { Say 'no file changes' }

    $message = Read-Host '  Commit message [SlimRead update]'
    if (-not $message) { $message = 'SlimRead update' }
    & git commit -m $message --allow-empty | Out-Null
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
        Say 'Done - committed, pushed, and tweaks are live on every installed copy.' Green
        Write-Host ''
        exit 0
    }

    Step 'Publishing a release'

    # Show what is already out there, and offer the obvious next number.
    $current = (& gh release view --json tagName --jq '.tagName' 2>$null | Select-Object -First 1)
    $suggested = '1.0'

    if ($LASTEXITCODE -eq 0 -and $current) {
        $current = $current.Trim()
        Say "currently published:  $current"
        $parts = ($current -replace '^v', '') -split '\.'
        if ($parts[-1] -match '^\d+$') {
            # Keep the original width, so 1.02 becomes 1.03 rather than 1.3.
            $width = $parts[-1].Length
            $parts[-1] = ([int]$parts[-1] + 1).ToString().PadLeft($width, '0')
            $suggested = ($parts -join '.')
        } else {
            $suggested = $current -replace '^v', ''
        }
    } else {
        Say 'no releases published yet - this will be the first'
    }

    $version = Read-Host "  New version number [$suggested]"
    if (-not $version) { $version = $suggested }
    $version = ($version.Trim() -replace '^v', '')
    if (-not $version) { Stop-With 'No version given' @('Run again and enter something like 1.1') }

    # A tag cannot be reused, so catch it here rather than after a 4-minute build.
    & gh release view "v$version" 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Stop-With "Version $version is already published" @(
            "Pick a number that is not taken - $suggested is free.",
            'Git tags cannot be reused, so GitHub rejects duplicates.'
        )
    }
    Say "publishing v$version"

    # Note which run is newest BEFORE dispatching, so the new one can be told apart.
    # Grabbing "the latest run" after a fixed sleep picks up the PREVIOUS release
    # whenever GitHub has not registered the new one yet - and that one already says
    # success, so the script would sail past a build that never happened.
    function Latest-RunId {
        $id = (& gh run list --workflow release-ipa.yml --limit 1 --json databaseId --jq '.[0].databaseId' 2>$null)
        if ($id) { return $id.Trim() }
        return ''
    }

    $previousRun = Latest-RunId

    & gh workflow run 'release-ipa.yml' -f version=$version
    if ($LASTEXITCODE -ne 0) {
        Stop-With 'Could not start the release build' @(
            'Start it by hand: repo > Actions > Publish release > Run workflow.'
        )
    }

    Say 'building, usually 2-4 minutes...'

    $runId = ''
    foreach ($attempt in 1..30) {
        Start-Sleep -Seconds 4
        $candidate = Latest-RunId
        if ($candidate -and $candidate -ne $previousRun) { $runId = $candidate; break }
    }

    if (-not $runId) {
        Stop-With 'The release build never started' @(
            'GitHub accepted the request but no run appeared within two minutes.',
            "Check it by hand: https://github.com/$Owner/$Repo/actions",
            "Nothing was released, so v$version is still free to use."
        )
    }

    & gh run watch $runId --exit-status
    $conclusion = (& gh run view $runId --json conclusion --jq '.conclusion' 2>$null)
    if ($conclusion) { $conclusion = $conclusion.Trim() }
    if ($conclusion -ne 'success') {
        & gh run view $runId --log-failed
        Stop-With 'Release build failed' @('The compiler output is above.')
    }

    Write-Host ''
    Say "Published v$version. Anyone running SlimRead.bat now gets this build." Green
    Write-Host ''

    # You are the maintainer, but you also want it on your own phone. Publishing
    # only puts the build on GitHub, so fetch it back here ready for Sideloadly.
    if (Ask 'Download this build to sideload onto your own phone?') {
        # Fetch to one side first. Clearing the folder before downloading means a
        # failure here leaves you with no IPA at all, including the one that worked.
        $staging = Join-Path $ProjectDir '.ipa-download'
        Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $staging -Force | Out-Null

        & gh release download "v$version" --pattern 'SlimRead.ipa' --dir $staging
        $fetched = Join-Path $staging 'SlimRead.ipa'

        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $fetched)) {
            Say 'Could not download it automatically. Get it from:' Yellow
            Say "  https://github.com/$Owner/$Repo/releases/tag/v$version" Yellow
            Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Get-ChildItem $ProjectDir -Filter *.ipa -File -ErrorAction SilentlyContinue | Remove-Item -Force
            $target = Join-Path $ProjectDir 'SlimRead.ipa'
            Move-Item $fetched $target -Force
            Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue

            $ipa = Get-Item $target
            Say "SlimRead.ipa is in this folder ($([math]::Round($ipa.Length / 1KB)) KB)" Green
            Write-Host ''
            Say 'Now drag it onto Sideloadly with your phone connected.'
            Say 'Tick auto-refresh so it renews itself each week.'
            Start-Process explorer.exe "/select,`"$($ipa.FullName)`""
        }
        Write-Host ''
    }
}
finally { Pop-Location }
