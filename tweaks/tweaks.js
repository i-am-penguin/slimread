/* ===========================================================================
   SlimRead page tweaks - LIVE FILE
   ---------------------------------------------------------------------------
   Fetched from GitHub at launch. Edit, push, reopen the app. No rebuild.

   The app draws the page edge to edge, under the sensor housing and into the
   rounded corners - so this file adds viewport-fit=cover everywhere, and the
   reader work below is scoped to episode pages only. Listing pages keep the
   site's own grid.

   Reader jobs:
     1. Load panels well ahead of where you are, and prime the first few of every
        chapter so one never opens on blank panels.
     2. Continuous chapter scroll: reaching the end appends the next chapter, and
        each chapter reached pushes a history entry so Back steps through them.
        There is no scroll-up gesture - it fired on any brisk flick to the top.
     3. Strip the site's chrome inside a chapter - top bar, bottom toolbar,
        comments, recommendations - so only the artwork remains.

   Panel loading is driven by an IntersectionObserver, deliberately. iOS keeps
   computing intersections during momentum scrolling but suspends
   requestAnimationFrame until the scroll settles, so a scroll+rAF loader stops
   dead the moment the page is flicked. Versions 1.12-1.14 did exactly that and
   stopped loading mid-chapter; 1.11 and earlier used the observer and did not.
   =========================================================================== */

