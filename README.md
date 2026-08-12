# SlimRead

A minimal iOS browser that hides the status bar in portrait orientation, built for reading
vertical-scroll comics without system UI covering the artwork.

---

## Why this exists

I read vertical-scroll comics, and on iOS the system status bar sits over the artwork for the
entire session — clock, battery and signal, permanently, on top of the page. No setting
removes it, in the reader app or in iOS itself, and no combination of Safari, Home Screen web
apps or Guided Access helps.

For whoever maintains the reader's iOS client this is a small, well-understood change. A
competitor already ships it on iOS, and the same reader ships it on Android
(see [Platform parity](#platform-parity)), so neither the operating system nor the pattern is
the obstacle. The change has simply not been made, and no feature-request channel leads
anywhere. SlimRead is that one change, built from the outside: an ordinary web browser,
pointed at the site I already pay to use, that does not draw the status bar over the page and
applies a few personal reading-comfort preferences to it.

One blunt point, kept because it is the whole argument. The unauthorised copies of this work
are, today, easier and more pleasant to read than the paid original — better layout, nothing
covering the art, no friction. I do not use them; I read and pay through the official service
because I want the creators supported, and I built a personal tool to make the legitimate
experience bearable rather than giving up on it. That is the lesson for anyone shipping a
reading product: **when the paid, legal path is worse than the free, illegal one, you teach
your own audience to leave.** This is one reader refusing to — patching around a single
unmet request instead of switching sides.

### What this is not

SlimRead is a web browser. It is not a client for any service, not a replacement for any
official app, and not affiliated with, endorsed by, or connected to any company.

- It **hosts and redistributes nothing.** Every page, image and byte is loaded live from the
  service's own servers, over your own logged-in session, exactly as a browser would.
- It **touches no payment, account, or content system.** You sign in to the service directly.
  Subscriptions, purchases, unlocks and creator payouts all happen on the service, under its
  terms, and belong entirely to it. SlimRead never sees or handles any of it.
- It **circumvents nothing.** No paywall or DRM bypass, no ad-stripping of monetised content,
  no downloading or offline copying. Locked chapters stay locked.
- It **makes no money.** There is no monetisation of any kind, now or planned.

What it *does* change is presentation, on the reader's own device: it hides the OS status bar
and restyles the page for reading — the same category of thing a browser's reader mode, zoom,
or a personal userstyle does with content already delivered to that device.

### Legal & disclaimer

SlimRead is a general-purpose WebKit browser with a default homepage and a set of personal
display tweaks — CSS and JavaScript applied to pages *after* they load, in the browser, on the
user's own device. Changing how a page is presented in your own browser, for your own use, is
ordinary browser behaviour: it is the same mechanism behind reader modes, zoom, dark-mode
extensions and userstyles.

Because it redistributes no content, circumvents no access controls, and interferes with no
payment or account system, SlimRead is intended and designed for personal, non-infringing
use. It is not affiliated with or endorsed by any content platform or its operators. All
trademarks, content and services referenced belong to their respective owners, and any use of
a third-party service through SlimRead is governed entirely by that service's own terms.

This document is not legal advice, and the software is provided "as is", without warranty of
any kind. You are responsible for your own use and for complying with the terms of any
service you access through it.

### Platform parity

This is not an iOS limitation and not an Apple restriction. As of July 2026:

- The reader's **Android app** has an immersive mode that hides the status bar. Its **iOS
  app** does not.
- **WEBTOON's iOS app** hides the status bar while reading, on the same operating system,
  using the same public API used here.

A competitor ships it on iOS today, and the same reader already ships it on Android. Neither
the platform nor the pattern is the obstacle.

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
- **Genuinely edge to edge.** The artwork fills the entire display, corner to corner and
  under the sensor housing. No letterboxing, no black frame.
- **Live tweaks.** Layout and reading behaviour are driven by CSS and JS pulled from this
  repository at every launch — see [Live tweaks](#live-tweaks).
- **Progressive image loading.** Panels load about two screens ahead of where you are, in
  order, so the visible page is never starved by everything below it loading at once.
- **Continuous chapters.** Reaching the end of a chapter seamlessly appends the next one;
  pulling up past the very top goes to the previous. No chapter-end wall of comments and
  recommendations — just the art.
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
| Keep scrolling past a chapter's end | The next chapter loads and continues inline |
| Pull up past the very top of a chapter | Jump to the previous chapter |

Control bar buttons, left to right: back, forward, reload, home, full-bleed toggle, guide.

The **full-bleed toggle** switches between filling the entire display and staying inside the
safe area. Full-bleed is the default, and is the point of the app: the artwork runs to all
four edges and under the sensor housing.

The trade is that the display's rounded corners clip whatever is in them, and the Dynamic
Island sits over the page. That is deliberate. Insetting to the safe area avoids it, but on a
Dynamic Island phone costs 59pt at the top and 34pt at the bottom — a permanent black frame
around the artwork, which is worse for reading than a corner that doesn't match the glass.
Turn the toggle off if you disagree; it is there for exactly that.

## Live tweaks

Everything about how pages are laid out and loaded lives in [`tweaks/`](tweaks/), fetched
from this repository each time the app launches or returns to the foreground.

**Edit `tweaks/tweaks.css` or `tweaks/tweaks.js`, push, reopen the app.** The change is live.
No rebuild, no re-signing, no reinstall, no PC.

- `tweaks.css` — layout. Full-width panels, black backgrounds, and hiding on-page chrome
  inside a chapter (top bar, bottom toolbar, comments, recommendations), scoped so listing
  pages are left alone.
- `tweaks.js` — behaviour. Progressive panel loading, and the continuous chapter scroll:
  reading the ordered episode list from the site's own JSON, then splicing the next chapter's
  panels onto the end of the current one as you reach it.

Both are written defensively, with broad selectors, because site markup changes without
warning. If a rule is too aggressive, delete it — the worst case is that the page renders
the way it does in Safari. The app keeps the last version it successfully fetched, so a
syntax error or an offline launch cannot leave you with a broken reader.

Only changes to *native* behaviour — the status bar, gestures, the control bar itself —
need a new build.

### Tuning knobs

The loader's numbers — how deep the panel buffer runs, how many chapters stay on one page —
are guesses about a device that can't be measured from the repository. Rather than push a
change and wait to hear how it felt, set them from the app's own address bar and find out in
seconds. Type any of these into the control bar's address field:

| | |
|---|---|
| `tapas.io/?slimread=hud=on` | Show the meter (below) |
| `tapas.io/?slimread=stitch=2` | Keep 2 chapters on the page instead of 4 |
| `tapas.io/?slimread=reserve=on` | Load panels as you reach them, not all on arrival |
| `tapas.io/?slimread=stitch=2,ahead=6` | Several at once, comma separated |
| `tapas.io/?slimread=show` | Report what's set right now, change nothing |
| `tapas.io/?slimread=trail` | The last 30 chapter changes and what caused each |
| `tapas.io/?slimread=reset` | Clear everything, back to defaults |

| knob | default | what it does |
|---|---|---|
| `hud` | `off` | The meter. Costs a 16ms timer while on. |
| `stitch` | `4` | Chapters kept on one page before the reader navigates instead. Lower holds less artwork, at one page load per N chapters. |
| `reserve` | `off` | On, panels reserve their space and load as you reach them. Off, the whole chapter loads at once. Neither is simply better — see the `RESERVE` comment in `tweaks.js`. |
| `autonav` | `off` | On, reaching the stitch cap moves to the next chapter by itself instead of waiting for the next-chapter button. Either way it never moves before the true bottom of the page. |
| `ahead` | `12` | **Inert unless `reserve=on`.** |
| `prime` | `12` | **Inert unless `reserve=on`.** |
| `margin` | `600` | **Inert unless `reserve=on`.** |

Two things that are easy to trip over. Setting knobs **replaces** the stored set rather than
merging into it, so `?slimread=hud=on` after `?slimread=reserve=on` also puts `reserve` back
to its default — name both if you want both. And they persist in `localStorage` across
relaunches until cleared. Setting one confirms itself on screen, and `?slimread=show` will
tell you later what's in force — worth asking before assuming a bug, since a knob left on
looks exactly like one. `stitch=2` has already been mistaken for a fault this way: it moves
the chapter cap onto your third chapter, where the default puts it on the fifth.

**The chapter trail** is always recording, knobs or no knobs — a switch you have to flip
*before* a bug happens is no use, because you don't know it's coming. `?slimread=trail` shows
the last 30 chapter changes and what caused each:

```
06:41:54  open    1001  (navigate)
06:41:57  append  1002  (stitched below, nothing moved)
06:41:58  scroll  1002  (crossed a stitch boundary)
06:42:05  back/fwd 1002  (history)
06:42:06  open    1003  (reload)
```

`append` and `scroll` are the reader working normally — content added below you, then you
scrolling into it. `open … (reload)` means **the app replaced the page under you**, which it
does whenever `tweaks.js` changes, discarding the stitched page and landing wherever the URL
pointed. That one is invisible from inside the page any other way, and it's the usual answer
to "it moved and I didn't touch it". `button` and `cap nav` are deliberate navigations.

**The meter** reads how blocked the main thread is, sampled over the last second:

```
block 34ms worst / 12% late | panels 24/130 | page 67k | ch 2
```

`block` is the worst single stall — under ~10ms is fine, 30ms+ is a visible hitch. `panels`
is how many hold artwork out of how many exist; it reads N/N with `reserve=off`, which is
expected. It measures the main thread only: if scrolling feels bad while `block` stays low,
the cost is in compositing a very tall page, and no CSS or JS here will fix it — reduce how
much page there is with `stitch=N` instead.

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

You can remove the weekly step entirely — see [Automatic renewal](#automatic-renewal).

## Automatic renewal

The 7-day expiry can be automated away with Sideloadly's built-in refresh daemon. Two
one-time steps:

1. **When sideloading,** tick the **auto-refresh** option before pressing Start.
2. **Enable Wi-Fi sideloading:** with the phone connected by cable, open iTunes → your
   device → Summary → Options → tick **Sync with this iDevice over Wi-Fi** → Sync.

From then on Sideloadly re-signs the app whenever your phone is on the same network as your
PC. Nothing to remember and no cable.

Your PC has to be switched on and reachable for this to fire. That is unavoidable — the
signing has to happen somewhere, and on a free Apple ID it happens on a computer.

## Updating

**You do not update this app.** Improvements arrive on their own.

Page layout and loading behaviour live in [`tweaks/`](tweaks/), which every installed copy
fetches from this repository each time it launches. When the maintainer changes something
there, your app has it the next time you open it — nothing to install, nothing to approve.

Changes to the app itself are rarer, and ride along with the certificate renewal you are
already doing: `SlimRead.bat` always downloads the newest published build.

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
  and must be re-signed. Re-signing preserves app data and logins. Sideloadly's auto-refresh
  daemon handles it over Wi-Fi; a paid Apple Developer account extends the certificate to a
  year instead.
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
iCloud (from [sideloadly.io](https://sideloadly.io), under *Before you install*) from Apple. Confirm the phone appears in
iTunes itself — if iTunes cannot see it, nothing else will. Also check you are using a data
cable rather than a charge-only one, and that you tapped **Trust This Computer**.

### Sideloadly rejects your Apple ID password, or says "update iCloud for Windows"

Use your real Apple ID password and the 6-digit code from your phone. App-specific passwords
only work with a *paid* developer account and anisette disabled, so they are not an option on
a free Apple ID.

If sign-in fails with a message about updating iCloud for Windows, the problem is **anisette**
— the authentication tokens Apple demands from Windows clients, normally supplied by a local
iCloud install. Apple removed the standalone iCloud download page, so this is now common.

The fix is a checkbox: **Sideloadly → Advanced Options → Remote Anisette**. Sideloadly then
fetches those tokens from its own server and your local iCloud stops mattering. Their server
sees only your IP, OS and Sideloadly version; your Apple ID and password still go straight to
Apple.

Device detection comes from iTunes rather than iCloud, so with remote anisette enabled you
may not need iCloud installed at all. If you want it anyway, Sideloadly's homepage still
hosts a working direct link under **Before you install → Web iCloud**.

Switching to AltServer does not avoid this — it has the same iTunes and iCloud requirement.

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

### "Unable to create '.git/index.lock': File exists"

A stale lock file. Git creates it while writing to the index and removes it after; if a git
process is killed, or another tool has the folder open, it survives and blocks every
subsequent git command.

```powershell
Remove-Item .git\index.lock -Force
```

Nothing is damaged — git simply refuses to touch the index while it thinks another process
holds it. `Publish Update.bat` now clears stale locks by itself, after checking no git
process is actually running.

### The app stopped opening after a week

The free certificate expired. Run `SlimRead.bat` again and re-sideload. App data, logins and
reading position all survive. Set up [Automatic renewal](#automatic-renewal) so it stops
happening.

### "SlimRead is no longer available"

**Do not delete the app.** That message comes from iOS, not from SlimRead, and deleting is the
one action that turns a five-minute fix into losing your Tapas login and your reading
position.

It almost always means iOS **offloaded** the app — removed the binary to reclaim storage while
keeping its data. Tapping the icon makes iOS try to re-download it from the App Store, and
SlimRead was never there, so it reports it as no longer available. A small cloud ☁ beside the
app's name on the Home Screen confirms this is what happened.

Certificate expiry is the other possibility, but it usually looks different — "Unable to
Verify App", or the app opens and immediately quits. Either way the fix is the same:

**Run `SlimRead.bat` again and re-sideload over the top.** Sideloadly reinstalls the same
bundle identifier, so the existing data container reattaches: your logins, reading position,
saved scroll offsets and any `?slimread=` settings all come back. Nothing needs re-fetching —
`tweaks/` is pulled fresh from this repository on the next launch regardless.

To stop it recurring, turn offloading off:

**Settings → App Store → Offload Unused Apps → off.**

Also check **Settings → General → iPhone Storage**, which offers to offload apps individually
when space runs low — SlimRead is a prime candidate there, because reading a long series fills
the web view's cache and makes the app look large and idle to iOS.

### A page renders oddly, or a tweak went too far

Everything about page layout lives in [`tweaks/`](tweaks/). Delete the offending rule, push,
and reopen the app — worst case the page renders exactly as it would in Safari. The app keeps
the last version it fetched successfully, so a bad edit or an offline launch cannot leave you
with a broken reader.

## Licence

MIT — see [LICENSE](LICENSE).
