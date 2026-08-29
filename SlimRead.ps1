<#
    SlimRead.ps1 - installs SlimRead on your iPhone.

    Run it by double-clicking SlimRead.bat.

    No GitHub account, no developer tools, no building. It downloads the finished app
    from the project's releases, makes sure the two Apple components are present, and
    walks you through the final steps.

    Nothing closes the window on failure. Every problem says what happened and what to do.
#>

$ErrorActionPreference = 'Stop'

# Where the finished app is published. Change these two lines if you fork the project.
$Owner = 'i-am-penguin'
$Repo  = 'slimread'

$IpaURL   = "https://github.com/$Owner/$Repo/releases/latest/download/SlimRead.ipa"
$WorkDir  = Join-Path ([Environment]::GetFolderPath('Desktop')) 'SlimRead'
$IpaPath  = Join-Path $WorkDir 'SlimRead.ipa'

# ---------------------------------------------------------------- output helpers

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
    Write-Host '   Nothing on your PC or phone was changed. Fix the above and run again.' -ForegroundColor Gray
    Write-Host ''
    exit 1
}

function Get-File {
    param([string]$Url, [string]$Dest, [string]$Label)
    $progressPreference = 'silentlyContinue'
    Info "Downloading $Label..."
    Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing -TimeoutSec 600
}

# ---------------------------------------------------------------- banner

Clear-Host
Write-Host ''
Write-Host '  ============================================================' -ForegroundColor Magenta
Write-Host '   SlimRead - install on your iPhone' -ForegroundColor Magenta
Write-Host '  ============================================================' -ForegroundColor Magenta
Line
Info 'A browser that hides the iOS status bar, for reading comics without'
Info 'the clock and battery sitting on top of the artwork.'
Line
Info 'You will need:'
Info '  - your iPhone and a data cable'
Info '  - an Apple ID (a spare one is fine, and is the safer choice)'
Line
Info 'Apple requires that apps installed outside the App Store are signed with'
Info 'YOUR OWN Apple ID. That is why this cannot be a simple double-click, and'
Info 'why no one can hand you a ready-to-run copy.'
Line
if (-not (Ask 'Ready to start?')) { exit 0 }

New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

# ---------------------------------------------------------------- 1. the app

Head '1. Downloading SlimRead'

try {
    Get-File -Url $IpaURL -Dest $IpaPath -Label 'the app'
} catch {
    Stop-With 'Could not download the app' @(
        "Check you are online, then try opening this in a browser:",
        "  https://github.com/$Owner/$Repo/releases/latest",
        'If that page says there are no releases yet, the app has not been',
        '  published. Ask whoever sent you this to publish one.',
        "Error was: $($_.Exception.Message)"
    )
}

$ipa = Get-Item $IpaPath
if ($ipa.Length -lt 10000) {
    Stop-With 'The downloaded file looks wrong' @(
        'It is too small to be the app - probably an error page.',
        "Open https://github.com/$Owner/$Repo/releases/latest and download SlimRead.ipa by hand.",
        "Then put it in: $WorkDir"
    )
}
Good "SlimRead.ipa downloaded ($([math]::Round($ipa.Length / 1KB)) KB)"
Info 'A small file is normal - iOS provides the Swift runtime, so it is not bundled.'

# ---------------------------------------------------------------- 2. apple bits

Head '2. Apple device drivers'

$driversPresent = Test-Path "$env:CommonProgramFiles\Apple\Mobile Device Support"
$storeItunes    = $null -ne (Get-AppxPackage -Name 'AppleInc.iTunes' -ErrorAction SilentlyContinue)

if ($storeItunes) {
    Warn 'You have the Microsoft Store version of iTunes installed.'
    Info 'Sideloadly cannot use its drivers - your phone will not appear.'
    Info 'Uninstall it first: Settings > Apps > iTunes > Uninstall.'
    Line
    if (Ask 'Have you uninstalled it?') { $storeItunes = $false } else {
        Stop-With 'The Microsoft Store iTunes has to go first' @(
            'Uninstall it, then run this file again.',
            'The desktop version from apple.com ships the drivers Sideloadly needs.'
        )
    }
}

if ($driversPresent -and -not $storeItunes) {
    Good 'Apple Mobile Device Support is installed'
} else {
    Warn 'The Apple drivers are missing.'
    Info 'iTunes supplies the drivers that let your phone be seen - that one matters.'
    Info 'iCloud only supplies Apple ID sign-in tokens, and Sideloadly can fetch those'
    Info 'from its own server instead (Advanced Options > Remote Anisette), so do not'
    Info 'get stuck if iCloud will not install.'
    Line
    if (Ask 'Download and run the installers now?') {
        $itunes = Join-Path $WorkDir 'iTunesSetup.exe'
        $icloud = Join-Path $WorkDir 'iCloudSetup.exe'
        try {
            Get-File -Url 'https://www.apple.com/itunes/download/win64' -Dest $itunes -Label 'iTunes (large, be patient)'
            Info 'Starting the iTunes installer - complete it, then come back here.'
            Start-Process $itunes -Wait
        } catch {
            Warn 'Automatic download failed. Get it manually:'
            Info '  https://www.apple.com/itunes/download/win64'
            Start-Process 'https://www.apple.com/itunes/download/win64'
        }
        try {
            Get-File -Url 'https://updates.cdn-apple.com/2020/windows/001-39935-20200911-1A70AA56-F448-11EA-8CC0-99D41950005E/iCloudSetup.exe' -Dest $icloud -Label 'iCloud'
            Info 'Starting the iCloud installer.'
            Start-Process $icloud -Wait
        } catch {
            Warn 'Automatic download failed.'
            Info '  Apple removed the standalone iCloud page, so use the link Sideloadly'
            Info '  publishes: sideloadly.io, under "Before you install" > Web iCloud.'
            Info '  Do NOT install iCloud from the Microsoft Store - it will not work.'
            Info '  You can also skip iCloud entirely and use Remote Anisette instead.'
            Start-Process 'https://sideloadly.io'
        }
    } else {
        Info 'Install them yourself before continuing:'
        Info '  iTunes  https://www.apple.com/itunes/download/win64'
        Info '  iCloud  sideloadly.io > "Before you install" > Web iCloud'
        Info 'IMPORTANT: the desktop versions, NOT the Microsoft Store ones.'
        Info 'Apple retired the iCloud download page, which is why the link is'
        Info 'Sideloadly rather than Apple. iCloud is optional if you use Remote Anisette.'
    }
}

