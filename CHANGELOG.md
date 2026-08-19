# Changelog

Newest first. The publish script reads the top section for the commit message and
the release notes, so whatever is written here is what shows up on GitHub.

Keep the top heading as `## Unreleased` while working. The publish script renames
it to the version number when a build is published.

## Unreleased
- Throttle the end-of-page check. atBottom() watched for the reader reaching the
  bottom with a bare scroll listener that read scrollHeight - a forced layout -
  on every event, with none of the per-frame throttling the main scroll handler
  has. It is armed only between the stitch cap latching and the reader reaching
  the end, which is about two screens of scrolling rather than a whole chapter,
  so the exposure was smaller than it first looked; but an unthrottled reflow per
  scroll event is never right. Now one measurement per frame, which during a
  momentum scroll costs a boolean check per event.
- Keep the append watchdog off the scroll path. It read scrollHeight every 700ms
  regardless of what the reader was doing, and that read is a full reflow of a
  70,000px page whenever panels are still arriving. It exists for when the
  scrolling has STOPPED - a chapter ending near the bottom on arrival, and the fact
  that being at the bottom produces no more scroll events - so while the page is
  moving it has nothing to add. Nothing is lost by waiting: appending needs the end
  to hold still for over a second anyway, so it could not have fired mid-glide.
- Write the reading offset only when it counts. localStorage.setItem is
  synchronous, so saving on the throttled scroll path put a storage write on the
  main thread once a second while the reader was moving, for a value immediately
  superseded. Coming to rest, leaving the page and backgrounding the app all still
  force it, which covers every moment the exact number matters.
  Together, over twenty seconds of reading: 256 forced layout reads before, 221
  now, against 251 for the released build.
- Stop doing work on every scroll event while the page is coasting. Everything in
  the scroll handler is throttled to one run per frame, and iOS suspends
  requestAnimationFrame during a momentum scroll - so the frame callback never
  runs, the early return fires, and the handler is meant to cost one boolean check
  per event while the page glides. The trailing save added below cleared and
  re-armed a timeout above that return: a fresh closure and a timer churned on
  every scroll event, sixty to a hundred and twenty times a second, at exactly the
  moment nothing else was running. Reported as stuttering while the scroll coasts
  rather than while the finger is down. A timestamp costs no allocation and no
  timer work: 3.3us per event with the churn, 1.6us without - below the 2.6us the
  handler cost before the trailing save existed at all.
- The panel watchdog skips settled pages. It walked every image on the page every
  three seconds, twice, and once a chapter has loaded there is nothing outstanding
  to find. It now bails on a flag, which is the state the reader is in for almost
  all of a chapter.
- reportPosition() asked which chapter is under the top twice - once for the id and
  again for the offset - and each call reads a bounding rect per stitched chapter,
  forcing layout twice for one answer, up to once a second while scrolling.
- Put the reload offer in the gap, not over the page. It was a bar pinned to the
  bottom of the screen, so it sat in the reader's way for the whole time they were
  still reading the panels above the fault - offering a fix for a problem they had
  not reached yet, on top of the page they were reading. It now sits at the first
  panel that failed: out of sight until they arrive at the gap, and then exactly
  where the missing panel should be.
- Name the chapter when reloading rather than reloading the address bar. The button
  called location.reload(), which reloads whatever the URL happens to hold - on a
  stitched page that is maintained as the reader crosses boundaries, so it is one
  more thing that has to be right for them to land where they were. It now goes to
  the same chapter reportPosition() just saved the offset against, so the two
  cannot disagree.
- Retry the panels the reader is looking at first. The watchdog scans backwards -
  it has to, to judge each panel against the ones after it - and the candidates
  came out of that scan in reverse, so the two retries allowed per pass were spent
  on the panels furthest down the page. With everything failing, the retries went
  79, 78, 77, 76 from the very end backwards, while the gap in front of the reader
  waited its turn. They now go in reading order, 0, 1, 2, 3.
