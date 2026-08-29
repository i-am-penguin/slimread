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
$Owner = 'i-am-penguin'
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

# Writes the version marker into tweaks/tweaks.js, so the badge on the phone always
# reports what was actually published. Doing this by hand means forgetting it, and a
# forgotten bump reads exactly like an update that failed to arrive.
function Set-TweaksStamp {
    param([string]$AppVersion)

    $path = Join-Path $ProjectDir 'tweaks\tweaks.js'
    if (-not (Test-Path $path)) { return $null }

    $text = Get-Content $path -Raw
    $pattern = "(?m)^(\s*var TWEAKS_VERSION\s*=\s*')([^']*)('\s*;.*)$"
    $match = [regex]::Match($text, $pattern)
    if (-not $match.Success) {
        Say 'could not find TWEAKS_VERSION in tweaks/tweaks.js - badge not stamped' Yellow
        return $null
    }

    # Carry the build counter forward so every publish differs, even two in one minute
    # with no version change.
    $counter = 1
    if ($match.Groups[2].Value -match 'b(\d+)') { $counter = [int]$Matches[1] + 1 }

    $stamp = "$AppVersion b$counter " + (Get-Date -Format 'dd MMM HH:mm')

    # This lands inside a single-quoted JS string. A stray quote or backslash in a
    # typed version number would break the whole tweaks file for every installed copy.
    $stamp = ($stamp -replace "[^A-Za-z0-9 ._:-]", '')

    $updated = [regex]::Replace($text, $pattern, "`${1}$stamp`${3}")

    # WriteAllText, not Set-Content: PowerShell 5.1 writes a BOM for -Encoding utf8,
    # and this file is fetched and parsed as raw JS.
    [System.IO.File]::WriteAllText($path, $updated, (New-Object System.Text.UTF8Encoding($false)))
    return $stamp
}

# Builds the commit message from what is actually staged, so publishing never stops to
# ask. Typing one every time meant taking the default, and a history of identical
# "SlimRead update" lines is no history at all.
# Reads the bullet points under the top heading of CHANGELOG.md. That file is the
# single place describing what a version actually does - "Release v1.15 - tweaks
# (1 file)" tells nobody anything six versions later.
function Get-ChangelogEntries {
    $path = Join-Path $ProjectDir 'CHANGELOG.md'
    if (-not (Test-Path $path)) { return @() }

    $lines = Get-Content $path
    $inSection = $false
    $entries = @()
    foreach ($line in $lines) {
        if ($line -match '^##\s+') {
            if ($inSection) { break }      # reached the next section
            $inSection = $true
            continue
        }
        if (-not $inSection) { continue }
        if ($line -match '^\s*-\s+(.*)$') { $entries += $Matches[1].Trim() }
        elseif ($line -match '^\s{2,}\S' -and $entries.Count) {
            # continuation of the previous bullet
            $entries[-1] = ($entries[-1] + ' ' + $line.Trim())
        }
    }
    return $entries
}

# Stamps the top heading with the version just published, so the next run starts a
# fresh Unreleased section instead of re-reporting old notes.
function Close-ChangelogSection {
    param([string]$Version)

    $path = Join-Path $ProjectDir 'CHANGELOG.md'
    if (-not (Test-Path $path)) { return }

    $text = Get-Content $path -Raw
    # A version can legitimately be published twice - the first attempt failing
    # leaves the tag free, so the same number is reused. Stamping unconditionally
    # produced two "## v1.22" headings, and the release notes then depend on which
    # one the extractor stops at. Fold into the existing section instead.
    $existing = [regex]::Match($text, "(?m)^##\s+v$([regex]::Escape($Version))\b.*$")

    if ($existing.Success) {
        $newEntries = [regex]::Match($text, '(?ms)^##\s+Unreleased\s*$(.*?)(?=^##\s)')
        if ($newEntries.Success -and $newEntries.Groups[1].Value.Trim()) {
            $body = $newEntries.Groups[1].Value.TrimEnd()
            # Move the pending notes under the heading that is already there...
            $text = $text.Remove($newEntries.Index, $newEntries.Length).Insert(
                $newEntries.Index, "## Unreleased`r`n`r`n")
            $again = [regex]::Match($text, "(?m)^##\s+v$([regex]::Escape($Version))\b.*$")
            $text = $text.Insert($again.Index + $again.Length, "$body")
        }
    } else {
        $stamped = "## v$Version - " + (Get-Date -Format 'yyyy-MM-dd')
        $text = [regex]::Replace($text, '(?m)^##\s+Unreleased\s*$', "## Unreleased`r`n`r`n$stamped", 1)
    }

    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
}