# ---------------------------------------------------------------- 3. sideloadly

Head '3. Sideloadly'

$sideloadlyExe = "$env:ProgramFiles\Sideloadly\sideloadly.exe"
if (Test-Path $sideloadlyExe) {
    Good 'Sideloadly is installed'
} else {
    Warn 'Sideloadly is not installed. It is the tool that signs the app with your Apple ID.'
    if (Ask 'Open the Sideloadly download page?') {
        Start-Process 'https://sideloadly.io'
        Info 'Install it, then press Enter here.'
        Read-Host '    Press Enter once Sideloadly is installed'
    }
}

# ---------------------------------------------------------------- 4. phone

Head '4. Connect your iPhone'
Line
Info '1. Plug it in with a DATA cable (a charge-only cable will not work).'
Info '2. Unlock the phone.'
Info '3. Tap Trust This Computer, and enter your passcode.'
Line
Read-Host '    Press Enter once the phone is connected and trusted'

Head '5. Sign and install'
Line
Info 'Sideloadly will open now.'
Line
Info '1. Pick your iPhone in the iOS Device list at the top.'
Info '     Not listed? The Apple drivers in step 2 are the cause. Check the phone'
Info '     shows up in iTunes itself - if iTunes cannot see it, nothing can.'
Info '2. Drag SlimRead.ipa onto the IPA box (the folder will open for you).'
Info '3. Type your Apple ID into the Apple account box.'
Info '4. Tick the auto-refresh option - it renews the app for you every week.'
Info '5. Press Start, then enter your password and the 6-digit code from your phone.'
Line
Warn 'If sign-in fails, or it tells you to update iCloud for Windows:'
Info '  In Sideloadly, open Advanced Options and tick "Remote Anisette", then'
Info '  try again. That takes your local iCloud install out of the sign-in path,'
Info '  which is the usual cause since Apple removed the iCloud download page.'
Info '  Use your REAL Apple ID password - app-specific passwords do not work'
Info '  with a free Apple ID.'
Line
Info 'Wait for the log to say Done.'
Line

if (Test-Path $sideloadlyExe) { Start-Process $sideloadlyExe }
Start-Process explorer.exe "/select,`"$IpaPath`""

Read-Host '    Press Enter once Sideloadly says Done'

# ---------------------------------------------------------------- 5. on-device

Head '6. Two settings on the phone'
Line
Info 'The app is on your Home Screen now, but will not open yet. Two one-time steps.'
Line
Info 'A. Developer Mode'
Info '     Settings > Privacy & Security > Developer Mode > turn on > Restart.'
Info '     After it reboots and you unlock, confirm Turn On and enter your passcode.'
Line
Info '     This is required because free Apple IDs produce development-signed apps.'
Info '     It does not disable code signing, sandboxing or encryption.'
Line
Info 'B. Trust the certificate'
Info '     Settings > General > VPN & Device Management > tap your Apple ID > Trust.'
Line
Info '     No Developer App section there? The phone needs internet to check the'
Info '     certificate. Connect to Wi-Fi, leave Settings, go back in.'
Line

Read-Host '    Press Enter once both are done'

# ---------------------------------------------------------------- done

Write-Host ''
Write-Host '  ============================================================' -ForegroundColor Green
Write-Host '   Installed. Open SlimRead on your phone.' -ForegroundColor Green
Write-Host '  ============================================================' -ForegroundColor Green
Line
Info 'Tap the top of the screen - the notch area - to show the controls.'
Info 'Swipe in from the left edge to go back. Scroll to read.'
Info 'The guide is on the ? button any time.'
Line
Warn 'It will stop opening after 7 days.'
Info 'That is the free Apple certificate expiring, not a fault. Run this file'
Info 'again to renew it - your logins and reading position survive.'
Line
Info 'You can automate that away with Sideloadly itself:'
Info '  1. When sideloading, tick the auto-refresh option before pressing Start.'
Info '  2. In iTunes: your device > Summary > Options > tick "Sync with this'
Info '     iDevice over Wi-Fi", then Sync.'
Info 'Sideloadly then re-signs the app whenever your phone is on the same network'
Info 'as this PC. No cable, nothing to remember.'
Line
