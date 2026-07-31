<#
    SlimRead.ps1 - does everything, in order, and explains itself when something breaks.

    Run it by double-clicking "SlimRead.bat". Safe to run repeatedly: it works out what
    is already done and picks up from there.

      1. clears the downloaded-file block that stops scripts running
      2. installs winget if missing (and works without it if that fails)
      3. installs Git and the GitHub CLI
      4. signs you in to GitHub
      5. creates the repo, or pushes your changes to the one you have
      6. builds on a GitHub macOS runner and downloads the IPA
      7. checks the Apple drivers Sideloadly needs
      8. prints the on-phone steps

    No step closes the window on failure. Every failure says what happened and what to do.
#>

$ErrorActionPreference = 'Stop'
$ProjectDir = $PSScriptRoot
$script:Failed = $false

# ---------------------------------------------------------------- output helpers

function Line { param([string]$t = '', [string]$c = 'Gray') Write-Host $t -ForegroundColor $c }
function Head { param([string]$t) Write-Host ''; Write-Host "  $t" -ForegroundColor Cyan; Write-Host ('  ' + ('-' * 60)) -ForegroundColor DarkGray }
function Good { param([string]$t) Write-Host "    [ok] $t" -ForegroundColor Green }
function Warn { param([string]$t) Write-Host "    [!] $t" -ForegroundColor Yellow }
function Info { param([string]$t) Write-Host "    $t" -ForegroundColor Gray }

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
    Write-Host '   Nothing was damaged. Fix the above and run this file again.' -ForegroundColor Gray
    Write-Host ''
    $script:Failed = $true
    exit 1
}

function Ask { param([string]$q) return ((Read-Host "    $q (Y/n)") -notmatch '^[Nn]') }

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

# ---------------------------------------------------------------- banner

Clear-Host
Write-Host ''
Write-Host '  ============================================================' -ForegroundColor Magenta
Write-Host '   SlimRead - build the app and get it onto your iPhone' -ForegroundColor Magenta
Write-Host '  ============================================================' -ForegroundColor Magenta
Line
Info 'Compiling an iOS app needs macOS, so this uses a free GitHub macOS'
Info 'runner to build, then you sign and install it locally.'
Line

# ---------------------------------------------------------------- 0. sanity

Head '0. Checking the folder'

if (-not (Test-Path (Join-Path $ProjectDir 'SlimRead.xcodeproj'))) {
    Stop-With "This script is not in the SlimRead project folder" @(
        "It is currently in: $ProjectDir",
        "It must sit beside SlimRead.xcodeproj, tweaks/ and README.md.",
        "If you ran it from a zip preview window, extract the zip properly first.",
        "Never run it from C:\Windows\System32 - that is the folder an admin",
        "  PowerShell window opens in, and Git will refuse to work there."
    )
}
Good "Project folder: $ProjectDir"

# Mark-of-the-Web: files out of a downloaded zip are blocked from running.
try {
    Get-ChildItem $ProjectDir -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
    Good 'Cleared the downloaded-file block on all project files'
} catch {
    Warn 'Could not unblock every file, continuing anyway'
}

# ---------------------------------------------------------------- 1. tooling

Head '1. Tools (Git and GitHub CLI)'

function Install-WingetIfPossible {
    if (Have 'winget') { return $true }

    Info 'winget not found. Trying to register the App Installer already on Windows...'
    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop
        Update-PathFromRegistry
        if (Have 'winget') { Good 'winget registered'; return $true }
    } catch { }

    if (Test-Admin) {
        Info 'Installing winget via the official PowerShell module (needs a moment)...'
        try {
            $progressPreference = 'silentlyContinue'
            Install-PackageProvider -Name NuGet -Force -ErrorAction Stop | Out-Null
            Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery -ErrorAction Stop | Out-Null
            Repair-WinGetPackageManager -AllUsers -ErrorAction Stop
            Update-PathFromRegistry
            if (Have 'winget') { Good 'winget installed'; return $true }
        } catch {
            Warn "winget install failed: $($_.Exception.Message)"
        }
    } else {
        Info 'Not running as administrator, so the winget repair route is unavailable.'
    }

    Warn 'Carrying on without winget - the installers can be fetched directly.'
    return $false
}