function New-CommitMessage {
    param([string]$Version, [string]$Stamp)

    $files = @(& git diff --cached --name-only 2>$null | Where-Object { $_ })
    $when = Get-Date -Format 'dd MMM HH:mm'

    if (-not $files.Count) { return "No file changes - $when" }

    # Prefer a real description of the change over a file inventory.
    $notes = Get-ChangelogEntries
    if ($notes.Count) {
        # First sentence of the first bullet, clipped to a sane subject length.
        $subject = ($notes[0] -split '(?<=\.)\s' | Select-Object -First 1).TrimEnd('.')
        if ($subject.Length -gt 62) { $subject = $subject.Substring(0, 59).TrimEnd() + '...' }

        $head = if ($Version) { "v${Version}: " } else { '' }
        if ($notes.Count -gt 1) { return "$head$subject (+$($notes.Count - 1) more)" }
        return "$head$subject"
    }

    $areas = @()
    if ($files -like 'tweaks/*')                                 { $areas += 'tweaks' }
    if ($files -like '*.swift')                                  { $areas += 'app' }
    if (($files -like '*.plist') -or ($files -like '*.pbxproj')) { $areas += 'project' }
    if ($files -like '.github/*')                                { $areas += 'ci' }
    if (($files -like '*.ps1') -or ($files -like '*.bat'))       { $areas += 'scripts' }
    if ($files -like '*.md')                                     { $areas += 'docs' }

    $what  = if ($areas.Count) { $areas -join ', ' } else { 'files' }
    $count = "$($files.Count) file" + $(if ($files.Count -ne 1) { 's' } else { '' })

    # The version number goes in either way, so `git log` alone tells you which build
    # each change belongs to.
    if ($Version) { return "Release v$Version - $what ($count)" }
    if ($Stamp)   { return "Update $what ($count) - $Stamp" }
    return "Update $what ($count) - $when"
}

# Brings in work pushed from another device BEFORE anything local is touched.
#
# Without this the divergence is only discovered at the push, by which point the
# run has already stamped tweaks.js, rolled the changelog and made a commit - so
# the failure leaves the PC half-advanced and the obvious next move (forcing the
# push) silently destroys whatever the other device did.
function Sync-WithRemote {
    Step 'Checking for work from another device'

    & git fetch origin --quiet
    if ($LASTEXITCODE -ne 0) {
        Say 'could not reach GitHub - carrying on, the push will catch it' Yellow
        return
    }

    $upstream = (& git rev-parse --abbrev-ref '@{u}' 2>$null)
    if (-not $upstream) { Say 'no upstream branch set - skipping' Yellow; return }
    $upstream = $upstream.Trim()

    $counts = (& git rev-list --left-right --count "HEAD...$upstream" 2>$null)
    if (-not $counts) { return }

    $parts = @(($counts -split '\s+') | Where-Object { $_ })
    if ($parts.Count -lt 2) { return }
    $behind = [int]$parts[1]

    if ($behind -eq 0) { Say 'up to date with GitHub' Green; return }

    Say "$behind commit(s) on GitHub that this PC does not have" Yellow
    Say 'bringing them in first, before anything here is committed'

    # --autostash so uncommitted edits on this PC are set aside and put back.
    & git pull --rebase --autostash
    if ($LASTEXITCODE -ne 0) {
        & git rebase --abort *> $null
        Stop-With 'Your work and the other device''s work overlap' @(
            'Both changed the same lines, so they cannot be combined automatically.',
            'Sort it out by hand, then run this again:',
            '    git pull --rebase',
            '    ...fix the conflicting files, then:',
            '    git add -A ; git rebase --continue',
            'Nothing was committed or pushed, so nothing here is lost.'
        )
    }

    Say 'merged - this PC now has everything' Green
}

