/* ===========================================================================
   SlimRead page tweaks - LIVE FILE
   ---------------------------------------------------------------------------
   Fetched from GitHub at launch. Edit, push, reopen the app.

   Three jobs:
     1. Force lazy-loaded episode images to load eagerly, and prefetch ahead,
        so scrolling does not stall on blank panels.
     2. Strip the horizontal padding that leaves white bars beside the art.
     3. Slide the site's fixed bottom bar out of the way while scrolling and
        bring it back at the end of the chapter.
   =========================================================================== */

(function () {
    'use strict';

    if (window.__slimread) return;
    window.__slimread = true;

    /* --- 1. Image loading ------------------------------------------------ */

    // Sites lazy-load panels and swap a placeholder for the real source on
    // scroll. Promote every known lazy attribute immediately instead.
    var LAZY_ATTRS = ['data-src', 'data-original', 'data-lazy-src', 'data-url', 'data-echo'];

    function promote(img) {
        if (img.__slimreadDone) return;

        for (var i = 0; i < LAZY_ATTRS.length; i++) {
            var value = img.getAttribute(LAZY_ATTRS[i]);
            if (value && img.getAttribute('src') !== value) {
                img.setAttribute('src', value);
                break;
            }
        }

        var lazySrcset = img.getAttribute('data-srcset');
        if (lazySrcset) img.setAttribute('srcset', lazySrcset);

        img.loading = 'eager';
        img.decoding = 'async';
        img.__slimreadDone = true;
    }

    function promoteAll() {
        var images = document.images;
        for (var i = 0; i < images.length; i++) promote(images[i]);
    }

    // Warm the browser cache for images just below the viewport, so they are
    // decoded before they scroll into view.
    function prefetchAhead() {
        var images = document.images;
        var viewportBottom = window.scrollY + window.innerHeight;
        var budget = 6;

        for (var i = 0; i < images.length && budget > 0; i++) {
            var img = images[i];
            if (img.__slimreadPrefetched) continue;

            var top = img.getBoundingClientRect().top + window.scrollY;
            if (top > viewportBottom && top < viewportBottom + window.innerHeight * 4) {
                var src = img.currentSrc || img.src;
                if (src) {
                    var warm = new Image();
                    warm.src = src;
                    img.__slimreadPrefetched = true;
                    budget--;
                }
            }
        }
    }

    /* --- 2. Layout ------------------------------------------------------- */

    // Some containers set an inline pixel width, which CSS cannot override.
    // Find the wrapper that actually holds the art and clear it.
    function unpadArtwork() {
        var images = document.images;
        for (var i = 0; i < images.length; i++) {
            var img = images[i];
            if (img.naturalWidth < 300) continue;   // skip icons and avatars

            var node = img.parentElement;
            var hops = 0;
            while (node && hops < 4) {
                var style = node.style;
                if (style) {
                    style.setProperty('max-width', '100%', 'important');
                    style.setProperty('width', '100%', 'important');
                    style.setProperty('padding-left', '0', 'important');
                    style.setProperty('padding-right', '0', 'important');
                    style.setProperty('margin-left', '0', 'important');
                    style.setProperty('margin-right', '0', 'important');
                }
                node = node.parentElement;
                hops++;
            }
        }
    }

    /* --- 3. The site's own fixed bottom bar ------------------------------ */

    function findFixedBottomBars() {
        var found = [];
        var candidates = document.body ? document.body.querySelectorAll('div, nav, footer, section') : [];

        for (var i = 0; i < candidates.length; i++) {
            var el = candidates[i];
            var cs = window.getComputedStyle(el);
            if (cs.position !== 'fixed' && cs.position !== 'sticky') continue;
            if (cs.display === 'none' || cs.visibility === 'hidden') continue;

            var rect = el.getBoundingClientRect();
            var sitsAtBottom = rect.bottom > window.innerHeight - 12 && rect.top > window.innerHeight * 0.55;
            var isBarShaped = rect.height > 0 && rect.height < 140 && rect.width > window.innerWidth * 0.6;

            if (sitsAtBottom && isBarShaped) {
                el.classList.add('slimread-autohide');
                found.push(el);
            }
        }
        return found;
    }

    var bars = [];
    var lastY = window.scrollY;

    function updateBars() {
        if (!bars.length) return;

        var y = window.scrollY;
        var goingDown = y > lastY + 4;
        var goingUp = y < lastY - 4;
        var atEnd = (window.innerHeight + y) >= (document.body.scrollHeight - 220);

        if (atEnd || goingUp) {
            for (var i = 0; i < bars.length; i++) bars[i].classList.remove('slimread-hidden');
        } else if (goingDown) {
            for (var j = 0; j < bars.length; j++) bars[j].classList.add('slimread-hidden');
        }

        if (goingDown || goingUp) lastY = y;
    }

    /* --- Wiring ---------------------------------------------------------- */

    function sweep() {
        promoteAll();
        unpadArtwork();
        bars = findFixedBottomBars();
    }

    var scrollQueued = false;
    window.addEventListener('scroll', function () {
        if (scrollQueued) return;
        scrollQueued = true;
        window.requestAnimationFrame(function () {
            scrollQueued = false;
            updateBars();
            prefetchAhead();
        });
    }, { passive: true });

    // Re-sweep as the page fills in, and on client-side route changes.
    new MutationObserver(function () {
        promoteAll();
    }).observe(document.documentElement, { childList: true, subtree: true });

    sweep();
    setTimeout(sweep, 600);
    setTimeout(sweep, 2000);
    window.addEventListener('load', sweep);
})();
