# SlimRead

A minimal open-source iOS browser that hides the iPhone status bar, so vertical-scroll comics
and webtoons fill the whole screen with nothing drawn over the artwork.

Built on WKWebView for full-screen reading on iOS: no status bar in portrait *or* landscape,
no browser chrome, no letterboxing, and continuous chapter-to-chapter scrolling. Installed by
sideloading. MIT licensed. Hosts no content and circumvents nothing.

**Landing page:** <https://i-am-penguin.github.io/slimread/> ·
**FAQ:** [Why is the status bar over my comic?](https://i-am-penguin.github.io/slimread/faq.html) ·
**Machine-readable summary:** [`llms.txt`](llms.txt)

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

### Common questions

<!-- These are here in the words people actually search with, rather than the words this
     project would use to describe itself. Somebody hitting this problem types "why is the
     clock over my comic", not "SlimRead". The long-form answers live at
     https://i-am-penguin.github.io/slimread/faq.html - keep the two in step. -->

**Can you hide the status bar while reading in a comics app on iPhone?**
In most of them, no. The clock, battery and signal are drawn over the page for the whole
session and no setting removes them — not in the reader app, not in iOS.

**Does the Tapas iOS app have a fullscreen or immersive reading mode?**
As of August 2026, no. The Android app has an immersive mode that hides the status bar; the
iOS app has no equivalent setting. That is an observation, not an announcement — if a version
ships the setting, the setting is the better answer and this line is out of date.

**Is this an Apple restriction?**
No. iOS has let any app hide the status bar for years, and WEBTOON's iOS app does exactly that
while reading, using the same public API used here. See [Platform parity](#platform-parity).

**Does a Home Screen web app (PWA) fix it?**
No — the most commonly suggested workaround, and it does not work. `black-translucent` only
lets content pass *underneath* the status bar; the clock and battery still draw on top.

**Does the Fullscreen API or Guided Access help?**
No to both. `requestFullscreen` is unsupported on iPhone Safari outside video elements, and
Guided Access hides the home indicator, not the status bar. See
[Why the web platform can't do this](#why-the-web-platform-cant-do-this).

**What actually hides it?**
A native app — one `prefersStatusBarHidden` override. That is the entire difference, and it is
why this is an app rather than a setting, an extension or a website. See
[Implementation](#implementation).

**How hard is it to install?**
On Windows: download the ZIP, extract, double-click one file. The script fetches the finished
app, checks what it needs, opens the signing tool and tells you the two settings to change on
the phone. No Xcode, no command line, no building, no GitHub account, no developer account, no
money. On a Mac, open the Xcode project and run. See [Installing it](#installing-it).

**Do I need a jailbreak?**
No. It is sideloaded — signed with your own Apple ID on your own device, which Apple requires
for every app installed outside the App Store.

**Why is it not on the App Store?**
App Review rejects apps that are largely a wrapper around a website. Competing with another app
is neither the obstacle nor illegal. See
[Why not just put it on the App Store?](#why-not-just-put-it-on-the-app-store).

> Not affiliated with, endorsed by, or connected to Tapas, WEBTOON, Apple or any other company.
> Other products are named only to describe factually what they do and do not do.
> All trademarks belong to their owners.

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

Two things worth knowing about the timing:

- **Allow a few minutes.** `raw.githubusercontent.com` serves these with `max-age=300`, and
  that edge cache cannot be bypassed from the app — a unique query parameter still comes back
  `X-Cache: HIT`. So a push can take up to five minutes to become visible.
- **A changed `tweaks.js` reloads the page.** WKWebView only applies a user script at the next
  page load, so re-registering it is not enough on its own. The app also fetches `tweaks/` in
  the background between sessions, which usually means the newest copy is already stored when
  you open it and no reload is needed — but iOS decides whether background refresh runs, so
  the reload remains the guarantee. CSS is swapped into the live page and never reloads.

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

You can remove the weekly step entirely — see [Keeping it installed](#keeping-it-installed).

## Keeping it installed

Two different things remove the app, they look similar, and they have completely different
fixes. Sorting out which one you are hitting matters, because one of them is a single
setting you change once.

### "SlimRead is no longer available"

**Do not delete the app.** That message is iOS's, not SlimRead's, and deleting is the one
action that turns a five-minute fix into losing your login and your reading position.

It means iOS wants to re-download the app from the App Store and cannot, because SlimRead was
never there. **Look at the icon to tell why**, because the two causes have different cures:

**With a cloud ☁ beside the name — offloading.** iOS deleted the binary to reclaim storage
and kept the data. Cure it permanently, once:

**Settings → App Store → Offload Unused Apps → off.**

Also check **Settings → General → iPhone Storage**, which offers to offload apps individually
when space is short. SlimRead is a prime candidate — reading a long series fills the web
view's cache, so it looks large and idle to iOS.

**With a normal icon — not offloading.** The binary is still there and iOS has decided it
needs replacing anyway. That comes from the signing side rather than storage:

- The free provisioning profile lasted its 7 days and expired. This more often shows as
  "Unable to Verify App", but not always.
- An iOS update, or a restore from backup, left the app as a record iOS expects to re-fetch
  from the App Store.
- The signing certificate was revoked — the free tier does this if an Apple ID registers too
  many app IDs.

Turning off offloading does nothing for any of these. The immediate fix is the same as ever —
run `SlimRead.bat` and re-sideload over the top, data intact — but the thing that stops it
recurring is a longer-lived signature, which is the section below.

### The app stops opening after 7 days — certificate expiry

This is the signing clock, and it is separate. A **free** Apple ID signs apps for 7 days.
Five ways to stop thinking about it — four of them free. They differ in what they still
require of you: a computer that stays on, some fiddling, an old iOS, or money.

**1. Sideloadly's refresh daemon — free, needs the PC reachable.**

1. When sideloading, tick **auto-refresh** before pressing Start.
2. With the phone connected by cable: iTunes → your device → Summary → Options → tick
   **Sync with this iDevice over Wi-Fi** → Sync.

Sideloadly then re-signs whenever the phone is on the same network as the PC. The PC has to
be switched on and reachable when the 7 days are up, which is the catch.

**2. AltStore with AltServer — free, same constraint as Sideloadly.**

Functionally the same trade as option 1: a desktop app re-signs over Wi-Fi when the phone and
the computer are on the same network. Worth knowing about as an alternative if Sideloadly's
daemon is unreliable for you, but it does not remove the need for a computer that is switched
on.

**3. SideStore — free, and no computer after setup.**

An AltStore fork that does the refreshing **on the device**. It stands up a local connection
to Apple's services on-phone rather than through a desktop, so once it is set up nothing else
has to be running. Still 7-day certificates underneath — they are just renewed without you or
your PC.

The catch is setup: it wants a pairing file generated once from a computer, and it leans on
iOS behaviour that shifts between releases, so it periodically breaks after an iOS update
until the project catches up. This is the free option that genuinely removes the weekly chore,
at the cost of being the fiddliest to get working.

**4. TrollStore — free, permanent, and only on old iOS.**

On the iOS versions it supports, TrollStore installs apps with a signature that **never
expires**. No refreshing, no seven days, no computer — install once and it stays. That is a
complete answer to this whole section.

It works by way of a flaw Apple fixed. Support runs to roughly **iOS 17.0**, with the exact
cut-off depending on the build, and there is no way onto it from a newer release because iOS
cannot be downgraded. Check **Settings → General → About → Software Version** before spending
any time on it: if that reads 17.1 or later, this option does not exist for your device and no
amount of effort will make it.

**5. A paid Apple Developer Program account — $99/year, no PC needed weekly.**

This is the real answer to "permanently, without sideloading every time", and it is the only
one that also addresses a normal-icon "no longer available". A paid account signs for **one
year** instead of seven days, so re-signing goes from a weekly chore to an annual one, and a
year-long profile is not sitting one week away from expiry every time iOS decides to
revalidate something. You are not publishing anything and not submitting to review — the
program is exactly what it says, a developer account for building your own apps onto your own
device. It also lifts the free tier's three-app limit.

**What to avoid: "free signing" websites and enterprise certificates.**

Services that sign an IPA for you without your own Apple ID are almost always distributing
under someone else's enterprise certificate. Apple revokes those regularly and in bulk, so the
app dies without warning and often takes others with it — and it means handing your build, and
sometimes your Apple ID, to a stranger. Not worth it for an app you can sign yourself.

### Why not just put it on the App Store?

Competing with someone is not illegal. There is no law against writing a browser that can
open a website which also happens to have its own app, and a general-purpose browser is an
ordinary, lawful thing to build. That part of the worry can be set down.

The real barrier is Apple's **App Review Guidelines**, which are policy rather than law, and
SlimRead would very likely fail two of them:

- **4.2 Minimum Functionality.** A browser whose purpose is one site reads as a repackaged
  website. That is a standard rejection.
- **5.2 Intellectual Property.** An app built around another company's content and name,
  without their permission, is one App Review declines to referee.

Separately, a site's Terms of Service are a contract between that site and you. Breaching
terms is a civil matter with them — not a criminal one, and not something the App Store is
the arbiter of.

What *would* create real legal exposure is hosting or redistributing content, breaking a
paywall or DRM, or using someone's trademarks as your own. SlimRead is built to do none of
those, and the reasoning is set out under [What this is not](#what-this-is-not).

None of this is legal advice, and this file is not written by a lawyer. If you ever intend to
distribute SlimRead to other people rather than run it yourself, that is the point to get a
real opinion — the analysis changes completely once other people are involved.

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

### If the GitHub username or repository ever changes again

<!-- Written after the move from the previous username. The link-fixing is the easy half; the
     half that matters is that baseURL is COMPILED IN, so already-installed copies keep asking
     the old address, and GitHub hands the old username to whoever claims it next. -->

Renaming is not just a link edit. `baseURL` in `TweaksLoader.swift` is compiled into the
binary, and the app fetches JavaScript from it and runs it on every page at document start.
Three things follow, in order of importance:

1. **Claim the old username and keep it.** GitHub releases an abandoned username for anyone to
   register, and its redirects stop the moment somebody does. Every copy of the app installed
   before the rename still asks the *old* address for `tweaks.js` — so whoever holds that name
   can serve arbitrary JavaScript into those copies, inside the reader's logged-in session.
   Registering the old name on a second free account costs nothing and is the only measure that
   protects copies already on people's phones.
2. **Cut a new release.** The prebuilt IPA in Releases has the old URL inside it, so
   `SlimRead.bat` keeps handing out the old address until a new build is published from the
   renamed repository.
3. **Reinstall your own copy** once that release exists, so your phone stops using the old
   address too.

Then update the references: `$Owner` in `SlimRead.ps1` and `Publish-Update.ps1`, `baseURL` in
`TweaksLoader.swift`, and the URLs in `README.md`, `llms.txt` and everything under `docs/`
(canonical links, `og:url`, the JSON-LD `url` and `codeRepository`, `sitemap.xml`,
`robots.txt`). The GitHub Pages address changes too — it is derived from the username. The
workflows in `.github/workflows/` need no edit; they use the repository they run in.

### Telling search engines about a docs/ change

<!-- Only relevant to pages, not to the app. tweaks/ reaches the phone directly and is not
     something a search engine indexes, so there is nothing to ping after a tweaks push. -->

After publishing a change under `docs/`, **double-click `Ping IndexNow.bat`** — same as every
other script here, no command line needed. The window stays open afterwards so you can read
what happened.

It asks Bing, DuckDuckGo and Yandex to re-crawl immediately rather than waiting for their own
schedule. No account is needed — IndexNow proves ownership with a key file
(`docs/c074d34cf0890a1e22bbd2db959f0fc5.txt`) whose name and contents match the key in the
script. The script checks that the file is actually published before submitting anything, so a
push that has not finished deploying fails with a readable message instead of a silent
rejection.

**Google is not covered.** Google trialled IndexNow and does not use it, so Google discovery
still depends on Search Console and on ordinary crawling. There is no no-account equivalent.

<!-- The two files under docs/ that prove ownership are load-bearing, not leftovers. Both are
     re-checked by the service that issued them, so deleting either silently un-verifies the
     site and the submissions stop working with no error anywhere. -->

**Do not delete `docs/google*.html` or `docs/<key>.txt`.** They are how Search Console and
IndexNow prove you own the site, and both are re-checked periodically rather than only once.
Removing either un-verifies the site silently — nothing breaks visibly, submissions just stop
being accepted.

If the key is ever rotated, change it in the script and rename the file to match on both sides,
then push before running it again — a key that disagrees with the hosted file is rejected.

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
Ping IndexNow.bat                 ask Bing/DDG/Yandex to re-crawl after a docs/ change
Ping-IndexNow.ps1
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
docs/                             the GitHub Pages site - a repo cannot set a page
  index.html                      title, meta description, link cards, structured data
  faq.html                        the questions people actually search, answered
  style.css                       shared styles for both pages
  og-card.png                     link preview image; favicon-32/180.png the tab icon
  llms.txt                        copy of the root one, so it resolves at the site root
  robots.txt / sitemap.xml        crawler entry points
  <key>.txt                       IndexNow ownership key - see Ping-IndexNow.ps1
  google*.html                    Search Console proof of ownership - DO NOT DELETE
llms.txt                          machine-readable project summary for AI tools
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
reading position all survive. See [Keeping it installed](#keeping-it-installed) for how to stop it
happening.

### "SlimRead is no longer available"

**Do not delete the app** — that is the one action that loses your login and your reading
position. Re-sideloading over the top keeps both.

There are two different causes and the icon tells you which. See
[Keeping it installed](#keeping-it-installed), which covers both and what actually stops each
one recurring. The short version: a cloud ☁ on the icon means storage, no cloud means
signing, and only the second is fixed by how you sign.

**Either way, run `SlimRead.bat` and re-sideload over the top.** Sideloadly reinstalls the
same bundle identifier, so the existing data container reattaches: logins, reading position,
saved scroll offsets and any `?slimread=` settings all come back. Nothing needs re-fetching —
`tweaks/` is pulled fresh from this repository on the next launch regardless.

### A page renders oddly, or a tweak went too far

Everything about page layout lives in [`tweaks/`](tweaks/). Delete the offending rule, push,
and reopen the app — worst case the page renders exactly as it would in Safari. The app keeps
the last version it fetched successfully, so a bad edit or an offline launch cannot leave you
with a broken reader.

## Licence

MIT — see [LICENSE](LICENSE).