Push-Location $ProjectDir
try {
    # Always reconcile first. Everything below writes to the working tree.
    Sync-WithRemote

    # ---- decide what is being published, BEFORE anything is committed ----------
    #
    # The version has to be known before the commit, or the stamp baked into
    # tweaks.js would name the previous release rather than the one going out.

    $current = ''
    $rawRelease = (& gh release view --json tagName) -join ''
    if ($rawRelease) {
        try { $current = [string]($rawRelease | ConvertFrom-Json).tagName } catch { }
    }

    Write-Host ''
    Say 'Changes to tweaks/ go live on their own - every installed copy picks them'
    Say 'up on its next launch. A build is only needed for native code.'
    Write-Host ''

    $publishBuild = Ask 'Publish a new app build too? (only for native code changes)'
    $version = $null

    if ($publishBuild) {
        Step 'Version'

        $suggested = '1.0'
        if ($current) {
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

        # Auto-increment. Set SLIMREAD_VERSION before running to override, e.g.
        #   $env:SLIMREAD_VERSION = '2.0'
        # A prompt here was answered with the suggested number every single time.
        $version = if ($env:SLIMREAD_VERSION) { $env:SLIMREAD_VERSION.Trim() -replace '^v', '' } else { $suggested }
        Say "new version:          $version" Green

        # A tag cannot be reused, so catch it here rather than after a 4-minute build.
        & gh release view "v$version" 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Stop-With "Version $version is already published" @(
                "Pick a number that is not taken - $suggested is free.",
                'Git tags cannot be reused, so GitHub rejects duplicates.'
            )
        }
    }

    # Stamp against whatever version the phone will actually be running: the new one
    # if a build is going out, otherwise the release already installed.
    $stampVersion = if ($version) { $version }
                    elseif ($current) { ($current -replace '^v', '') }
                    else { '0' }

    $stamp = Set-TweaksStamp -AppVersion $stampVersion
    if ($stamp) { Say "badge stamped:  $stamp" Green }

    # Roll CHANGELOG.md's Unreleased section over to this version before committing,
    # so the notes ship inside the same commit they describe.
    $notes = Get-ChangelogEntries
    if ($notes.Count) {
        Write-Host ''
        Say "release notes ($($notes.Count)):" Cyan
        foreach ($n in $notes) { Say "  - $n" }
        if ($version) { Close-ChangelogSection -Version $version }
    } else {
        Say 'CHANGELOG.md has no entries under the top heading - notes will be generic' Yellow
    }

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

    $message = New-CommitMessage -Version $version -Stamp $stamp
    Say "commit: $message"
    & git commit -m $message --allow-empty | Out-Null
    & git push
    if ($LASTEXITCODE -ne 0) {
        Stop-With 'Push failed' @(
            'Expired login?  gh auth login --web',
            'Remote ahead?   git pull --rebase, then run again.'
        )
    }
    Say 'pushed' Green

    if (-not $publishBuild) {
        Write-Host ''
        Say 'Done - committed, pushed, and tweaks are live on every installed copy.' Green
        if ($stamp) {
            Write-Host ''
            Say "On the phone: reopen the app and the badge should read  $stamp"
            Say 'Not showing? Give it five minutes - GitHub caches raw files that long.'
        }
        Write-Host ''
        exit 0
    }

    Step 'Publishing a release'
    Say "publishing v$version"

    # Note which run is newest BEFORE dispatching, so the new one can be told apart.
    # Grabbing "the latest run" after a fixed sleep picks up the PREVIOUS release
    # whenever GitHub has not registered the new one yet - and that one already says
    # success, so the script would sail past a build that never happened.
    # No --jq anywhere in this script's polling. PowerShell 5.1 re-quotes arguments
    # when it hands them to a native exe, and a jq expression containing spaces and
    # double quotes arrives at gh mangled - it then returns nothing, which reads as
    # "status unknown" forever. ConvertFrom-Json has no such problem.
    function Latest-RunId {
        $raw = (& gh run list --workflow release-ipa.yml --limit 1 --json databaseId) -join ''
        if (-not $raw) { return '' }
        try {
            $runs = $raw | ConvertFrom-Json
            if ($runs -and $runs.Count -gt 0) { return [string]$runs[0].databaseId }
        } catch { }
        return ''
    }

    $previousRun = Latest-RunId

    & gh workflow run 'release-ipa.yml' -f version=$version
    if ($LASTEXITCODE -ne 0) {
        Stop-With 'Could not start the release build' @(
            'Start it by hand: repo > Actions > Publish release > Run workflow.'
        )
    }

    Write-Host ''

    $runId = ''
    foreach ($attempt in 1..30) {
        Write-Host ("`r  waiting for GitHub to pick it up... {0}s   " -f ($attempt * 4)) -NoNewline -ForegroundColor DarkGray
        Start-Sleep -Seconds 4
        $candidate = Latest-RunId
        if ($candidate -and $candidate -ne $previousRun) { $runId = $candidate; break }
    }
    Write-Host "`r                                              `r" -NoNewline

    if (-not $runId) {
        Stop-With 'The release build never started' @(
            'GitHub accepted the request but no run appeared within two minutes.',
            "Check it by hand: https://github.com/$Owner/$Repo/actions",
            "Nothing was released, so v$version is still free to use."
        )
    }

    Say "run:  https://github.com/$Owner/$Repo/actions/runs/$runId" DarkGray
    Write-Host ''

    # Poll and report, rather than handing off to `gh run watch` - that printed
    # nothing at all here, so a 3-minute build looked like a hung script.
    $spin = '|/-\'
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $status = ''
    $conclusion = ''
    $tick = 0

    $unreadable = 0

    while ($true) {
        $raw = (& gh run view $runId --json status,conclusion) -join ''
        $ok = $false
        if ($raw) {
            try {
                $info = $raw | ConvertFrom-Json
                if ($info.status) { $status = [string]$info.status; $ok = $true }
                $conclusion = [string]$info.conclusion
            } catch { }
        }

        # Never spin silently on a status that cannot be read.
        if ($ok) { $unreadable = 0 } else { $unreadable++ }
        if ($unreadable -ge 8) {
            Write-Host ''
            Stop-With 'Cannot read the build status' @(
                'gh returned nothing usable for 8 tries running.',
                "The build itself is probably fine - watch it here:",
                "  https://github.com/$Owner/$Repo/actions/runs/$runId",
                "Then download the IPA from the release page for v$version."
            )
        }

        $label = switch ($status) {
            'queued'      { 'queued - waiting for a macOS runner' }
            'in_progress' { 'building on macOS' }
            'completed'   { 'finishing up' }
            default       { if ($status) { $status } else { 'checking' } }
        }

        Write-Host ("`r  [{0}] {1,-38} {2:mm\:ss}   " -f `
            $spin[$tick % 4], $label, $clock.Elapsed) -NoNewline -ForegroundColor Cyan

        if ($status -eq 'completed') { break }

        if ($clock.Elapsed.TotalMinutes -ge 20) {
            Write-Host ''
            Stop-With 'The build is taking far too long' @(
                "Check it: https://github.com/$Owner/$Repo/actions/runs/$runId",
                "Nothing was released, so v$version is still free to use."
            )
        }

        $tick++
        Start-Sleep -Seconds 3
    }

    Write-Host ''
    if ($conclusion -ne 'success') {
        Write-Host ''
        & gh run view $runId --log-failed
        Stop-With "Release build $conclusion" @(
            'The compiler output is above.',
            "Full log: https://github.com/$Owner/$Repo/actions/runs/$runId"
        )
    }
    Say "build succeeded in $([int]$clock.Elapsed.TotalMinutes)m $($clock.Elapsed.Seconds)s" Green

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
