# SlimRead

A minimal iOS browser that hides the status bar in portrait orientation, built for reading
vertical-scroll comics without system UI covering the artwork.

---

## Why this exists

I read vertical-scroll comics on Tapas, and on iOS the status bar sits over the artwork for
the entire session. Clock, battery and signal, permanently, on top of the page. There is no
setting for it, in the app or in iOS, and no combination of Safari, Home Screen web apps or
Guided Access removes it.

That is a two-line fix for whoever maintains the iOS client. It has not been made. So this is
the fix, built from outside: a browser that opens to Tapas and simply does not draw the
status bar.

To be clear about what this is not — it does not bypass paywalls, download chapters, block
ads, or touch Tapas' business in any way. It loads the site exactly as Safari would, ads and
analytics included, because the creators should get paid. The single difference is that the
system UI is not drawn over their work.

### On platform parity

This is not an iOS limitation and it is not an Apple restriction. As of July 2026:

- The **Tapas Android app** has an immersive reading mode that hides the status bar.
  The iOS app does not.
- The **WEBTOON iOS app** hides the status bar while reading, on the same operating system,
  using the same public API used here.

A competitor ships it on iOS today, and Tapas already ships it on Android. Neither the
platform nor the pattern is the obstacle.

### Why the web platform can't do this

| Approach | Outcome |
|---|---|
| Home Screen web app (PWA) | Status bar still renders. `apple-mobile-web-app-status-bar-style: black-translucent` only lets content pass *underneath*; the clock and battery still draw on top. |
| Fullscreen API | Not supported on iPhone Safari outside video elements. |
| Guided Access | Hides the home indicator, not the status bar. |
| Rotating to landscape | Works, but portrait is the correct aspect ratio for vertical-scroll comics. |

A native app has no such restriction. A view controller returning `true` from
`prefersStatusBarHidden` hides it in every orientation.

## Features

- **No status bar, portrait or landscape.** Documented UIKit API, no orientation spoofing.
- **No permanent chrome.** Nothing overlays the page while reading — no bar, no handle, no
  indicator. The controls appear only when asked for.
- **Tap the top of the screen** — the notch or Dynamic Island — to show the controls. They
  slide away when you scroll down, or after six seconds.
