/* ===========================================================================
   SlimRead page tweaks - LIVE FILE
   ---------------------------------------------------------------------------
   Fetched from GitHub at launch. Edit, push, reopen the app. No rebuild.

   The app draws the page edge to edge, under the sensor housing and into the
   rounded corners - so this file adds viewport-fit=cover everywhere, and the
   reader work below is scoped to episode pages only. Listing pages keep the
   site's own grid.

   Reader jobs:
     1. Load panels ahead of where you are, with a real concurrency limit.
     2. Continuous chapter scroll: reaching the end appends the next chapter;
        pulling down at the very top goes back to the previous one.
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

    var TWEAKS_VERSION = '1.16 b11 01 Aug 18:50';
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

    // How far ahead panels start loading, as a percentage of the viewport.
    //
    // This is the one knob that decides whether a panel is ready before you reach
    // it. Panels are around 1700px tall against a ~850px screen, so 300% (2550px)
    // was only about 1.5 panels of warning - enough to see the black gap while the
    // download and decode finish. 800% is roughly 4 panels ahead, which covers
    // several seconds of reading.
    //
    // It stays proportional to the viewport, not the document, so a bigger number
    // does not mean loading the whole chapter at once: at 800% only the handful of
    // panels within ~6800px are ever in flight.
    //
    // Turn it down if it ever feels heavy on cellular; turn it up if a black gap
    // comes back. Nothing else needs to change.
    var LOAD_MARGIN = '800% 0px 800% 0px';

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
                promote(entries[i].target);
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
                var pg = text.match(/"page"\s*:\s*(\d+)/);
                IS.page = pg ? parseInt(pg[1], 10) : IS.page + 1;
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

    function prevIdBefore(id) {
        return ensureIndexOf(id).then(function (i) { return i > 0 ? IS.order[i - 1] : null; });
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
                });
        }).catch(function () { IS.appending = false; });
    }

    /* Keep the URL and title in step with whichever chapter is under the top of
       the screen. Measured on scroll rather than observed - a zero-height anchor
       plus a top-edge condition is exactly the case IntersectionObserver does
       not report. */
    function updateChapterURL() {
        if (!IS.blocks.length) return;
        var current = null;
        for (var i = 0; i < IS.blocks.length; i++) {
            if (IS.blocks[i].anchor.getBoundingClientRect().top <= 1) current = IS.blocks[i];
            else break;
        }
        var id = current ? current.id : IS.headId;
        var title = current ? current.title : null;
        if (id && ('/episode/' + id) !== location.pathname) {
            try { history.replaceState(null, '', '/episode/' + id); } catch (e) {}
            if (title) document.title = title;
        }
    }

    function maybeAppend() {
        if (!IS.active) return;
        var doc = document.documentElement;
        var remaining = doc.scrollHeight - (window.scrollY + window.innerHeight);
        if (remaining < window.innerHeight * 2.5) appendNextChapter();
    }

    /* Previous chapter. Prepending would fight the scroll position, so this is a
       real navigation - and it lands at the BOTTOM of that chapter, which is
       where you were reading from. */
    var LAND_KEY = 'slimread.landAtBottom';
    var prevBusy = false;

    function goPrev() {
        if (prevBusy || !IS.active) return;
        prevBusy = true;
        prevIdBefore(IS.headId).then(function (pid) {
            if (!pid) { prevBusy = false; return; }
            try { sessionStorage.setItem(LAND_KEY, pid); } catch (e) {}
            location.href = '/episode/' + pid;
        }).catch(function () { prevBusy = false; });
    }

    function applyLandAtBottom() {
        var want;
        try { want = sessionStorage.getItem(LAND_KEY); } catch (e) { return; }
        if (!want || want !== currentEpisodeId()) return;
        try { sessionStorage.removeItem(LAND_KEY); } catch (e) {}

        // Panels reserve their height, so the page is already the right length;
        // settle it over a few frames as the last panels decode.
        var tries = 0;
        (function settle() {
            window.scrollTo(0, document.documentElement.scrollHeight);
            if (tries++ < 12) setTimeout(settle, 120);
        })();
    }

    var pullStartY = 0, pullFromTop = false;
    function bindPrevGesture() {
        document.addEventListener('touchstart', function (e) {
            pullStartY = e.touches[0].clientY;
            pullFromTop = window.scrollY <= 0;
        }, { passive: true });

        document.addEventListener('touchmove', function (e) {
            if (prevBusy || !pullFromTop) return;
            if (window.scrollY > 0) { pullFromTop = false; return; }
            if ((e.touches[0].clientY - pullStartY) > 130) goPrev();
        }, { passive: true });

        var wheelUp = 0;
        window.addEventListener('wheel', function (e) {
            if (prevBusy) return;
            if (window.scrollY <= 0 && e.deltaY < 0) {
                wheelUp += -e.deltaY;
                if (wheelUp > 260) goPrev();
            } else wheelUp = 0;
        }, { passive: true });
    }

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
        bindPrevGesture();
        applyLandAtBottom();
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
        });
    }

    function startReader() {
        setupContinuousScroll();
        preconnectImageHost();
        observeImages();
        window.addEventListener('scroll', onScroll, { passive: true });
        window.addEventListener('load', function () { observeImages(); });
        setTimeout(function () { observeImages(); }, 500);
        setTimeout(function () { observeImages(); }, 1500);
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
        window.addEventListener('popstate', check);
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