function Get-LatestAsset {
    param([string]$Repo, [string]$Pattern)
    $uri = "https://api.github.com/repos/$Repo/releases/latest"
    $release = Invoke-RestMethod -Uri $uri -Headers @{ 'User-Agent' = 'SlimRead' } -TimeoutSec 30
    $asset = $release.assets | Where-Object { $_.name -like $Pattern } | Select-Object -First 1
    if (-not $asset) { throw "No asset matching $Pattern in $Repo" }
    return $asset.browser_download_url
}

function Install-Direct {
    param([string]$Name, [string]$Repo, [string]$Pattern, [string]$SilentArgs)
    Info "Downloading $Name..."
    $url = Get-LatestAsset -Repo $Repo -Pattern $Pattern
    $file = Join-Path $env:TEMP (Split-Path $url -Leaf)
    $progressPreference = 'silentlyContinue'
    Invoke-WebRequest -Uri $url -OutFile $file -UseBasicParsing -TimeoutSec 300
    Info "Running the $Name installer - approve the Windows prompt if it appears."
    if ($file -like '*.msi') {
        Start-Process msiexec.exe -ArgumentList "/i `"$file`" $SilentArgs" -Wait
    } else {
        Start-Process $file -ArgumentList $SilentArgs -Wait
    }
    Update-PathFromRegistry
}

function Ensure-Tool {
    param([string]$Exe, [string]$WingetId, [string]$Repo, [string]$Pattern, [string]$SilentArgs, [string[]]$Fallbacks)

    if (Have $Exe) { Good "$Exe already installed"; return }

    Info "$Exe is missing - installing it."

    if (Have 'winget') {
        try {
            winget install --id $WingetId --exact --silent --accept-source-agreements --accept-package-agreements | Out-Null
            Update-PathFromRegistry
        } catch { Warn "winget could not install $WingetId" }
    }

    if (-not (Have $Exe)) {
        try { Install-Direct -Name $Exe -Repo $Repo -Pattern $Pattern -SilentArgs $SilentArgs }
        catch { Warn "Direct download failed: $($_.Exception.Message)" }
    }

    if (-not (Have $Exe)) {
        foreach ($p in $Fallbacks) {
            if (Test-Path $p) { $env:Path = "$env:Path;$(Split-Path $p)"; break }
        }
    }

    if (-not (Have $Exe)) {
        Stop-With "$Exe is still not available" @(
            "Install it by hand, then run this file again:",
            "  Git         https://git-scm.com/download/win",
            "  GitHub CLI  https://cli.github.com",
            "If you just installed it, close this window and open a NEW one -",
            "  PATH does not refresh inside a window that is already open."
        )
    }
    Good "$Exe installed"
}

Install-WingetIfPossible | Out-Null

Ensure-Tool -Exe 'git' -WingetId 'Git.Git' `
    -Repo 'git-for-windows/git' -Pattern 'Git-*-64-bit.exe' `
    -SilentArgs '/VERYSILENT /NORESTART /NOCANCEL /SP-' `
    -Fallbacks @("$env:ProgramFiles\Git\cmd\git.exe")

Ensure-Tool -Exe 'gh' -WingetId 'GitHub.cli' `
    -Repo 'cli/cli' -Pattern 'gh_*_windows_amd64.msi' `
    -SilentArgs '/qn /norestart' `
    -Fallbacks @("$env:ProgramFiles\GitHub CLI\gh.exe")

# ---------------------------------------------------------------- 2. github

Head '2. GitHub sign-in'

& gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
    Info 'A browser will open. Copy the code shown here, paste it in the browser, approve.'
    Info 'When it asks about the Git protocol, choose HTTPS.'
    Line
    & gh auth login --hostname github.com --git-protocol https --web
    if ($LASTEXITCODE -ne 0) {
        Stop-With 'GitHub sign-in did not complete' @(
            'Run this file again and finish the browser step.',
            'If the browser never opened, run: gh auth login --web',
            'A free GitHub account is required: https://github.com/signup'
        )
    }
}
$account = (& gh api user --jq '.login').Trim()
Good "Signed in as $account"

# ---------------------------------------------------------------- 3. repo

Head '3. Repository'

Push-Location $ProjectDir
try {
    if (-not (Test-Path (Join-Path $ProjectDir '.git'))) {
        & git init -b main | Out-Null
        Good 'Created a local repository'
    }

    if (-not (& git config user.email)) { & git config user.email "$account@users.noreply.github.com" }
    if (-not (& git config user.name))  { & git config user.name  "$account" }

    # Tidy files this project no longer uses, so they do not linger in the repo.
    $obsolete = @('Build-SlimRead.ps1', 'RUN ME - Build SlimRead.bat', 'Build and Download IPA.bat', '.write_test', '__t', 'SlimRead.swiftpm')
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
        Info "Pushing to $origin"
        & git push origin main
        if ($LASTEXITCODE -ne 0) {
            Stop-With 'Push to GitHub failed' @(
                'Most often this is an expired login. Fix with: gh auth login --web',
                'If it says the remote has commits you do not have, run: git pull --rebase',
                'Then run this file again.'
            )
        }
        Good 'Pushed'
    } else {
        Info 'PUBLIC repos get unlimited free macOS build minutes.'
        Info 'PRIVATE repos bill macOS time at 10x against your monthly allowance.'
        $vis = if (Ask 'Make the repository public?') { '--public' } else { '--private' }

        $repo = 'slimread'
        & gh repo view "$account/$repo" *> $null
        if ($LASTEXITCODE -eq 0) {
            $repo = "slimread-$(Get-Random -Minimum 1000 -Maximum 9999)"
            Warn "You already have a 'slimread' repo, using '$repo'"
        }

        & gh repo create $repo $vis --source . --remote origin --push
        if ($LASTEXITCODE -ne 0) {
            Stop-With 'Could not create the repository' @(
                'Check the message above - a name clash is the usual cause.',
                'You can also create it manually at https://github.com/new and then run:',
                '  git remote add origin https://github.com/YOU/slimread.git',
                '  git push -u origin main'
            )
        }
        Good "Created github.com/$account/$repo"
    }

    # ------------------------------------------------------------ 4. build

    Head '4. Building on a macOS runner'

    Info 'Waiting for the build to appear...'
    $runId = $null
    for ($i = 0; $i -lt 30 -and -not $runId; $i++) {
        Start-Sleep -Seconds 4
        $runId = (& gh run list --limit 1 --json databaseId --jq '.[0].databaseId' 2>$null)
        if ($runId) { $runId = $runId.Trim() }
    }
    if (-not $runId) {
        Stop-With 'No build was triggered' @(
            "Open https://github.com/$account/slimread/actions and check the Actions tab.",
            'If Actions are disabled, enable them in the repo Settings > Actions.',
            'You can start one by hand from that page, then run this file again.'
        )
    }

    $status = (& gh run view $runId --json status --jq '.status' 2>$null)
    if ($status -eq 'completed') {
        Info 'That build already finished.'
    } else {
        Info "Build #$runId is running. Usually 1-4 minutes. Leave this window open."
        Line
        & gh run watch $runId --exit-status
    }

    $conclusion = (& gh run view $runId --json conclusion --jq '.conclusion' 2>$null)
    if ($conclusion -ne 'success') {
        Write-Host ''
        Warn "The build failed (conclusion: $conclusion)."
        Info 'The compiler output is below. Copy it if you want help reading it.'
        Line
        & gh run view $runId --log-failed
        Stop-With 'The app did not compile' @(
            'The full log is above and also at:',
            "  https://github.com/$account/slimread/actions/runs/$runId",
            'Paste the red lines to whoever is helping you and they can patch the source.'
        )
    }
    Good 'Build succeeded'

    # ------------------------------------------------------------ 5. ipa

    Head '5. Downloading the app'

    Get-ChildItem $ProjectDir -Filter *.ipa -File -ErrorAction SilentlyContinue | Remove-Item -Force
    & gh run download $runId --name SlimRead-ipa
    if ($LASTEXITCODE -ne 0) {
        Stop-With 'Could not download the built app' @(
            'The build succeeded, so the file exists. Download it by hand from:',
            "  https://github.com/$account/slimread/actions/runs/$runId",
            'Scroll to Artifacts at the bottom of that page.'
        )
    }

    $ipa = Get-ChildItem $ProjectDir -Filter *.ipa -File | Select-Object -First 1
    if (-not $ipa) { Stop-With 'No .ipa appeared after downloading' @('Re-run this file.') }
    Good "$($ipa.Name) ready ($([math]::Round($ipa.Length / 1KB)) KB)"
    Info 'A small file is normal - iOS supplies the Swift runtime, so it is not bundled.'

    # ------------------------------------------------------------ 6. drivers

    Head '6. Checking what Sideloadly needs'

    $appleMobile = Test-Path "$env:CommonProgramFiles\Apple\Mobile Device Support"
    $storeItunes = $null -ne (Get-AppxPackage -Name 'AppleInc.iTunes' -ErrorAction SilentlyContinue)

    if ($storeItunes) {
        Warn 'You have the Microsoft Store version of iTunes.'
        Info 'Sideloadly cannot use its drivers. Uninstall it, then install the'
        Info 'desktop versions from apple.com:'
        Info '  https://www.apple.com/itunes/download/win64'
        Info '  https://support.apple.com/en-us/HT204283'
    } elseif ($appleMobile) {
        Good 'Apple Mobile Device Support is installed'
    } else {
        Warn 'Apple device drivers were not found.'
        Info 'Install BOTH from apple.com (not the Microsoft Store):'
        Info '  iTunes  https://www.apple.com/itunes/download/win64'
        Info '  iCloud  https://support.apple.com/en-us/HT204283'
    }

    $sideloadly = Test-Path "$env:ProgramFiles\Sideloadly\sideloadly.exe"
    if ($sideloadly) { Good 'Sideloadly is installed' }
    else { Warn 'Sideloadly is not installed: https://sideloadly.io' }

    # ------------------------------------------------------------ 7. phone

    Head '7. Putting it on the phone'
    Line
    Info '1. Plug the iPhone in with a DATA cable. Unlock it, tap Trust This Computer.'
    Info '2. Open Sideloadly. Pick your iPhone in the device list.'
    Info "3. Drag $($ipa.Name) onto the IPA box."
    Info '4. Type your Apple ID, press Start, enter your password and 2FA code.'
    Info '     If the password is rejected, make an app-specific password at'
    Info '     https://account.apple.com/account/manage and use that instead.'
    Line
    Info 'Then on the iPhone, first install only:'
    Info '5. Settings > Privacy & Security > Developer Mode > On > Restart.'
    Info '     After it reboots and you unlock, confirm Turn On and enter your passcode.'
    Info '6. Settings > General > VPN & Device Management > tap your Apple ID > Trust.'
    Line
    Info 'Open SlimRead. Tap the top of the screen for controls.'
    Line
    Warn 'It stops opening after 7 days - that is the free Apple certificate expiring.'
    Info 'Run this file again and re-sideload. Your logins and reading position survive.'
    Line

    Write-Host '  ============================================================' -ForegroundColor Green
    Write-Host '   Done.' -ForegroundColor Green
    Write-Host '  ============================================================' -ForegroundColor Green
    Line

    Start-Process explorer.exe "/select,`"$($ipa.FullName)`""
    if (-not $sideloadly) {
        if (Ask 'Open the Sideloadly download page?') { Start-Process 'https://sideloadly.io' }
    }
}
finally {
    Pop-Location
}