- Save the position once scrolling stops. It is written at most once a second and
  only from a scroll event, so the last second of movement before coming to rest
  was never recorded - stop mid-flick and the remembered spot was up to a second
  behind, measured at 4500px adrift. Backgrounding the app hid this by forcing a
  save; a reload did not. Now exact.
- Offer a way back when the panels are beyond retrying. Retrying asks for the same
  URL again, which recovers a panel that was dropped and does nothing for one whose
  URL has gone stale - and image URLs on these services are typically signed and
  time-limited, so a page left open overnight is holding addresses that have since
  expired. Every panel not already loaded then fails outright, retrying cannot help,
  and giving up was silent and permanent: a chapter of broken panels with no way
  back. Once several panels are past help the reader is told, and offered the one
  thing that fixes it. Nothing reloads on its own - that would throw away the
  stitched chapters and the reading position unasked.
- Give failed panels another go when the app comes back to the foreground. A panel
  written off under whatever the connection was doing yesterday should not stay
  broken because of it.
- Wait for the page before giving up on the reading position. The position was
  always saved correctly - it was the restore that quit. It waits for the page to
  grow tall enough to hold the offset, and that wait was a flat 25 attempts at
  150ms: 3.75 seconds, whatever the page was doing at the end of them. A chapter is
  ~130 panels that only take up space as they load, so on a slow connection the
  page is nowhere near tall enough by then, and the restore abandoned the reader at
  the top in silence. Worse the deeper into a chapter they were, a larger offset
  needing a taller page - which reads as remembering less and less accurately the
  further you read. Present since the feature was added in 1.21, not new.
  A clock cannot decide this, because the right amount of time is however long the
  panels take. It now waits while the page is still growing and stops when it is
  not, and if the chapter really is shorter than the offset it goes as far as there
  is rather than to the top. Measured on a slow connection, 23400px deep: was
  abandoned at 0, now restored exactly.
- Retry a panel that the panels after it have overtaken. The quiet check below
  counted the stalled panels themselves, and a stalled panel never completes, so
  it counted against itself forever: five simultaneous stalls held the count above
  the threshold and none of them was ever retried - 0 of 5 recovered, the blank
  gap intact. What identifies a stuck panel is not how many are outstanding but
  whether the ones AFTER it have arrived, since panels are requested in order. All
  5 now recover in about 5 seconds, and a slow connection still triggers no retries
  at all.
- Two more in the same retry. `release` was registered on both `load` and `error`
  with `{once}`, which removes only the event that fired - so an `error` left the
  `load` listener attached and unreachable, to fire later on the next retry's
  placeholder and unpin the box mid-swap. It now removes both itself. And a panel
  that has already been retried no longer holds the chapter boundary: retrying
  puts it back to `complete === false`, which had `tailResolved()` waiting out its
  full escape timer at the end of every chapter carrying a broken panel.
- Only retry a panel once the page has gone quiet. The retry added below started
  every panel's clock at the same instant, because every panel is promoted at the
  same instant - so on a connection too slow to pull a chapter within the timeout,
  all ~130 were declared stalled together, all aborted mid-download, and all
  restarted. Measured on a 40-panel chapter at 20s a panel: 40 aborted at once,
  160 requests where 40 would do, every panel out of retries by t+50s, nothing
  loaded. A slow chapter turned into a broken one, which is worse than the fault
  it was added for. Time cannot tell "stalled" from "slow" when everything is
  slow; the number of panels still outstanding can. A stalled panel is only
  interrupted once few others are left, at most two per pass. A request that
  failed outright is still retried immediately - it is holding nothing open.
- Two smaller faults in the same retry, both from the placeholder used to cancel a
  stalled request. It loads instantly, so it consumed the one-shot listener that
  releases the height pin - unpinning the box mid-retry and letting a 1x1 image
  render full width, the exact shift the pin exists to prevent - and, with
  `reserve=on`, the one-shot listener that clears reserved space, dropping a panel
  that still had no image to zero height for good.
