# SlimRead

A one-page iPhone browser with **no status bar in portrait**. Built for reading vertical-scroll
manhwa on Tapas without the clock, battery and signal bars sitting on top of the artwork.

---

## Before you build anything

Two App Store apps already do this, free, with no PC and no weekly expiry:

- **Kiosk - fullscreen browser** - explicitly hides the status bar, no nav bar, swipe to go back
- **Private Full Screen Browser** - hides address bar, buttons and status bar, portrait and landscape

If either works on Tapas, use it and skip this repo entirely. Build your own only if you
want no ads, exact gesture behaviour, or the ability to change it.

## Fastest route on Windows

Extract this zip, then double-click **`RUN ME - Build SlimRead.bat`**.

It installs Git and the GitHub CLI, signs you in, uploads the project to a repo of your own,
builds it on GitHub's free macOS runners, and leaves `SlimRead.ipa` on your Desktop - about
five minutes, mostly waiting. Then you drag that IPA onto [Sideloadly](https://sideloadly.io)
with the phone plugged in.

You need a free GitHub account. Choose **public** when it asks about repo visibility -
public repos get unlimited free macOS build minutes, private ones burn your monthly quota
at a 10x rate.

---

## Why this needs to be an app

There is no web-only way to do this, and it is worth knowing that up front:

| Approach | Result |
|---|---|
| PWA "Add to Home Screen" | Status bar still renders. `black-translucent` only lets content pass *under* it — the clock and battery still draw on top. |
| Fullscreen API | Not supported on iPhone Safari for anything but video. |
| Your own page with tapas.io in an iframe | Blocked by Tapas' frame headers, and the status bar would stay anyway. |
| Guided Access | Hides the home bar, not the status bar. |
| Rotating to landscape | Works, but it's landscape. |

A native app can simply say "hide it", in any orientation. That's what this is — three Swift files.

## How it actually works

In `BrowserViewController.swift`:

```swift
override var prefersStatusBarHidden: Bool { true }
override var prefersHomeIndicatorAutoHidden: Bool { true }
override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { [.top, .bottom] }
```

plus, in `Info.plist`:

```xml
<key>UIStatusBarHidden</key><true/>                          <!-- launch screen too -->
<key>UIViewControllerBasedStatusBarAppearance</key><true/>   <!-- let the VC decide -->
```

That's the whole mechanism. Documented API, no orientation faking, no private calls,
App Store-legal if you ever wanted to ship it.

## Using it

- Opens straight to tapas.io, and resumes wherever you left off.
- **No chrome at all** while reading — just a faint pill at the bottom centre.
- **Tap the pill** (or **two-finger tap anywhere**) to raise back / forward / address / reload /
  home / edge-to-edge toggle. It slides away again after 5 seconds.
- **Swipe from the left or right edge** to go back and forward.
- The **edge-to-edge button** switches between painting under the Dynamic Island and staying
  inside the safe area. Full-bleed is the default; flip it if the island clips artwork.
- Cookies persist, so a Tapas login sticks.

To point it at a different site by default, change `homeURL` at the top of
`BrowserViewController.swift`.

---

## Installing it

Pick whichever matches your setup. **Route A** if you can borrow a Mac for ten minutes,
**Route B** if you're on Windows only, **Route C** if you have an iPad.

### Route A — Mac with Xcode

1. Open `SlimRead.xcodeproj`.
2. Select the **SlimRead** target → **Signing & Capabilities**.
3. Set **Team** to your Apple ID (Xcode → Settings → Accounts → **+** adds a free one).
4. Change the **Bundle Identifier** from `com.example.slimread` to something unique —
   `com.yourname.slimread`.
5. Plug in the iPhone, pick it in the device menu, press **⌘R**.
6. First run only: on the phone, **Settings → General → VPN & Device Management** → trust
   your developer certificate.

### Route B — Windows only, no Mac

You still need macOS to *compile*, but GitHub's runners are free and there's a workflow
included that does it for you.

1. Push this folder to a GitHub repo.
2. **Actions** tab → **Build unsigned IPA** → **Run workflow**.
3. When it finishes, download the `SlimRead-ipa` artifact and unzip it to get `SlimRead.ipa`.
4. Install it with either:
   - **Sideloadly** (simplest) — desktop app for Windows, plug in the phone, drag the IPA,
     enter your Apple ID.
   - **AltStore** — install AltServer on the PC, pair once over USB, and it can then refresh
     over Wi-Fi so you don't have to plug in every week.
   - **SideStore** — runs on the phone itself and refreshes in the background after setup.
5. Trust the certificate under **Settings → General → VPN & Device Management**.

### Route C — iPad with Swift Playgrounds

Open `SlimRead.swiftpm` in Swift Playgrounds on an iPad and use **Run on device** to install
onto your iPhone. Same browser code, SwiftUI entry point instead of `AppDelegate`.
(Swift Playgrounds on iPhone can't build apps — iPad only.)

---

## The catch you should know about

Free Apple ID signing gives you a **7-day certificate**. After a week the app stops opening
and needs re-signing — which is a re-run of whichever install step you used, and doesn't wipe
your data or logins. You're also capped at **3 sideloaded apps at once**.

AltStore and SideStore automate the weekly refresh, which is why they're worth the extra
setup over Sideloadly if you plan to keep this around.

A paid Apple Developer account ($99/year) extends the certificate to **1 year**. Only worth it
if the weekly refresh genuinely irritates you.

## Requirements

- iOS 15+ for the Xcode project, iOS 16+ for the Swift Playgrounds variant
- Xcode 15 or newer

## Layout

```
SlimRead.xcodeproj              Xcode project (Routes A + B)
SlimRead/
  AppDelegate.swift             window + root VC, ~20 lines
  BrowserViewController.swift   the web view, status-bar overrides, gestures
  ControlBarView.swift          the pop-up bottom bar
  Info.plist                    status bar keys live here
  Assets.xcassets               app icon
SlimRead.swiftpm/               Swift Playgrounds variant (Route C)
.github/workflows/build-ipa.yml CI build for Route B
```
