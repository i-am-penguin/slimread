# Changelog

Newest first. The publish script reads the top section for the commit message and
the release notes, so whatever is written here is what shows up on GitHub.

Keep the top heading as `## Unreleased` while working. The publish script renames
it to the version number when a build is published.

## Unreleased

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