- Ask again for a panel that never arrived. A chapter opens by requesting all ~130
  of its panels at once, at high priority, and a CDN under that burst will
  occasionally stall or drop one. Nothing retried it - a browser does not
  re-request an image on its own, and neither did this file - so an unlucky panel
  stayed blank for as long as you stayed on the page, and reloading did not help
  because a reload re-fires the same burst. A watchdog now catches both shapes: a
  request that finished with no image, and one that is still open long after it
  should have arrived, which fires no error event and can only be found by a clock.
  Three tries, then it stops.
  Retrying is not just re-assigning the URL: while the first request is still open
  the browser folds the second into it, so the retry attaches to the very stall it
  was meant to escape. The panel is parked on the placeholder first to cancel the
  old request, and the URL itself is never altered - a cache-busting parameter
  would force the issue but would break a signed image URL, turning a slow panel
  into a permanently forbidden one.

## v1.26 - 2026-08-12
- Fetch tweaks/ in the background, so the newest copy is already stored when the
  app opens. The fetch used to start at launch and race the first page load; the
  page won, rendered with the previous copy, and the app reloaded once the new
  script arrived. Correct, but visible. This lands the files ahead of time so
  there is nothing to correct. Purely an optimisation - iOS decides whether these
  ever run, and Background App Refresh can be switched off, so the reload path
  stays exactly as it was.

- Publishing now pulls work pushed from another device before it touches
  anything locally. The divergence used to surface only at the push, by which
  point the run had already stamped tweaks.js, rolled the changelog and made a
  commit - leaving the PC half-advanced, with the obvious next move (forcing the
  push) silently destroying whatever the other device did. Overlapping edits stop
  with instructions instead of guessing.
- Draw the way on at the end of the page, where the scrolling stops. Pausing at the
  stitch cap announced itself with a toast naming the next-chapter button - gone in
  1.6 seconds, and naming a button inside a control bar that has to be summoned from
  the top-left corner first. Reaching the end and finding nothing was therefore
  indistinguishable from the reader being broken, and was reported as exactly that,
  with 45 seconds between arriving at the wall and finding the way past it. There is
  now a real button in the page at the point the scrolling ends, with a line saying
  why the pause exists. `?slimread=autonav=on` still skips the pause entirely.
- Stop the reader moving to the next chapter on its own. Appending and navigating
  were driven from the same trigger, which fires when the bottom of the page comes
  within 2.5 screens. That is right for an append - the chapter lands below you,
  unseen, ready by the time you reach it - and wrong for a navigation, which throws
  away everything below you and moves you to another page. At a reading pace it
  took you off the chapter with two full screens still unread; measured at 1708px
  on an 844px viewport. Reaching the stitch cap now stops and says so, and the
  next-chapter button takes it from there: changing chapter is yours to do.
  `?slimread=autonav=on` restores continuous reading past the cap, and even then
  waits for the true bottom rather than the append trigger's lead.
- Record a chapter trail, always, and show it with `?slimread=trail`. "It changed
  chapter on its own" has several causes that feel alike and cannot be told apart
  afterwards: scrolling across a stitched boundary, the app reloading the web view
  and discarding the stitched page, a deliberate navigation, or history. The last
  30 changes are now kept with the cause of each, including whether a page arrived
  by navigation, reload or back/forward - a reload being the app replacing the page
  under you, which nothing inside the page could otherwise see. It records whether
  or not a knob is set, since a switch that has to be flipped before the bug is no
  use.
- Say when a knob is set, and add `?slimread=show` to ask later. A knob changes how
  the reader behaves and then persists with nothing on screen to say so, which
  makes one turned on and forgotten indistinguishable from a bug - `stitch=2` has
  already been reported as one, having quietly moved the chapter cap onto the third
  chapter. Setting a knob now confirms itself, and `show` reports what is in force
  without changing it.
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