- **Edge-swipe navigation.** Swipe in from the left edge to go back, right edge to go forward.
- **Page corners match the display,** rather than square content against rounded glass.
- **Live tweaks.** Layout and loading behaviour are driven by CSS and JS pulled from this
  repository at every launch — see [Live tweaks](#live-tweaks).
- **Faster image loading.** Lazy-loaded panels are promoted immediately and the next few are
  prefetched, with a 512 MB disk cache so re-reads are instant.
- **Site chrome tamed.** Persistent bottom bars slide away while scrolling and return at the
  end of a chapter.
- **Built-in guide,** shown on first launch and available from the **?** button.
- **Session persistence.** Cookies survive, so logins stick. Reopening returns to the last page.

## Implementation

The status bar behaviour comes from four overrides in `BrowserViewController.swift`:

```swift
override var prefersStatusBarHidden: Bool { true }
override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }
override var prefersHomeIndicatorAutoHidden: Bool { true }
override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { [.top, .bottom] }
```

paired with two keys in `Info.plist`:

```xml
<key>UIStatusBarHidden</key><true/>
<key>UIViewControllerBasedStatusBarAppearance</key><true/>
```

`UIStatusBarHidden` covers the launch screen; `UIViewControllerBasedStatusBarAppearance`
delegates the runtime decision to the view controller. Both are public API and App Store
compliant.

## Using it

| Gesture | Result |
|---|---|
| Tap the top of the screen (notch / Dynamic Island area) | Show or hide the controls |
| Two-finger tap anywhere | Same, when the top is awkward to reach |
| Swipe in from the left edge | Back |
| Swipe in from the right edge | Forward |
| Scroll down | Controls get out of the way automatically |

Control bar buttons, left to right: back, forward, reload, home, full-bleed toggle, guide.

The **full-bleed toggle** switches between filling the entire display (artwork passes under
the Dynamic Island) and staying inside the safe area. Full-bleed is the default; turn it off
if the sensor housing clips something you need to see.

## Live tweaks

Everything about how pages are laid out and loaded lives in [`tweaks/`](tweaks/), fetched
from this repository each time the app launches or returns to the foreground.

**Edit `tweaks/tweaks.css` or `tweaks/tweaks.js`, push, reopen the app.** The change is live.
No rebuild, no re-signing, no reinstall, no PC.

- `tweaks.css` — layout. Removing the white margins beside artwork, black backgrounds,
  hiding cookie banners and app-install interstitials.
- `tweaks.js` — behaviour. Promoting lazy-loaded images, prefetching the next few panels,
  clearing inline widths CSS can't override, and sliding the site's fixed bottom bar away
  while scrolling.

Both are written defensively, with broad selectors, because site markup changes without
warning. If a rule is too aggressive, delete it — the worst case is that the page renders
the way it does in Safari. The app keeps the last version it successfully fetched, so a
syntax error or an offline launch cannot leave you with a broken reader.

Only changes to *native* behaviour — the status bar, gestures, the control bar itself —
need a new build.

## Requirements

- iOS 15.0 or later
- Xcode 15 or later to build
- An Apple ID for code signing — a free account is sufficient

## Installing it

**Download this repository** (green **Code** button → **Download ZIP**), extract it, and
**double-click `SlimRead.bat`**.

That is the whole thing. No GitHub account, no developer tools, no building. The script
downloads the finished app, checks the two Apple components it needs, opens Sideloadly for
you, and walks you through the last two settings on the phone. It stops and explains itself
if anything goes wrong rather than closing.

You will need your iPhone, a data cable, and an Apple ID. A spare Apple ID is fine and is the
safer choice.

### Why it isn't just a download

Apple requires apps installed outside the App Store to be signed with **the installing
person's own Apple ID**. Nobody can hand you a ready-to-run copy — not the author, not
anyone. That is why Sideloadly and your Apple ID are in the loop, and it is the same for
every sideloaded iOS app.

Two consequences:

- **The app stops opening after 7 days.** That is the free Apple certificate expiring, not a
  fault. Run `SlimRead.bat` again to renew — logins and reading position survive.
- **Developer Mode must be enabled** and left on. It does not disable code signing,
  sandboxing or encryption. See [Troubleshooting](#troubleshooting).

[AltStore](https://altstore.io) removes the weekly renewal by re-signing automatically over
Wi-Fi. Optional, and worth it if the reminder gets tiresome.

## Updating

**Page behaviour** — edit `tweaks/`, push, reopen the app. Nothing else. See
[Live tweaks](#live-tweaks).

**The app itself** — a new binary must be signed and installed; iOS permits no silent
self-update. Two options:

*From the PC:* run `SlimRead.bat` and sideload the new IPA over the old install. App data
and site logins survive.

*From the phone:* run the **Publish release** workflow (Actions → Publish release → enter a
version). It builds the app, attaches the IPA to a GitHub Release, and updates
[AltStore](https://altstore.io) or [SideStore](https://sidestore.io):

```
```

Updates then appear in AltStore on the phone and install with one tap, no cable. AltStore
also re-signs automatically over Wi-Fi before the certificate expires, which removes the
weekly Sideloadly step.

## For the maintainer

Everyone below this line is building the app rather than using it.

### Publishing changes

**Double-click `Publish Update.bat`.** It installs Git and the GitHub CLI if needed, signs
you in, pushes your changes, and offers to publish a new build.

The important distinction:

| Changed | What to do | Reaches users |
|---|---|---|
| `tweaks/tweaks.css` or `tweaks/tweaks.js` | Push. That is all. | Next time they open the app |
| Swift source, Info.plist, the icon | Push **and** publish a release | Next time they run `SlimRead.bat` |

Publishing a release builds on a GitHub macOS runner and attaches `SlimRead.ipa` to a GitHub
Release. `SlimRead.bat` always downloads from `releases/latest`, so users need no account and
no instructions beyond "run the file".

### Configuration

| Setting | Location |
|---|---|
| Start page | `homeURL` in `BrowserViewController.swift` |
| Control bar auto-hide delay | `autoHideDelay`, same file |
| Which buttons appear | `wireControls()`, one line per button |
| Default full-bleed behaviour | the `fullBleed` default in `init()` |
| Where tweaks are fetched from | `baseURL` in `TweaksLoader.swift` |
| Where the installer downloads from | `$Owner` / `$Repo` at the top of `SlimRead.ps1` |

If you fork this, change the last two — otherwise your users pull from the original
repository rather than yours.

### Building on macOS

Open `SlimRead.xcodeproj`, set your team under **Signing & Capabilities**, change the bundle
identifier from `com.example.slimread`, and run.

## Limitations

- **Certificate expiry.** Apps signed with a free Apple ID stop launching after seven days
  and must be re-signed. Re-signing preserves app data and logins. AltStore and SideStore
  automate this; a paid Apple Developer account extends the certificate to a year.
- **Developer Mode must stay enabled.** Development-signed apps will not launch without it.
  Turning it off disables the app. Ad-hoc and TestFlight distribution avoid the requirement
  but need the paid developer account.
- **Three-app limit.** Free Apple IDs allow at most three sideloaded apps at once.
- **The tweaks are best-effort.** They target site markup that can change at any time. When
  a page starts rendering oddly, `tweaks/` is the first place to look.
- **Single view.** No tabs, bookmarks, or history UI. Deliberate.

## Project layout

```
SlimRead.bat / SlimRead.ps1       what a user runs - downloads and installs the app
Publish Update.bat                what the maintainer runs - push and release
Publish-Update.ps1
SlimRead/
  AppDelegate.swift               window and root view controller
  BrowserViewController.swift     web view, status bar overrides, gestures, tweak injection
  ControlBarView.swift            the top control bar
  TweaksLoader.swift              fetches and caches tweaks/ from this repo
  GuideOverlayView.swift          first-run gesture guide
  Info.plist                      status bar configuration
  Assets.xcassets                 app icon
tweaks/
  tweaks.css                      live layout rules
  tweaks.js                       live behaviour: image loading, bottom-bar hiding
.github/workflows/
  build-ipa.yml                   build and upload an IPA artifact
  release-ipa.yml                 publish a GitHub Release for users to download
```

## Scope

SlimRead is a browser. It renders sites as they are served, with no content extraction,
downloading, ad blocking, or script injection of any kind. Pages load exactly as they would
in Safari, including advertising and analytics, so publisher and creator revenue is
unaffected. The only difference is that the status bar is not drawn.

## Troubleshooting

Every problem below was hit during a real install. `SlimRead.bat` now handles most of them
automatically, but here is what each one means if you meet it elsewhere.

### "Your internet security settings prevented one or more files from being opened"

Mark-of-the-Web. Windows flags files extracted from a downloaded zip and refuses to run
scripts among them. Nothing is wrong with the files.

Right-click the **zip** → Properties → tick **Unblock** → OK → extract again. To clear files
you already extracted:

```powershell
Get-ChildItem "C:\path\to\SlimRead" -Recurse | Unblock-File
```

`SlimRead.bat` does this to itself on every run.

### A script window flashes open and closes instantly

The script failed before reaching its own pause. Run it from a terminal so the output stays:

```powershell
cd "C:\path\to\SlimRead"
powershell -ExecutionPolicy Bypass -File .\SlimRead.ps1
```

`SlimRead.bat` keeps the window open regardless, because the pause is in the batch file
rather than the script it launches.

### "winget is not available on this PC"

winget ships inside App Installer, which is missing or unregistered. `SlimRead.bat` tries to
fix this by itself; failing that it downloads the Git and GitHub CLI installers directly and
carries on without winget.

To fix winget manually, in an **administrator** PowerShell:

```powershell
Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
```

If that does not work:

```powershell
Install-PackageProvider -Name NuGet -Force
Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery
Repair-WinGetPackageManager -AllUsers
```

Then open a **new** window — PATH does not refresh inside one already open. Note that winget
is only a means to install two programs; installing [Git](https://git-scm.com/download/win)
and the [GitHub CLI](https://cli.github.com) directly is equally valid and often quicker.

### "fatal: detected dubious ownership in repository at 'C:/Windows/System32'"

You ran `git init` in `C:\Windows\System32` — the folder an administrator PowerShell window
opens in. Git correctly refused to treat a system directory as your project.

**Do not add the suggested `safe.directory` exception.** That would tell Git to treat all of
System32 as your repository. Instead remove the stray repo and move to the right folder:

```powershell
Remove-Item -Recurse -Force C:\Windows\System32\.git
cd "$env:USERPROFILE\Downloads\SlimRead"
```

If you already added the exception, undo it with `git config --global --unset safe.directory`.

### "Use arrows to move… HTTPS / SSH"

That is `gh auth login` asking how Git should talk to GitHub. Choose **HTTPS** — no key setup
required, and it is what everything here uses.

### "found no in progress runs to watch"

Nothing is building right now, usually because the build already finished. Check the result:

```powershell
gh run list
```

A tick means it succeeded — download it. An X means it failed — `gh run view --log-failed`
shows why. No rows at all means nothing has been pushed yet.

### "error extracting… SlimRead.ipa: The file exists"

You already downloaded that artifact. `gh` will not overwrite. Delete first:

```powershell
Remove-Item SlimRead.ipa
gh run download --name SlimRead-ipa
```

### The IPA is only ~65 KB — is that right?

Yes. iOS supplies the Swift runtime, so it is not bundled into the app. Three source files
and one icon compress to about that.

### Your iPhone does not appear in Sideloadly

Almost always the wrong iTunes. Sideloadly needs the **desktop** builds from apple.com; the
Microsoft Store versions ship different drivers.

Uninstall the Store versions, then install
[iTunes 64-bit](https://www.apple.com/itunes/download/win64) and
[iCloud](https://support.apple.com/en-us/HT204283) from Apple. Confirm the phone appears in
iTunes itself — if iTunes cannot see it, nothing else will. Also check you are using a data
cable rather than a charge-only one, and that you tapped **Trust This Computer**.

### Sideloadly rejects your Apple ID password

With two-factor enabled, some accounts need an
[app-specific password](https://account.apple.com/account/manage) instead of your real one.
Generate one and paste that.

### "Untrusted Developer" when opening the app

Expected on first install. **Settings → General → VPN & Device Management** → tap your Apple
ID under *Developer App* → **Trust** → confirm.

If no *Developer App* section appears, the phone needs internet to verify the certificate.
Connect to Wi-Fi, leave Settings, and go back in.

### "Developer Mode required"

iOS 16 and later will not run development-signed apps until Developer Mode is on. A free
Apple ID can only produce development-signed apps, so this is unavoidable on this route.

**Settings → Privacy & Security → Developer Mode** → on → **Restart**. After the phone
reboots and you unlock it, confirm **Turn On** and enter your passcode.

It must stay enabled — turning it off stops the app launching. It does not disable code
signing, sandboxing or encryption; it removes one obstacle for someone installing a
development app on a phone they physically hold, which is why it needs your passcode and a
reboot. Ad-hoc and TestFlight distribution avoid the requirement, but both need the paid
Apple Developer account.

### The app stopped opening after a week

The free certificate expired. Run `SlimRead.bat` again and re-sideload. App data, logins and
reading position all survive. [AltStore](https://altstore.io) or
[SideStore](https://sidestore.io) automate the renewal over Wi-Fi.

### A page renders oddly, or a tweak went too far

Everything about page layout lives in [`tweaks/`](tweaks/). Delete the offending rule, push,
and reopen the app — worst case the page renders exactly as it would in Safari. The app keeps
the last version it fetched successfully, so a bad edit or an offline launch cannot leave you
with a broken reader.

## Licence

MIT — see [LICENSE](LICENSE).