(function () {
    'use strict';

    if (window.__slimread) return;
    window.__slimread = true;

    var root = document.documentElement;

    /* --- Version marker (stamped by the publish script) ------------------ */

    var TWEAKS_VERSION = '1.22 b17 04 Aug 16:45';
    var SHOW_BADGE = true;

    function showVersionBadge() {
        if (!SHOW_BADGE || !document.body) return;
        try {
            if (localStorage.getItem('slimread.tweaksSeen') === TWEAKS_VERSION) return;
            localStorage.setItem('slimread.tweaksSeen', TWEAKS_VERSION);
        } catch (e) { /* private mode - show it, harmless */ }

        var badge = document.createElement('div');
        badge.className = 'slimread-badge';
        badge.textContent = 'tweaks ' + TWEAKS_VERSION;
        document.body.appendChild(badge);
        setTimeout(function () { badge.className = 'slimread-badge slimread-badge-out'; }, 2200);
        setTimeout(function () { if (badge.parentNode) badge.parentNode.removeChild(badge); }, 2800);
    }

    /* --- Reader detection ------------------------------------------------ */

    var READER_PATH = /\/(episode|viewer|ep)\//i;
    function isReaderPage() { return READER_PATH.test(location.pathname); }
    function currentEpisodeId() { var m = location.pathname.match(/\/episode\/(\d+)/); return m ? m[1] : null; }

    function markReader() {
        var on = isReaderPage();
        root.classList.toggle('slimread-reader', on);
        return on;
    }

    /* --- Edge to edge ---------------------------------------------------- */

    function coverViewport() {
        var metas = document.querySelectorAll('meta[name="viewport"]');
        if (!metas.length) {
            if (!document.head) return;   // too early; boot() calls this again
            var meta = document.createElement('meta');
            meta.setAttribute('name', 'viewport');
            meta.setAttribute('content', 'width=device-width, initial-scale=1, viewport-fit=cover');
            document.head.appendChild(meta);
            return;
        }
        for (var i = 0; i < metas.length; i++) {
            var content = metas[i].getAttribute('content') || '';
            if (!/viewport-fit\s*=\s*cover/i.test(content)) {
                metas[i].setAttribute('content', content.replace(/\s*,\s*$/, '') + ', viewport-fit=cover');
            }
        }
    }

    /* --- 1. Panel loading -------------------------------------------------
       Each panel is handed to an IntersectionObserver with a wide margin, and
       loads when it comes within range. No concurrency limiter: the browser's
       own connection scheduling handles that, and every home-made queue tried
       here so far has found a new way to wedge itself.

       Quality: the site serves one resolution per panel via data-src (940px
       wide JPEG, no srcset, no size parameters). That is the maximum
       available, and it is exactly what is used - nothing here downscales.
       --------------------------------------------------------------------- */

    var LAZY_ATTRS = ['data-src', 'data-original', 'data-lazy-src', 'data-url', 'data-echo'];
    var TRANSPARENT = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';

    // When a panel comes within this much of the viewport it is considered
    // "reached", which starts the rolling window below. Kept moderate on purpose -
    // the depth of the buffer is AHEAD_PANELS' job, not this one's.
    var LOAD_MARGIN = '600% 0px 600% 0px';

    // The buffer that travels with you. Reaching any panel also starts the next
    // AHEAD_PANELS after it, so the loaded region rolls forward as you read and is
    // always this many panels deep - not just at the start of a chapter.
    //
    // At ~1700px each that is roughly 20,000px of artwork ready ahead of you.
    var AHEAD_PANELS = 12;

    // Panels loaded the instant a chapter is entered, without waiting for the
    // observer, so a chapter opens already drawn rather than filling in.
    var PRIME_COUNT = 12;

    // How many chapters may be stitched onto one page before the next one is
    // reached by navigating instead. Each chapter is ~130 panels that are never
    // released, so without a cap a long session ends in iOS killing the app - and
    // that is what loses your reading position. Four chapters is a long stretch of
    // uninterrupted scrolling; the fifth costs one page load at a chapter boundary.
    var MAX_STITCHED = 4;

    function lazyURL(img) {
        for (var i = 0; i < LAZY_ATTRS.length; i++) {
            var v = img.getAttribute(LAZY_ATTRS[i]);
            if (v && v.indexOf('data:') !== 0) return v;
        }
        return null;   // nothing lazy here - already carrying a real src
    }

    /* DNS, TCP and TLS to the image CDN cost a round trip each, and they are
       otherwise paid at the moment the first panel is requested. Warming the
       connection while the HTML is still parsing takes that off the critical
       path for every panel that follows. */
    function preconnectImageHost() {
        if (preconnectImageHost.done || !document.head) return;
        var probe = document.querySelector('.content__img');
        var url = probe && lazyURL(probe);
        if (!url) return;
        var origin;
        try { origin = new URL(url, location.href).origin; } catch (e) { return; }
        preconnectImageHost.done = true;
        ['preconnect', 'dns-prefetch'].forEach(function (rel) {
            var l = document.createElement('link');
            l.rel = rel;
            l.href = origin;
            l.crossOrigin = 'anonymous';
            document.head.appendChild(l);
        });
    }

    function panelNodes() {
        // Live collection - newly appended chapters appear automatically.
        return (IS.article || document).getElementsByTagName('img');
    }

    function promote(img) {
        if (img.__slimreadDone) return;
        img.__slimreadDone = true;

        var real = lazyURL(img);
        if (!real) return;                // nothing lazy about it; leave it alone

        img.loading = 'eager';
        img.decoding = 'async';
        // The panels you are about to look at outrank everything else the page
        // still wants to fetch.
        try { img.fetchPriority = 'high'; } catch (e) {}
        img.setAttribute('fetchpriority', 'high');

        if (img.getAttribute('src') !== real) img.setAttribute('src', real);
    }

    /* Reaching a panel also starts the ones after it, so the loaded region rolls
       forward with you instead of being a fixed distance from the viewport.

       Walks siblings rather than indexing a live collection: chapter anchors and
       dividers sit between panels, and appended chapters continue the same sibling
       chain, so this keeps working straight across a chapter boundary. Costs
       AHEAD_PANELS steps, once per panel reached. */
    function promoteAhead(img) {
        promote(img);
        var node = img, started = 0;
        while (node && started < AHEAD_PANELS) {
            node = node.nextElementSibling;
            if (!node) break;
            if (node.tagName === 'IMG') { promote(node); started++; }
        }
    }

    /* An IntersectionObserver is what drives loading, and that choice matters.
       On iOS, intersections keep being computed during momentum scrolling, while
       requestAnimationFrame callbacks are suspended until the scroll settles. A
       scroll+rAF version of this loop therefore stopped loading anything the
       moment you flicked the page - which is exactly how loading "stopped" from
       1.12 onward. Left alone, WebKit also manages decoded-image memory for
       off-screen images by itself, so nothing here needs to unload them. */
    var imgObserver = null;

    function ensureImgObserver() {
        if (imgObserver) return imgObserver;
        imgObserver = new IntersectionObserver(function (entries) {
            for (var i = 0; i < entries.length; i++) {
                if (!entries[i].isIntersecting) continue;
                promoteAhead(entries[i].target);
                imgObserver.unobserve(entries[i].target);
            }
        }, { root: null, rootMargin: LOAD_MARGIN, threshold: 0 });
        return imgObserver;
    }

    function observeImages(scope) {
        var io = ensureImgObserver();
        var imgs = (scope || IS.article || document).getElementsByTagName('img');
        for (var i = 0; i < imgs.length; i++) {
            var img = imgs[i];
            if (img.__slimObserved || img.__slimreadDone) continue;
            img.__slimObserved = true;
            io.observe(img);
        }
    }

    /* --- 2. Continuous chapter scroll ------------------------------------ */

    var IS = {
        seriesId: null,
        order: [],
        page: 0,
        hasMore: true,
        tailId: null,
        headId: null,
        article: null,
        blocks: [],        // { id, title, anchor } per appended chapter
        appending: false,
        ended: false,
        active: false
    };

    function seriesIdFromDom() {
        var el = document.querySelector('[data-series-id]');
        return el ? el.getAttribute('data-series-id') : null;
    }

    function apiEpisodes(page) {
        return fetch('/series/' + IS.seriesId + '/episodes?page=' + page + '&sort=OLDEST',
            { credentials: 'include', headers: { 'x-requested-with': 'XMLHttpRequest' } })
            .then(function (r) { return r.ok ? r.text() : null; })
            .then(function (text) {
                if (!text) return false;
                var ids = [], re = /\/episode\/(\d+)/g, m;
                while ((m = re.exec(text))) {
                    if (IS.order.indexOf(m[1]) < 0 && ids.indexOf(m[1]) < 0) ids.push(m[1]);
                }
                IS.order = IS.order.concat(ids);
                IS.hasMore = /"has_next"\s*:\s*true/.test(text);

                // Track the page WE asked for. The "page" field in the response is
                // the NEXT page, not the current one - requesting page 1 comes back
                // saying "page":2. Trusting it meant asking for page+1 = 3 next and
                // skipping page 2 entirely, so anything past episode 20 was never
                // found and the reader decided the series had ended.
                IS.page = page;
                // No new ids and no next page: stop, or ensureIndexOf would spin.
                if (!ids.length && !IS.hasMore) return false;
                return true;
            })
            .catch(function () { IS.hasMore = false; return false; });
    }

    function ensureIndexOf(id) {
        var guard = 0;
        function step() {
            var i = IS.order.indexOf(id);
            if (i >= 0 || !IS.hasMore || guard++ > 40) return Promise.resolve(i);
            return apiEpisodes(IS.page + 1).then(step);
        }
        return step();
    }

    function nextIdAfter(id) {
        return ensureIndexOf(id).then(function (i) {
            if (i < 0) return null;
            if (i >= IS.order.length - 1 && IS.hasMore) {
                return apiEpisodes(IS.page + 1).then(function () { return IS.order[i + 1] || null; });
            }
            return IS.order[i + 1] || null;
        });
    }


    function extractPanels(html) {
        var doc = new DOMParser().parseFromString(html, 'text/html');
        var src = doc.querySelectorAll('.content__img');
        var out = [];
        for (var i = 0; i < src.length; i++) {
            var p = src[i];
            var real = p.getAttribute('data-src');
            if (!real) {
                var s = p.getAttribute('src');
                if (s && s.indexOf('data:') !== 0) real = s;
            }
            if (!real) continue;
            out.push({
                src: real,
                w: p.getAttribute('width') || p.getAttribute('data-width'),
                h: p.getAttribute('height') || p.getAttribute('data-height')
            });
        }
        var title = (doc.querySelector('title') || {}).textContent || '';
        return { panels: out, title: title.replace(/\s*\|\s*Tapas.*$/i, '').replace(/^Read\s+/i, '').trim() };
    }

    function appendNextChapter() {
        if (!IS.active || IS.appending || IS.ended || !IS.article) return;
        IS.appending = true;

        nextIdAfter(IS.tailId).then(function (nid) {
            if (!nid) { IS.ended = true; IS.appending = false; return; }

            // Stitching never released anything, so a long session grew until iOS
            // killed the web process or the app - and a termination in the
            // foreground is what loses your place. Past the cap, move on by
            // navigating instead: memory resets completely, and you land at the top
            // of the next chapter, which is exactly where the scroll would have put
            // you anyway.
            if (IS.blocks.length >= MAX_STITCHED) {
                // Latch before navigating. The append watchdog keeps ticking until
                // the new document actually replaces this one, and without this it
                // would re-enter and assign location.href over and over.
                IS.ended = true;
                IS.appending = false;
                location.href = '/episode/' + nid;
                return;
            }
            return fetch('/episode/' + nid, { credentials: 'include' })
                .then(function (r) { return r.ok ? r.text() : null; })
                .then(function (html) {
                    if (!html) { IS.appending = false; return; }   // network blip, retry later

                    var data = extractPanels(html);
                    // Fetched fine but no panels: locked/paid chapter, or the end.
                    if (!data.panels.length) { IS.ended = true; IS.appending = false; return; }

                    var frag = document.createDocumentFragment();

                    var anchor = document.createElement('div');
                    anchor.className = 'slimread-chapter-anchor';
                    frag.appendChild(anchor);

                    var divider = document.createElement('div');
                    divider.className = 'slimread-chapter-divider';
                    divider.textContent = data.title || 'Next chapter';
                    frag.appendChild(divider);

                    for (var i = 0; i < data.panels.length; i++) {
                        var p = data.panels[i];
                        var img = document.createElement('img');
                        img.className = 'content__img slimread-appended';
                        img.setAttribute('data-src', p.src);
                        img.setAttribute('src', TRANSPARENT);
                        if (p.w) img.setAttribute('width', p.w);
                        if (p.h) img.setAttribute('height', p.h);
                        // Reserves the right height before the panel loads, so the
                        // scroll position never jumps as chapters stream in.
                        if (p.w && p.h) img.style.aspectRatio = p.w + ' / ' + p.h;
                        frag.appendChild(img);
                    }

                    IS.article.appendChild(frag);
                    IS.tailId = nid;
                    IS.blocks.push({ id: nid, title: data.title, anchor: anchor });

                    IS.appending = false;
                    observeImages(IS.article);   // hand the new panels to the observer

                    // Draw the start of the new chapter straight away, so arriving
                    // at it never lands on blank panels.
                    primeFrom(anchor, PRIME_COUNT);
                });
        }).catch(function () { IS.appending = false; });
    }

    /* Keep the URL and title in step with whichever chapter is under the top of
       the screen.

       The first time a chapter is reached this PUSHES a history entry, so the
       app's back button steps back through chapters like real pages. Coming back
       to a chapter you have already been through only replaces, or scrolling up
       and down over one boundary would stack duplicate entries.

       Back does not reload: popstate scrolls to that chapter's anchor, so the
       continuously-scrolled content stays exactly as it is. */
    var pushedIds = {};

    function chapterUnderTop() {
        var current = null;
        for (var i = 0; i < IS.blocks.length; i++) {
            if (IS.blocks[i].anchor.getBoundingClientRect().top <= 1) current = IS.blocks[i];
            else break;
        }
        return current;
    }

    function updateChapterURL() {
        if (!IS.blocks.length) return;
        var current = chapterUnderTop();
        var id = current ? current.id : IS.headId;
        var title = current ? current.title : null;
        if (!id || ('/episode/' + id) === location.pathname) return;

        try {
            if (pushedIds[id]) history.replaceState({ slimread: id }, '', '/episode/' + id);
            else history.pushState({ slimread: id }, '', '/episode/' + id);
        } catch (e) { return; }

        pushedIds[id] = true;
        if (title) document.title = title;
    }

    /* Back / forward within the stitched chapters: scroll rather than navigate. */
    function scrollToEpisode(id) {
        if (!id) return false;
        if (id === IS.headId) { window.scrollTo(0, 0); return true; }
        for (var i = 0; i < IS.blocks.length; i++) {
            if (IS.blocks[i].id !== id) continue;
            var y = IS.blocks[i].anchor.getBoundingClientRect().top + window.scrollY;
            window.scrollTo(0, y);
            return true;
        }
        return false;
    }

    function maybeAppend() {
        if (!IS.active || IS.ended) return;

        var vh = window.innerHeight;
        var height = document.documentElement.scrollHeight;

        // Two guards against appending a chapter nobody asked for.
        //
        // A page that has not reached its real height yet - panels still taking up
        // their space - trivially looks "near the end", and the watchdog runs on a
        // timer rather than on scroll. Together that meant arriving at a chapter
        // could append the next one immediately, then the next, until the stitch
        // cap navigated onward: the reader advancing chapters on its own.
        if (height < vh * 3) return;        // too short to be a real chapter yet
        if (window.scrollY <= 0) return;    // still at the very top - not the end

        if (height - (window.scrollY + vh) < vh * 2.5) appendNextChapter();
    }

    /* Safety net for appending.
       The scroll handler was the only thing that ever called maybeAppend, which
       fails in two ways: a chapter short enough to sit near the bottom on arrival
       never triggers one, and once you are AT the bottom there is no scrolling
       left to fire the check - so the reader just stops. iOS also suspends
       requestAnimationFrame during momentum scrolling, delaying it further.
       A slow timer costs one scrollHeight read and removes all three. */
    var appendTimer = null;
    function startAppendWatchdog() {
        if (appendTimer) return;
        appendTimer = setInterval(function () {
            if (!IS.active) return;
            if (IS.ended) { clearInterval(appendTimer); appendTimer = null; return; }
            maybeAppend();
        }, 700);
    }

    /* There is deliberately no scroll-up-for-previous-chapter gesture.
       It fired on any brisk upward flick that reached the top, yanking you out of
       the chapter you were reading. Going back is the app's back button now, which
       is unambiguous and cannot trigger itself. */

    /* --- Remembering where you were -------------------------------------
       Two halves. The chapter goes to the app, which reopens there next launch.
       The offset within that chapter is kept here, because the app only restores
       a URL and a stitched page cannot be rebuilt from one.
       --------------------------------------------------------------------- */

    var POS_KEY = 'slimread.pos.';
    var lastReport = 0;

    // localStorage.setItem is a synchronous write; doing it every scroll frame is
    // exactly the kind of thing that makes scrolling stutter. Once a second is
    // plenty to never lose more than a screen, and the important moments
    // (arriving, leaving, backgrounding) pass force = true.
    function reportPosition(force) {
        var now = Date.now();
        if (!force && now - lastReport < 1000) return;
        lastReport = now;

        var id = null;
        if (IS.blocks.length) { var c = chapterUnderTop(); if (c) id = c.id; }
        if (!id) id = currentEpisodeId();
        if (!id) return;

        var href = location.origin + '/episode/' + id;
        try {
            if (window.webkit && window.webkit.messageHandlers &&
                window.webkit.messageHandlers.slimread) {
                window.webkit.messageHandlers.slimread.postMessage({ type: 'position', url: href });
            }
        } catch (e) { /* not running in the app - fine */ }

        // Offset measured from the top of the chapter you are in, so it still means
        // something when that chapter is reopened on its own.
        try {
            var base = 0;
            if (IS.blocks.length) {
                var b = chapterUnderTop();
                if (b) base = b.anchor.getBoundingClientRect().top + window.scrollY;
            }
            var within = Math.max(0, Math.round(window.scrollY - base));
            localStorage.setItem(POS_KEY + id, String(within));
        } catch (e) {}
    }

    /* Restore the offset for the chapter just opened. Cancelled the moment you
       scroll yourself, so it can never fight you for control. */
    function restorePosition() {
        var id = currentEpisodeId();
        if (!id) return;

        var want = 0;
        try { want = parseInt(localStorage.getItem(POS_KEY + id) || '0', 10); } catch (e) { return; }
        if (!want || want < window.innerHeight) return;   // near the top anyway

        var cancelled = false;
        function cancel() { cancelled = true; }
        window.addEventListener('touchstart', cancel, { passive: true, once: true });
        window.addEventListener('wheel', cancel, { passive: true, once: true });

        // Wait for the page to be tall enough to hold that offset, then scroll ONCE
        // and stop. Scrolling repeatedly would keep dragging the page back while it
        // is still growing - the reader tugging against itself.
        var tries = 0;
        (function settle() {
            if (cancelled) return;
            if (document.documentElement.scrollHeight > want + window.innerHeight) {
                window.scrollTo(0, want);
                return;
            }
            if (++tries < 25) setTimeout(settle, 150);
        })();
    }

    /* Brief on-screen message. The button used to do its work silently, so a tap
       that resolved to nothing was indistinguishable from a tap that missed. */
    function toast(text) {
        var el = document.getElementById('slimread-toast');
        if (!el) {
            el = document.createElement('div');
            el.id = 'slimread-toast';
            el.className = 'slimread-toast';
            (document.body || root).appendChild(el);
        }
        el.textContent = text;
        el.className = 'slimread-toast';
        clearTimeout(toast.timer);
        toast.timer = setTimeout(function () { el.className = 'slimread-toast slimread-toast-out'; }, 1600);
    }

    /* Called by the app's next-chapter button - the manual way out when the
       automatic append has not happened, or cannot.

       This navigates rather than trying to stitch and scroll. Stitching is for
       reading continuously; when you have deliberately asked to move on, the
       reliable thing is simply to go there. */
    var navigating = false;

    window.__slimreadNextChapter = function () {
        if (navigating) return;   // repeated taps while the next page is on its way

        var here = null;
        if (IS.blocks.length) { var c = chapterUnderTop(); if (c) here = c.id; }
        if (!here) here = IS.headId || currentEpisodeId();

        // Read these fresh rather than depending on setupContinuousScroll having
        // run. The old version bailed to clicking the site's own Next button,
        // which does not navigate - so the tap did nothing at all, silently.
        if (!IS.seriesId) IS.seriesId = seriesIdFromDom();

        if (!IS.seriesId || !here) {
            toast('Cannot tell which chapter this is');
            return;
        }

        toast('Loading next chapter...');
        navigating = true;
        nextIdAfter(here).then(function (nid) {
            if (nid) { location.href = '/episode/' + nid; return; }
            navigating = false;
            toast('This is the latest chapter');
        }).catch(function () {
            navigating = false;
            toast('Could not reach the next chapter');
        });
    };

    function setupContinuousScroll() {
        IS.seriesId = seriesIdFromDom();
        IS.article = document.querySelector('.js-episode-article, .viewer__body');
        var cur = currentEpisodeId();

        if (!IS.seriesId || !IS.article || !cur) {
            // Cannot drive chapters ourselves. The CSS hides the site's own
            // toolbar, so without this the reader would be stranded with no way
            // to reach the next chapter at all.
            root.classList.add('slimread-no-continuous');
            return;
        }

        IS.active = true;
        IS.tailId = cur;
        IS.headId = cur;
        primeChapter(IS.article);
    }

    /* Entering a chapter, load its opening panels immediately rather than waiting
       for the observer to notice them. The observer still handles everything
       after that; this only removes the wait at the start of each chapter. */
    function primeChapter(scope) {
        if (!scope) return;
        var imgs = scope.getElementsByTagName('img');
        var n = Math.min(imgs.length, PRIME_COUNT);
        for (var i = 0; i < n; i++) promote(imgs[i]);
    }

    /* Same idea for an appended chapter: walk forward from its anchor and load the
       first few panels of that chapter only. */
    function primeFrom(anchor, count) {
        var node = anchor, done = 0;
        // nextElementSibling, matching promoteAhead - nextSibling also walks text
        // nodes, which is just wasted iterations between panels.
        while (node && done < count) {
            node = node.nextElementSibling;
            if (!node) break;
            if (node.tagName === 'IMG') { promote(node); done++; }
        }
    }

    /* --- Wiring ---------------------------------------------------------- */

    // Image loading is NOT driven from here - the observer handles it, including
    // during momentum scrolling when these callbacks do not run. This only keeps
    // the URL current and decides when to append the next chapter, neither of
    // which is urgent enough to care about a paused frame or two.
    var scrollQueued = false;
    function onScroll() {
        if (scrollQueued) return;
        scrollQueued = true;
        requestAnimationFrame(function () {
            scrollQueued = false;
            updateChapterURL();
            maybeAppend();
            reportPosition();
        });
    }

    function startReader() {
        setupContinuousScroll();
        preconnectImageHost();
        observeImages();
        startAppendWatchdog();
        restorePosition();
        reportPosition(true);      // record the chapter immediately on arrival

        window.addEventListener('scroll', onScroll, { passive: true });
        window.addEventListener('load', function () { observeImages(); maybeAppend(); });
        setTimeout(function () { observeImages(); maybeAppend(); }, 500);
        setTimeout(function () { observeImages(); maybeAppend(); }, 1500);

        // The last word before the app is backgrounded or the page goes away.
        // pagehide and visibilitychange are the two that reliably fire on iOS.
        window.addEventListener('pagehide', function () { reportPosition(true); });
        document.addEventListener('visibilitychange', function () {
            if (document.visibilityState === 'hidden') reportPosition(true);
        });
    }

    // Panels the site itself streams into the current chapter.
    var mo = null;
    var moQueued = false;
    function syncMutationObserver() {
        if (isReaderPage() && !mo) {
            mo = new MutationObserver(function () {
                if (moQueued) return;
                moQueued = true;
                requestAnimationFrame(function () { moQueued = false; observeImages(); });
            });
            mo.observe(root, { childList: true, subtree: true });
        } else if (!isReaderPage() && mo) {
            mo.disconnect();
            mo = null;
        }
    }

    function onRouteChange() {
        var lastPath = location.pathname;
        function check() {
            if (location.pathname === lastPath) return;
            lastPath = location.pathname;
            markReader();
            syncMutationObserver();
        }
        ['pushState', 'replaceState'].forEach(function (name) {
            var orig = history[name];
            if (typeof orig !== 'function') return;
            history[name] = function () { var r = orig.apply(this, arguments); check(); return r; };
        });

        window.addEventListener('popstate', function (e) {
            // Back/forward between chapters we stitched together: scroll to it
            // instead of letting the browser reload and lose the stitched page.
            var id = (e.state && e.state.slimread) || currentEpisodeId();
            if (IS.active && scrollToEpisode(id)) {
                lastPath = location.pathname;
                return;
            }
            check();
        });
    }

    function boot() {
        coverViewport();
        showVersionBadge();
        syncMutationObserver();
        onRouteChange();
        if (isReaderPage()) startReader();
    }

    // Both at document start, so the page never paints with the wrong rules.
    markReader();
    coverViewport();

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', boot, { once: true });
    } else {
        boot();
    }
})();
