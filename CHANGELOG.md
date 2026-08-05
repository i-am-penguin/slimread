# Changelog

Newest first. The publish script reads the top section for the commit message and
the release notes, so whatever is written here is what shows up on GitHub.

Keep the top heading as `## Unreleased` while working. The publish script renames
it to the version number when a build is published.

## Unreleased
- Add runtime knobs, set from the address bar, for the numbers this file cannot
  measure from where it is written - buffer depth, load margin, stitch cap,
  whether panels reserve space - plus a meter reading how blocked the main thread
  is while scrolling. `tapas.io/?slimread=hud=on`, `?slimread=stitch=2,ahead=6`,
  `?slimread=reserve=off` to compare against the old loading behaviour,
  `?slimread=reset` to clear. Stored, so it survives moving between chapters.
  Inert unless set: with nothing stored this reads one key and stops.
- Found why the panel buffer has never rolled, then left it not rolling. It loads
  whatever falls inside a band around the viewport - but an unloaded panel is a
  zero-height box, so before anything loads the whole chapter is collapsed into a
  few pixels and every panel is inside that band at once. Every version since 1.15
  has therefore fetched all ~130 panels of a chapter the moment it opened, which
  also means AHEAD_PANELS, PRIME_COUNT and LOAD_MARGIN have done nothing at all
  since 1.15. Reserving each panel's space up front fixes it - 12 on arrival
  instead of 130 - but it moves every load, and the box resize behind it, into the
  scroll. scrollHeight is read every scroll frame and every watchdog tick, and it
  is free while layout is clean and a full reflow while it is dirty: 0.001ms
  against 0.105ms on a 227k-px page. Loading panels is what dirties layout. All at
  once means layout settles once and scrolling is cheap after; as-you-go means it
  is never settled while you move, which on the device reads as scrolling that
  drags and recovers the moment you stop. Off by default on that evidence, and
  available as `?slimread=reserve=on`. Worth another go if the reserved size can
  be made exact enough not to resize on load.
- Fix the reader dead-ending at the end of a chapter. Appending was gated on the
  page being at least three screens tall, as a stand-in for "the panels have
  finished taking up their space". A chapter that never reaches three screens -
  a notice, an author's note, a bonus page - therefore never qualified, and one
  opened directly stopped there for good: no next chapter, no message, and
  nothing left to scroll. A chapter too short to scroll at all was doubly stuck,
  because appending also required a scroll that could never happen.
  What that height check was really reaching for is "the panels have taken up
  their space", and the panels can simply be asked. Appending now waits for the
  ones at the bottom of the page to have resolved - loaded or failed - so length
  decides nothing, and a two-panel chapter qualifies the moment those two draw.
  Height cannot tell a short chapter from an unloaded one; the panels can.
- Stop treating "could not work out the next chapter" as "there is no next
  chapter". Locating the current chapter walks the episode list from page one,
  and running out of walk - which happens to whoever is deepest into a longest
  series - latched the reader as finished for the rest of the page and said
  "Reached the latest chapter". Only a lookup that succeeds and shows nothing
  after this chapter ends the reader now; everything else retries, and a list
  walked to its end without the chapter in it is discarded and rebuilt.
- Retry a failed append instead of falling silent, briskly at first and never
  slower than every five seconds, and say so if it goes on.

## v1.25 - 2026-08-04
- Apply a changed tweaks.js without waiting for a navigation. User scripts are
  registered when the web view is created, from the previously stored copy, and
  WKWebView only applies a newly registered one at the next page load - so the
  page in front of you kept running the old script. Re-registering it was not
  enough; the page is now reloaded when the script actually changed. CSS was
  never affected, which is why layout changes appeared and behaviour changes did
  not.
- The refresh now reports which of the two files changed, so a CSS-only edit
  still swaps in silently with no reload.

## v1.23 - 2026-08-04
- Fix the reader stalling for good at the end of a chapter. Fetching the next one
  set an "appending" flag and had no timeout, so a request that never settled -
  a stalled radio, a hung connection - left that flag set forever, and it blocks
  every future append. Both network calls now time out, and the watchdog releases
  the flag if it is ever stuck regardless of cause.
- Say why the reader stopped instead of just stopping: "Reached the latest
  chapter" or "Next chapter is locked or unavailable". A silent stop was
  indistinguishable from a bug.

- Fix a single network hiccup ending the endless scroll for the rest of the page.
  A failed episode-list lookup cleared the "there are more pages" flag, so every
  later lookup gave up instantly, the caller read that as "no next chapter" and
  latched the reader as finished. It only became easy to hit once the append
  watchdog started calling the API early and often. A failed lookup is now
  transient and the next attempt - under a second later - recovers.
