# SlimRead

A minimal iOS browser that hides the status bar in portrait orientation, built for reading
vertical-scroll comics without system UI covering the artwork.

---

## Why

Reading a vertical-scroll comic on iOS means the status bar — clock, battery, signal — sits
over the top of the page for the entire session. iOS exposes no setting to hide it while
browsing, and the web platform offers no way to remove it either:

| Approach | Outcome |
|---|---|
| Home Screen web app (PWA) | Status bar still renders. `apple-mobile-web-app-status-bar-style: black-translucent` only lets content pass *underneath* it; the clock and battery still draw on top. |
| Fullscreen API | Not supported on iPhone Safari outside of video elements. |
| Guided Access | Hides the home indicator, not the status bar. |
| Rotating to landscape | Works, but portrait is the correct aspect ratio for vertical-scroll comics. |

A native app has no such restriction. A view controller returning `true` from
`prefersStatusBarHidden` hides the status bar in every orientation. SlimRead is the smallest
useful application built around that fact: a single `WKWebView`, no permanent chrome, three
Swift files.

### On platform parity

This is not an iOS limitation, and it is not an Apple restriction. As of July 2026:

- The **Tapas Android app** provides an immersive reading mode that hides the status bar.
  The iOS app does not.
- The **WEBTOON iOS app** hides the status bar while reading, on the same operating system
  and the same public API used here.

The capability is four lines of UIKit, shown in full below. A competitor ships it on iOS
today, and Tapas already ships it on Android — so neither the platform nor the design pattern
is the obstacle. This repository exists because the feature is absent from the iOS client,
not because it is difficult.

## Features

- **No status bar, portrait or landscape.** Documented UIKit API, no orientation spoofing.
- **No permanent chrome.** The reading surface is the entire display. A small pill at the
  bottom edge is the only persistent UI.
- **Controls on demand.** Tap the pill or two-finger tap anywhere for back, forward, address
  field, reload, home, and a full-bleed toggle. Auto-hides after five seconds.
- **Edge-swipe navigation** for back and forward.
- **Full-bleed toggle** switches between drawing under the Dynamic Island and respecting the
  safe area, for pages where the sensor housing clips artwork.
- **Home indicator dimmed** and edge gestures deferred, so scrolling near the bottom of the
  screen doesn't exit the app.
- **Session persistence.** Cookies are kept, so site logins survive. Reopening returns to the
  last page read.

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

## Requirements

- iOS 15.0 or later (iOS 16.0 for the Swift Playgrounds variant)
- Xcode 15 or later to build
- An Apple ID for code signing — a free account is sufficient

## Installation

### Windows

No Mac is required. The included GitHub Actions workflow compiles the project on a
GitHub-hosted macOS runner and publishes an unsigned `.ipa` as a build artifact.

**Prerequisites:** [Git](https://git-scm.com/download/win) and the
[GitHub CLI](https://cli.github.com), authenticated with `gh auth login`.

**First-time setup:**

```powershell
git init -b main
git add -A
git commit -m "Initial commit"
gh repo create slimread --public --source . --remote origin --push
```

**Every build after that** — double-click `Build and Download IPA.bat`. It commits, pushes,
waits for the macOS build, and downloads `SlimRead.ipa` into the project folder. Equivalent
manual commands:

```powershell
git add -A; git commit -m "update"; git push
gh run watch
gh run download --name SlimRead-ipa
```

**Installing the IPA on device:** open [Sideloadly](https://sideloadly.io), connect the
iPhone by cable, drag the `.ipa` onto the window, and sign in with your Apple ID.
[AltStore](https://altstore.io) and [SideStore](https://sidestore.io) are alternatives that
re-sign automatically over Wi-Fi.

> Public repositories receive unlimited GitHub Actions minutes. Private repositories bill
> macOS runner time against the free monthly allowance at a 10× multiplier.

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
  and must be re-signed. Re-signing preserves app data and site logins. AltStore and SideStore
  automate this; a paid Apple Developer account extends the certificate to one year.
- **Three-app limit.** Free Apple IDs can have at most three sideloaded applications
  installed simultaneously.
- **Single view.** There are no tabs, bookmarks, or history UI. This is deliberate.

## Project layout

```
SlimRead.xcodeproj                Xcode project
SlimRead/
  AppDelegate.swift               window and root view controller
  BrowserViewController.swift     web view, status bar overrides, gestures
  ControlBarView.swift            the on-demand control bar
  Info.plist                      status bar configuration
  Assets.xcassets                 app icon
SlimRead.swiftpm/                 Swift Playgrounds variant
.github/workflows/build-ipa.yml   macOS CI build
Build and Download IPA.bat        one-click build and fetch (Windows)
```

## Scope

SlimRead is a browser. It renders sites as they are served, with no content extraction,
downloading, ad blocking, or script injection of any kind. Pages load exactly as they would
in Safari, including advertising and analytics, so publisher and creator revenue is
unaffected. The only difference is that the status bar is not drawn.

## Licence

MIT — see [LICENSE](LICENSE).
