<#
    Build-SlimRead.ps1

    Takes the SlimRead source next to this script, builds it on GitHub's free macOS
    runners, and drops a ready-to-sign SlimRead.ipa on your Desktop.

    You need: a GitHub account (free). Everything else it installs for you.

    Why GitHub: compiling an iOS app requires macOS. There is no way around that on
    Windows. GitHub rents you a Mac for the four minutes it takes, at no cost.
#>

$ErrorActionPreference = 'Stop'
$ProjectDir = $PSScriptRoot

function Say([string]$msg, [string]$colour = 'White') { Write-Host $msg -ForegroundColor $colour }
function Step([string]$msg) { Write-Host ""; Write-Host "==> $msg" -ForegroundColor Cyan }
function Die([string]$msg) { Write-Host ""; Write-Host "FAILED: $msg" -ForegroundColor Red; Write-Host ""; Read-Host "Press Enter to close"; exit 1 }

function Update-PathFromRegistry {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

function Ensure-Tool([string]$exe, [string]$wingetId, [string[]]$fallbackPaths) {
    if (Get-Command $exe -ErrorAction SilentlyContinue) {
        Say "    $exe is already installed." Green
        return
    }

    Say "    $exe not found - installing $wingetId ..." Yellow
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Die "winget is not available on this PC. Install '$wingetId' manually, then re-run this script."
    }

    winget install --id $wingetId --exact --silent `
        --accept-source-agreements --accept-package-agreements | Out-Null

    Update-PathFromRegistry

    if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) {
        foreach ($p in $fallbackPaths) {
            if (Test-Path $p) { $env:Path = "$env:Path;$(Split-Path $p)" ; break }
        }
    }

    if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) {
        Die "$exe still is not on PATH. Close this window, open a NEW PowerShell, and run the script again - a fresh window usually picks it up."
    }
    Say "    $exe installed." Green
}

# ----------------------------------------------------------------------------

Clear-Host
Say "======================================================" Magenta
Say "  SlimRead - build an IPA from Windows" Magenta
Say "======================================================" Magenta
Say ""
Say "This will:"
Say "  1. install Git and the GitHub CLI (if you don't have them)"
Say "  2. sign you in to GitHub in your browser"
Say "  3. upload this project to a repo of your own"
Say "  4. build it on a macOS runner (about 4 minutes)"
Say "  5. download SlimRead.ipa to your Desktop"
Say ""
Say "Nothing is installed on your phone yet - that's the last step, by hand."
Say ""
if ((Read-Host "Continue? (Y/n)") -match '^[Nn]') { exit 0 }

if (-not (Test-Path (Join-Path $ProjectDir 'SlimRead.xcodeproj'))) {
    Die "Can't find SlimRead.xcodeproj next to this script. Make sure you EXTRACTED the zip (don't run it from inside the zip viewer) and that this script sits beside the SlimRead folder."
}

Step "Checking tools"
Ensure-Tool 'git' 'Git.Git' @("$env:ProgramFiles\Git\cmd\git.exe", "${env:ProgramFiles(x86)}\Git\cmd\git.exe")
Ensure-Tool 'gh'  'GitHub.cli' @("$env:ProgramFiles\GitHub CLI\gh.exe", "${env:ProgramFiles(x86)}\GitHub CLI\gh.exe")

Step "Signing in to GitHub"
& gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
    Say "    A browser window will open. Sign in and paste the code shown here." Yellow
    & gh auth login --hostname github.com --git-protocol https --web
    if ($LASTEXITCODE -ne 0) { Die "GitHub sign-in did not complete." }
} else {
    Say "    Already signed in." Green
}

$account = (& gh api user --jq '.login').Trim()
Say "    Signed in as $account." Green

Step "Choosing repository visibility"
Say "    PUBLIC repos get unlimited free macOS build minutes."
Say "    PRIVATE repos bill macOS minutes at 10x against your free monthly allowance."
Say "    There are no secrets in this code, so public is the sensible pick."
$visibility = if ((Read-Host "    Make the repo public? (Y/n)") -match '^[Nn]') { '--private' } else { '--public' }

Step "Preparing the repository"
Push-Location $ProjectDir
try {
    if (-not (Test-Path (Join-Path $ProjectDir '.git'))) {
        & git init -b main | Out-Null
    }
    if (-not (& git config user.email)) { & git config user.email "$account@users.noreply.github.com" }
    if (-not (& git config user.name))  { & git config user.name  "$account" }

    & git add -A | Out-Null
    & git commit -m "SlimRead" --allow-empty | Out-Null
    & git branch -M main | Out-Null

    $repo = 'slimread'
    & gh repo view "$account/$repo" *> $null
    if ($LASTEXITCODE -eq 0) {
        $repo = "slimread-$(Get-Random -Minimum 1000 -Maximum 9999)"
        Say "    You already have a 'slimread' repo, using '$repo' instead." Yellow
    }

    Step "Uploading to github.com/$account/$repo"
    & git remote remove origin *> $null
    & gh repo create $repo $visibility --source . --remote origin --push
    if ($LASTEXITCODE -ne 0) { Die "Upload failed. Scroll up for the reason." }
    Say "    Uploaded." Green

    Step "Building on a macOS runner"
    Say "    Waiting for the build to start ..."
    $runId = $null
    for ($i = 0; $i -lt 30 -and -not $runId; $i++) {
        Start-Sleep -Seconds 4
        $runId = (& gh run list --limit 1 --json databaseId --jq '.[0].databaseId' 2>$null)
        if ($runId) { $runId = $runId.Trim() }
    }
    if (-not $runId) {
        Die "The build never started. Open https://github.com/$account/$repo/actions and run 'Build unsigned IPA' manually."
    }

    Say "    Build #$runId running. This takes about 4 minutes - leave this window open." Yellow
    & gh run watch $runId --exit-status
    if ($LASTEXITCODE -ne 0) {
        Die "The build failed. See https://github.com/$account/$repo/actions/runs/$runId for the log, and send it to me."
    }
    Say "    Build succeeded." Green

    Step "Downloading the IPA"
    $staging = Join-Path $env:TEMP "slimread-$runId"
    Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    & gh run download $runId --name SlimRead-ipa --dir $staging
    if ($LASTEXITCODE -ne 0) { Die "Could not download the build artifact." }

    $ipa = Get-ChildItem -Path $staging -Filter *.ipa -Recurse | Select-Object -First 1
    if (-not $ipa) { Die "No .ipa found in the downloaded artifact." }

    $desktop = [Environment]::GetFolderPath('Desktop')
    $target  = Join-Path $desktop 'SlimRead.ipa'
    Copy-Item $ipa.FullName $target -Force

    Say ""
    Say "======================================================" Green
    Say "  Done. SlimRead.ipa is on your Desktop." Green
    Say "======================================================" Green
    Say ""
    Say "Last step - putting it on the phone:"
    Say ""
    Say "  1. Download Sideloadly:  https://sideloadly.io"
    Say "  2. Plug the iPhone into this PC with a cable, unlock it, tap Trust."
    Say "  3. Open Sideloadly, drag SlimRead.ipa onto it."
    Say "  4. Enter your Apple ID (it goes to Apple, not to Sideloadly) and press Start."
    Say "  5. On the phone: Settings > General > VPN & Device Management > trust yourself."
    Say ""
    Say "  It expires after 7 days. Re-run Sideloadly to renew - your Tapas login survives."
    Say "  AltStore (https://altstore.io) does that renewal automatically over Wi-Fi if"
    Say "  the weekly re-plug gets annoying."
    Say ""
    Say "  Rebuilding later after code changes: just re-run this script."
    Say ""

    Start-Process explorer.exe "/select,`"$target`""
    if ((Read-Host "Open the Sideloadly download page now? (Y/n)") -notmatch '^[Nn]') {
        Start-Process "https://sideloadly.io"
    }
}
finally {
    Pop-Location
}

Read-Host "Press Enter to close"