- The next-chapter button no longer says "This is the latest chapter" when it
  simply could not reach the server.

## v1.22 - 2026-08-04
- Fix the release build failing whenever a changelog entry contained a double
  quote. Actions substitutes expressions textually into the shell, so the quotes
  in a note closed the --notes string and the rest of the words were passed to gh
  as asset names, which failed with: no matches found for `the`. Notes now go to a
  file read with --notes-file, and inputs come from the environment instead of
  being expanded inside the script.
- Fold repeat publishes of the same version into one changelog section. A failed
  release leaves the version free, so retrying it stamped a second heading with
  the same number.
- Fix the reader advancing chapters on its own. The append watchdog added in 1.20
  runs on a timer rather than on scroll, and "near the end" was measured from the
  page height - which is small while panels are still taking up their space. So
  arriving at a chapter could append the next one immediately, and the next, until
  the stitch cap navigated onward. Appending now requires a page that has reached
  a real height and that you have actually scrolled.

## v1.21 - 2026-08-04
- Remember the chapter you were reading, reliably. The app was reading the web
  view's URL, but chapters advance through history.pushState from the page, so it
  could reopen at the chapter you originally opened rather than the one you had
  scrolled to. The page now reports its chapter to the app directly.
- Remember the position within a chapter too, restored on reopening and cancelled
  the instant you scroll yourself.
- Write the saved position straight to disk. It was flushed on the system's own
  schedule, so a termination under memory pressure discarded the most recent
  chapter - which is why progressing further made it more likely to forget.
- Reload where you were if iOS kills the web content process, instead of leaving
  a blank page behind.
- Guard both places that navigate to another chapter against re-entry. The append
  watchdog keeps ticking until the new document replaces the old one, so it could
  assign location.href repeatedly, and repeated taps on the next-chapter button
  did the same.
- Cap continuous stitching at 4 chapters, then move on by navigating. Nothing was
  ever released, so a long session grew until iOS killed the app - and that is
  what lost your place. Reading is unbroken for four chapters; the fifth costs one
  page load at a chapter boundary.

## v1.20 - 2026-08-01
- Fix the endless scroll stopping at the bottom of a chapter. Appending was only
  ever triggered from the scroll handler, so once you were AT the end there was no
  scrolling left to fire it, and a chapter short enough to arrive near the bottom
  never appended at all. A slow watchdog now checks independently of scrolling.
- Prime-ahead for appended chapters walked text nodes instead of elements, wasting
  iterations between panels.
- Guide text corrected: it still described tapping anywhere along the top to show
  the controls, and did not mention continuous chapters or the next-chapter button.

## v1.19 - 2026-08-01
- Panel loading now rolls forward with you. Reaching any panel starts the next 12
  after it, so the loaded region always stays that deep ahead of wherever you are
  - previously only the start of each chapter was preloaded, and the rest relied
  on a fixed distance from the viewport that a fast scroll could outrun.
- The buffer carries across chapter boundaries, stepping over the divider so the
  first panels of the next chapter are already loading before you reach them.

## v1.18 - 2026-08-01
- Fix the endless scroll stopping after 20 episodes. The episode-list API returns
  the NEXT page number in its "page" field, not the current one, so asking for
  page+1 skipped every other page - anything past episode 20 was never found and
  the reader decided the series had ended.
- Next-chapter button now navigates directly instead of trying to stitch and
  scroll, and shows a message either way. It previously fell back to clicking the
  site's own Next button, which does not navigate - so the tap did nothing at all.
- Tapping next-chapter no longer closes the control bar, so a tap is never
  mistaken for an accidental dismissal.
- Only the top-LEFT corner toggles the control bar. Full-width tap zones above and
  inside the bar were swallowing taps meant for its buttons.
- Panels now load 16 screens ahead and each chapter primes its first 12 panels, so
  artwork is drawn well before it is scrolled to.

## v1.17 - 2026-08-01
- Disable scroll-up-to-previous-chapter. It fired on any brisk upward flick that
  reached the top and yanked you out of the chapter you were reading.
- Back button now steps through chapters. Each chapter reached while scrolling
  pushes a real history entry, and going back scrolls to it rather than
  reloading, so the stitched-together page survives.
- Add a next-chapter button to the control bar, beside the guide button. Manual
  fallback for when the automatic chapter append has not happened yet.
- Preload the first panels of every chapter on entry, so a new chapter never
  opens on blank panels.
- Panels now start loading 8 screens ahead instead of 3, removing the black gap
  before an image appears while scrolling.
- Hide the translucent scroll indicator again. WebKit re-enables it on every
  navigation, so it is now re-disabled on each page commit and finish.
