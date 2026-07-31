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

- iOS 15.0 or later (iOS 16.0 for the Swift Playgrounds variant)
- Xcode 15 or later to build
- An Apple ID for code signing — a free account is sufficient

## Installation

### Windows

No Mac is required. A GitHub Actions workflow compiles the project on a GitHub-hosted macOS
runner; you sign and install the result locally. These are the exact steps that produced a
working install.

**1. Tooling.** Install [Git](https://git-scm.com/download/win) and the
[GitHub CLI](https://cli.github.com). If `winget` is unavailable, use those installers
directly rather than trying to repair `winget` first. Then authenticate:

```powershell
gh auth login --web        # choose HTTPS when asked about the Git protocol
```

**2. Publish the repository** (first time only), from the project folder:

```powershell
git init -b main
git add -A
git commit -m "Initial commit"
gh repo create slimread --public --source . --remote origin --push
```

Public repositories get unlimited GitHub Actions minutes; private ones bill macOS runner
time at a 10x multiplier.

**3. Build and fetch the IPA.** Double-click `Build and Download IPA.bat`, or run:

```powershell
git add -A; git commit -m "update"; git push
gh run watch
gh run download --name SlimRead-ipa
```

The push triggers the build; it takes a few minutes and leaves `SlimRead.ipa` in the folder.

**4. Apple's device drivers.** Sideloadly needs iTunes and iCloud installed **from
apple.com, not the Microsoft Store** — Store builds ship different drivers and the phone
will not appear. Uninstall the Store versions first if you have them.

- [iTunes 64-bit](https://www.apple.com/itunes/download/win64)
- [iCloud for Windows](https://support.apple.com/en-us/HT204283)

**5. Sideload.** Install [Sideloadly](https://sideloadly.io). Connect the iPhone with a data
cable, unlock it, tap **Trust This Computer**. In Sideloadly, pick your device, drag
`SlimRead.ipa` onto the IPA field, enter your Apple ID, press **Start**. Enter your password,
then the 6-digit two-factor code. If the password is rejected outright, generate an
[app-specific password](https://account.apple.com/account/manage) and use that.

Consider a throwaway Apple ID rather than your main one. Credentials go to Apple for
signing, not to Sideloadly, but a spare account costs nothing.

**6. Developer Mode.** A free Apple ID produces a *development*-signed app, which iOS 16 and
later will not run until Developer Mode is on:

**Settings → Privacy & Security → Developer Mode** → toggle on → **Restart**. After the
phone reboots and you unlock it, confirm **Turn On** and enter your passcode.

**7. Trust the certificate.** **Settings → General → VPN & Device Management** → tap your
Apple ID under *Developer App* → **Trust**.

Open the app. It loads Tapas with no status bar.

### macOS

1. Open `SlimRead.xcodeproj`.
2. Select the **SlimRead** target → **Signing & Capabilities**.
3. Set **Team** to your Apple ID and change the bundle identifier from `com.example.slimread`
   to something unique.
4. Select your device and run (⌘R).
5. On first launch, trust the certificate under **Settings → General → VPN & Device
   Management**.

### iPad (Swift Playgrounds)

Open `SlimRead.swiftpm` in Swift Playgrounds and use **Run on device**. The browser code is
identical; only the entry point differs (SwiftUI rather than `UIApplicationDelegate`).
Swift Playgrounds on iPhone cannot build applications — an iPad is required.

## Updating

**Page behaviour** — edit `tweaks/`, push, reopen the app. Nothing else. See
[Live tweaks](#live-tweaks).

**The app itself** — a new binary must be signed and installed; iOS permits no silent
self-update. Two options:

*From the PC:* run `Build and Download IPA.bat` and sideload the new IPA over the old
install. App data and site logins survive.

*From the phone:* run the **Publish release** workflow (Actions → Publish release → enter a
version). It builds the app, attaches the IPA to a GitHub Release, and updates
[`source.json`](source.json). Add that file's raw URL as a source in
[AltStore](https://altstore.io) or [SideStore](https://sidestore.io):

```
https://raw.githubusercontent.com/llllllllllllllppppppppppp/slimread/main/source.json
```

Updates then appear in AltStore on the phone and install with one tap, no cable. AltStore
also re-signs automatically over Wi-Fi before the certificate expires, which removes the
weekly Sideloadly step.

## Configuration

All of the following are in `BrowserViewController.swift`:

| Setting | Location |
|---|---|
| Start page | `homeURL` |
| Control bar auto-hide delay | `autoHideDelay` |
| Which buttons appear | `wireControls()` — one line per button |
| Default full-bleed behaviour | the `fullBleed` default in `init()` |

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
SlimRead/
  AppDelegate.swift               window and root view controller
  BrowserViewController.swift     web view, status bar overrides, gestures, tweak injection
  ControlBarView.swift            the top control bar
  TweaksLoader.swift              fetches and caches tweaks/ from this repo
  GuideOverlayView.swift          first-run gesture guide
  Info.plist                      status bar configuration
tweaks/
  tweaks.css                      live layout rules
  tweaks.js                       live behaviour: image loading, bottom-bar hiding
SlimRead.swiftpm/                 Swift Playgrounds variant
source.json                       AltStore/SideStore update manifest
.github/workflows/
  build-ipa.yml                   build and upload an IPA artifact
  release-ipa.yml                 publish a GitHub Release and refresh source.json
Build and Download IPA.bat        one-click build and fetch (Windows)
```

## Scope

SlimRead is a browser. It renders sites as they are served, with no content extraction,
downloading, ad blocking, or script injection of any kind. Pages load exactly as they would
in Safari, including advertising and analytics, so publisher and creator revenue is
unaffected. The only difference is that the status bar is not drawn.

## Licence

MIT — see [LICENSE](LICENSE).
