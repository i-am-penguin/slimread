# Changelog

Newest first. The publish script reads the top section for the commit message and
the release notes, so whatever is written here is what shows up on GitHub.

Keep the top heading as `## Unreleased` while working. The publish script renames
it to the version number when a build is published.

## Unreleased

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
