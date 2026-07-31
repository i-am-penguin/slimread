/* ===========================================================================
   SlimRead page tweaks - LIVE FILE
   ---------------------------------------------------------------------------
   Fetched from GitHub at launch. Edit, push, reopen the app.

   Four jobs:
     1. Mark reader pages, so the aggressive full-bleed CSS only applies where
        it belongs. Everything outside the reader (home, series, search) keeps
        the site's own grid - forcing 100% widths there is what turns cover
        thumbnails into small images floating in big black cards.
     2. Force lazy-loaded episode images to load eagerly, and prefetch ahead,
        so scrolling does not stall on blank panels.
     3. Strip the horizontal padding that leaves white bars beside the art.
     4. Tag the site's own fixed bars so CSS can inset them clear of the
        rounded display corners, and slide the bottom one out of the way
        while scrolling.

   Injected at document start. DOM work waits for the document to be ready.
   =========================================================================== */

(function () {
    'use strict';

    if (window.__slimread) return;
    window.__slimread = true;

    var root = document.documentElement;

    /* --- Version marker --------------------------------------------------
       BUMP THIS whenever you push tweaks. It is the only way to confirm from
       the phone that a tweaks push actually landed, and unlike the app version
       it needs no sideload - this file is fetched fresh on every launch.

       The badge shows once per version, for about two seconds, then never
       again until this string changes. Set SHOW_BADGE to false to silence it.
       --------------------------------------------------------------------- */

    var TWEAKS_VERSION = '2026-08-01.1';
    var SHOW_BADGE = true;

    function showVersionBadge() {
        if (!SHOW_BADGE || !document.body) return;

        // Only announce a version once. Private mode throws on localStorage, in
        // which case showing it every time is the harmless outcome.
        try {
            if (window.localStorage.getItem('slimread.tweaksSeen') === TWEAKS_VERSION) return;
            window.localStorage.setItem('slimread.tweaksSeen', TWEAKS_VERSION);
        } catch (e) { /* no storage - fall through and show it */ }

        var badge = document.createElement('div');
        badge.className = 'slimread-badge';
        badge.textContent = 'tweaks ' + TWEAKS_VERSION;
        document.body.appendChild(badge);

        setTimeout(function () { badge.className = 'slimread-badge slimread-badge-out'; }, 2200);
        setTimeout(function () {
            if (badge.parentNode) badge.parentNode.removeChild(badge);
        }, 2800);
    }

    /* --- 0. Reader detection --------------------------------------------- */

    // Only the episode viewer wants edge-to-edge artwork. Listing pages are a
    // grid of cover thumbnails and must keep their own sizing.
    var READER_PATH = /\/(episode|viewer|ep)\//i;

    function isReaderPage() {
        return READER_PATH.test(location.pathname);
    }

    function markReader() {
        var on = isReaderPage();
        root.classList.toggle('slimread-reader', on);
        return on;
    }

    /* Let CSS env() insets resolve. Without viewport-fit=cover the web content
       reports zero safe-area insets, so the site's fixed bars run under the
       Dynamic Island and into the rounded corners. */
    function coverViewport() {
        var metas = document.querySelectorAll('meta[name="viewport"]');

        if (!metas.length) {
            // At document start <head> may not exist yet. Do nothing rather than hang
            // a meta off <html>, where the site's own tag would later override it -
            // sweep() calls this again once the document is ready.
            if (!document.head) return;
            var meta = document.createElement('meta');
            meta.setAttribute('name', 'viewport');
            meta.setAttribute('content', 'width=device-width, initial-scale=1, viewport-fit=cover');
            document.head.appendChild(meta);
            return;
        }

        // Patch every one of them - the last tag in the document is the one that wins.
        for (var i = 0; i < metas.length; i++) {
            var content = metas[i].getAttribute('content') || '';
            if (!/viewport-fit\s*=\s*cover/i.test(content)) {
                metas[i].setAttribute('content', content.replace(/\s*,\s*$/, '') + ', viewport-fit=cover');
            }
        }
    }

    /* --- 1. Image loading ------------------------------------------------ */

    // Sites lazy-load panels and swap a placeholder for the real source on
    // scroll. Promote every known lazy attribute immediately instead.
    var LAZY_ATTRS = ['data-src', 'data-original', 'data-lazy-src', 'data-url', 'data-echo'];

    function hasPendingLazyAttr(img) {
        for (var i = 0; i < LAZY_ATTRS.length; i++) {
            if (img.getAttribute(LAZY_ATTRS[i])) return true;
        }
        return !!img.getAttribute('data-srcset');
    }

    function promote(img) {
        if (img.__slimreadDone) return;

        var promoted = false;
        for (var i = 0; i < LAZY_ATTRS.length; i++) {
            var value = img.getAttribute(LAZY_ATTRS[i]);
            if (value && img.getAttribute('src') !== value) {
                img.setAttribute('src', value);
                promoted = true;
                break;
            }
        }

        var lazySrcset = img.getAttribute('data-srcset');
        if (lazySrcset && img.getAttribute('srcset') !== lazySrcset) {
            img.setAttribute('srcset', lazySrcset);
            promoted = true;
        }

        img.loading = 'eager';
        img.decoding = 'async';

        // Only close the door once there is nothing left to swap in. Sites populate
        // data-src late; marking every image done on the first pass - which is what
        // this used to do - means those never get promoted at all.
        if (promoted || !hasPendingLazyAttr(img)) {
            img.__slimreadDone = true;
        }

        // Panels are measured by natural size, which is zero until they decode.
        if (!img.__slimreadWatched) {
            img.__slimreadWatched = true;
            if (img.complete) {
                unpadFor(img);
            } else {
                img.addEventListener('load', function () { unpadFor(img); }, { once: true });
            }
        }
    }

    function promoteAll() {
        var images = document.images;
        for (var i = 0; i < images.length; i++) promote(images[i]);
    }

    // Warm the cache for images just below the viewport, so they are decoded
    // before they scroll into view.
    //
    // The cursor only ever moves forward. Rescanning from index 0 meant every
    // image already scrolled past was re-measured on every single scroll frame,
    // and getBoundingClientRect forces layout - so the cost grew the further
    // into a chapter you read.
    var prefetchCursor = 0;

    function prefetchAhead() {
        var images = document.images;
        var viewportBottom = window.scrollY + window.innerHeight;
        var horizon = viewportBottom + window.innerHeight * 4;
        var budget = 6;

        while (prefetchCursor < images.length && budget > 0) {
            var img = images[prefetchCursor];
            var top = img.getBoundingClientRect().top + window.scrollY;

            if (top > horizon) break;   // far enough ahead - stop, keep the cursor here

            prefetchCursor++;
            var src = img.currentSrc || img.src;
            if (src && top > viewportBottom) {
                var warm = new Image();
                warm.src = src;
                budget--;
            }
        }
    }

    /* --- 2. Layout ------------------------------------------------------- */

    // Some containers set an inline pixel width, which CSS cannot override.
    // Find the wrapper that actually holds the art and clear it.
    //
    // Reader pages only, and only for images big enough to be a panel. Applied
    // to a cover thumbnail this forces its card to full width while the image
    // keeps its own size - which is exactly the "small thumbnail in a big black
    // box" the listing pages were showing.
    function isPanel(img) {
        return img.naturalWidth >= 600;
    }

    function unpadFor(img) {
        if (!isReaderPage() || !isPanel(img)) return;

        var node = img.parentElement;
        var hops = 0;
        while (node && node !== document.body && hops < 4) {
            if (!node.__slimreadUnpadded) {
                node.__slimreadUnpadded = true;
                var style = node.style;
                if (style) {
                    style.setProperty('max-width', '100%', 'important');
                    style.setProperty('width', '100%', 'important');
                    style.setProperty('padding-left', '0', 'important');
                    style.setProperty('padding-right', '0', 'important');
                    style.setProperty('margin-left', '0', 'important');
                    style.setProperty('margin-right', '0', 'important');
                }
            }
            node = node.parentElement;
            hops++;
        }
    }

    /* --- 3. The site's own fixed bars ------------------------------------ */

    // Tagged so CSS can pad them clear of the Dynamic Island and the rounded
    // corners. In full-bleed mode the web view runs to the physical edge, so
    // anything the site pins to the top or bottom gets clipped by the curve
    // unless it is inset by the safe-area insets.
    function tagFixedBars() {
        var found = [];
        if (!document.body) return found;

        var candidates = document.body.querySelectorAll('div, nav, header, footer, section');
        var viewportH = window.innerHeight;
        var viewportW = window.innerWidth;

        for (var i = 0; i < candidates.length; i++) {
            var el = candidates[i];
            if (el.__slimreadBarChecked) {
                if (el.classList.contains('slimread-autohide')) found.push(el);
                continue;
            }

            var cs = window.getComputedStyle(el);
            if (cs.position !== 'fixed' && cs.position !== 'sticky') continue;
            if (cs.display === 'none' || cs.visibility === 'hidden') continue;

            var rect = el.getBoundingClientRect();
            var isBarShaped = rect.height > 0 && rect.height < 140 && rect.width > viewportW * 0.6;
            if (!isBarShaped) continue;

            el.__slimreadBarChecked = true;

            var sitsAtBottom = rect.bottom > viewportH - 12 && rect.top > viewportH * 0.55;
            var sitsAtTop = rect.top < 12 && rect.bottom < viewportH * 0.45;

            if (sitsAtBottom) {
                el.classList.add('slimread-fixed-bottom', 'slimread-autohide');
                found.push(el);
            } else if (sitsAtTop) {
                el.classList.add('slimread-fixed-top');
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
        markReader();
        coverViewport();
        promoteAll();
        bars = tagFixedBars();
    }

    var scrollQueued = false;
    function onScroll() {
        if (scrollQueued) return;
        scrollQueued = true;
        window.requestAnimationFrame(function () {
            scrollQueued = false;
            updateBars();
            prefetchAhead();
        });
    }

    // The observer fires for every node the page adds. Unthrottled, that is a
    // full document.images walk per mutation on an infinite-scrolling page.
    var promoteQueued = false;
    function queuePromote() {
        if (promoteQueued) return;
        promoteQueued = true;
        window.requestAnimationFrame(function () {
            promoteQueued = false;
            promoteAll();
        });
    }

    // Client-side navigation does not reload the document, so the reader class
    // and the bar tags have to be recomputed by hand.
    function watchRouteChanges() {
        var lastPath = location.pathname;

        function check() {
            if (location.pathname === lastPath) return;
            lastPath = location.pathname;
            prefetchCursor = 0;
            markReader();
            window.requestAnimationFrame(sweep);
        }

        ['pushState', 'replaceState'].forEach(function (name) {
            var original = history[name];
            if (typeof original !== 'function') return;
            history[name] = function () {
                var result = original.apply(this, arguments);
                check();
                return result;
            };
        });
        window.addEventListener('popstate', check);
    }

    function start() {
        sweep();
        showVersionBadge();

        window.addEventListener('scroll', onScroll, { passive: true });
        new MutationObserver(queuePromote).observe(root, { childList: true, subtree: true });
        watchRouteChanges();

        setTimeout(sweep, 600);
        setTimeout(sweep, 2000);
        window.addEventListener('load', sweep);
    }

    // Runs at document start, so the reader class lands before first paint and
    // the page never flashes with the wrong layout rules.
    markReader();
    coverViewport();

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', start, { once: true });
    } else {
        start();
    }
})();
