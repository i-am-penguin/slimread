/* ===========================================================================
   SlimRead page tweaks - LIVE FILE
   ---------------------------------------------------------------------------
   Fetched from GitHub at launch. Edit, push, reopen the app. No rebuild.

   Everything here is scoped to the episode reader. Listing pages (home, series,
   search) are left completely alone - the app's native layout already insets
   the web view to the safe area, so there are no corners or notch to fight.

   Reader jobs:
     1. Load panels progressively as you approach them (fast, no request storm).
     2. Continuous chapter scroll: reaching the end seamlessly appends the next
        chapter; pulling up past the very top goes to the previous one.
     3. Strip Tapas's own chrome inside a chapter - top bar, bottom toolbar,
        comments, recommendations - so only the artwork remains.
   =========================================================================== */

(function () {
    'use strict';

    if (window.__slimread) return;
    window.__slimread = true;

    var root = document.documentElement;

    /* --- Version marker (stamped by the publish script) ------------------ */

    var TWEAKS_VERSION = '1.11 b6 01 Aug 18:07';
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

    /* --- Edge to edge -----------------------------------------------------
       Without viewport-fit=cover WebKit lays the page out INSIDE the safe area
       even when the web view fills the screen - which shows up as a thick black
       bar above and below the page. Applied on every page, not just the reader,
       because the listing pages need it just as much.
       --------------------------------------------------------------------- */
    function coverViewport() {
        var metas = document.querySelectorAll('meta[name="viewport"]');

        if (!metas.length) {
            // <head> may not exist yet at document start; boot() calls this again.
            if (!document.head) return;
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

    /* --- 1. Progressive image loading -----------------------------------
       An IntersectionObserver loads each panel ~2 screens before it is needed.
       This replaced forcing every panel eager at once, which fired one request
       per panel the instant a chapter opened - saturating the connection and
       blocking the main thread (the "cannot tap anything" freeze). Panels keep
       their width/height attributes, so space is reserved and nothing reflows.
       --------------------------------------------------------------------- */

    var LAZY_ATTRS = ['data-src', 'data-original', 'data-lazy-src', 'data-url', 'data-echo'];
    var TRANSPARENT = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';

    function promote(img) {
        if (img.__slimreadDone) return;
        img.__slimreadDone = true;

        for (var i = 0; i < LAZY_ATTRS.length; i++) {
            var v = img.getAttribute(LAZY_ATTRS[i]);
            if (v && img.getAttribute('src') !== v) { img.setAttribute('src', v); break; }
        }
        var ss = img.getAttribute('data-srcset');
        if (ss && img.getAttribute('srcset') !== ss) img.setAttribute('srcset', ss);

        img.loading = 'eager';
        img.decoding = 'async';
    }

    var imgObserver = null;
    function ensureImgObserver() {
        if (imgObserver) return imgObserver;
        imgObserver = new IntersectionObserver(function (entries) {
            for (var i = 0; i < entries.length; i++) {
                if (entries[i].isIntersecting) {
                    promote(entries[i].target);
                    imgObserver.unobserve(entries[i].target);
                }
            }
        }, { root: null, rootMargin: '200% 0px 200% 0px', threshold: 0 });
        return imgObserver;
    }

    function observeImages(scope) {
        var io = ensureImgObserver();
        var imgs = (scope || document).querySelectorAll('img');
        for (var i = 0; i < imgs.length; i++) {
            var img = imgs[i];
            if (img.__slimObserved) continue;
            img.__slimObserved = true;
            // Something already visible (top of the chapter) loads immediately.
            io.observe(img);
        }
    }

    /* --- 2. Continuous chapter scroll -----------------------------------
       Tapas hides the next-episode URL behind a JS handler, but its episode
       list is available as JSON at /series/{id}/episodes. We build the ordered
       list from that, then splice the next chapter's panels straight onto the
       end of the current one - no page reload, no flash. The address bar is
       kept in step as each chapter scrolls under the top of the screen.
       --------------------------------------------------------------------- */

    var IS = {
        seriesId: null,
        order: [],          // episode ids, oldest -> newest
        page: 0,
        hasMore: true,
        tailId: null,       // last chapter appended into the DOM
        headId: null,       // first chapter in the DOM (for "previous")
        article: null,      // the container panels live in
        sentinel: null,
        appending: false,
        ended: false
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
                while ((m = re.exec(text))) if (IS.order.indexOf(m[1]) < 0 && ids.indexOf(m[1]) < 0) ids.push(m[1]);
                IS.order = IS.order.concat(ids);
                var hasNext = /"has_next"\s*:\s*true/.test(text);
                var pg = text.match(/"page"\s*:\s*(\d+)/);
                IS.page = pg ? parseInt(pg[1], 10) : IS.page + 1;
                IS.hasMore = hasNext;
                return true;
            })
            .catch(function () { return false; });
    }

    function ensureIndexOf(id) {
        // Load pages until the id shows up (or we run out).
        function step() {
            if (IS.order.indexOf(id) >= 0) return Promise.resolve(IS.order.indexOf(id));
            if (!IS.hasMore) return Promise.resolve(IS.order.indexOf(id));
            return apiEpisodes(IS.page + 1).then(step);
        }
        return step();
    }

    function nextIdAfter(id) {
        return ensureIndexOf(id).then(function (i) {
            if (i < 0) return null;
            if (i >= IS.order.length - 1 && IS.hasMore) return apiEpisodes(IS.page + 1).then(function () { return IS.order[i + 1] || null; });
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
            var real = p.getAttribute('data-src') || p.getAttribute('src');
            if (!real || real.indexOf('data:') === 0) real = p.getAttribute('data-src');
            if (!real) continue;
            out.push({ src: real, w: p.getAttribute('width') || p.getAttribute('data-width'),
                                   h: p.getAttribute('height') || p.getAttribute('data-height') });
        }
        var title = (doc.querySelector('title') || {}).textContent || '';
        return { panels: out, title: title.replace(/\s*\|\s*Tapas.*$/i, '').trim() };
    }

    function appendNextChapter() {
        if (IS.appending || IS.ended || !IS.article) return;
        IS.appending = true;

        nextIdAfter(IS.tailId).then(function (nid) {
            if (!nid) { IS.ended = true; IS.appending = false; return; }
            return fetch('/episode/' + nid, { credentials: 'include' })
                .then(function (r) { return r.ok ? r.text() : null; })
                .then(function (html) {
                    // Network hiccup - leave the door open to try again next time.
                    if (!html) { IS.appending = false; return; }

                    var data = extractPanels(html);
                    // Fetched fine but no panels: a locked/paid chapter or the end of
                    // the series. Stop, rather than refetching it every scroll.
                    if (!data.panels.length) { IS.ended = true; IS.appending = false; return; }

                    var frag = document.createDocumentFragment();

                    var anchor = document.createElement('div');
                    anchor.className = 'slimread-chapter-anchor';
                    anchor.setAttribute('data-ep-id', nid);
                    anchor.setAttribute('data-ep-title', data.title);
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
                        img.src = TRANSPARENT;
                        if (p.w) img.setAttribute('width', p.w);
                        if (p.h) img.setAttribute('height', p.h);
                        if (p.w && p.h) img.style.aspectRatio = p.w + ' / ' + p.h;
                        frag.appendChild(img);
                    }

                    IS.article.appendChild(frag);
                    IS.tailId = nid;

                    observeImages(IS.article);
                    moveSentinelToEnd();
                    watchChapterAnchor(anchor);

                    IS.appending = false;
                });
        }).catch(function () { IS.appending = false; });
    }

    /* Address bar / saved-position tracking: when a chapter's anchor crosses the
       top of the screen, make its episode the current URL. */
    var anchorObserver = null;
    function watchChapterAnchor(anchor) {
        if (!anchorObserver) {
            anchorObserver = new IntersectionObserver(function (entries) {
                for (var i = 0; i < entries.length; i++) {
                    var e = entries[i];
                    if (e.isIntersecting && e.boundingClientRect.top <= 2) {
                        var id = e.target.getAttribute('data-ep-id');
                        var title = e.target.getAttribute('data-ep-title');
                        if (id && ('/episode/' + id) !== location.pathname) {
                            try { history.replaceState(null, '', '/episode/' + id); } catch (x) {}
                            if (title) document.title = title;
                        }
                    }
                }
            }, { root: null, rootMargin: '0px', threshold: 0 });
        }
        anchorObserver.observe(anchor);
    }

    function moveSentinelToEnd() {
        if (!IS.article) return;
        if (!IS.sentinel) {
            IS.sentinel = document.createElement('div');
            IS.sentinel.className = 'slimread-end-sentinel';
            IS.sentinelObserver = new IntersectionObserver(function (entries) {
                if (entries[0].isIntersecting) appendNextChapter();
            }, { root: null, rootMargin: '300% 0px', threshold: 0 });
            IS.sentinelObserver.observe(IS.sentinel);
        }
        IS.article.appendChild(IS.sentinel);   // keep it the very last child
    }

    function setupContinuousScroll() {
        IS.seriesId = seriesIdFromDom();
        IS.article = document.querySelector('.js-episode-article, .viewer__body');
        var cur = currentEpisodeId();
        if (!IS.seriesId || !IS.article || !cur) return;   // not a recognisable chapter

        IS.tailId = cur;
        IS.headId = cur;
        moveSentinelToEnd();
        bindPrevGesture();
    }

    /* Previous chapter: at the very top, a deliberate downward pull. Prepending
       would fight the scroll position, so going back is a clean navigation - a
       rare action, unlike scrolling forward. */
    var pullStartY = 0, pullAtTop = false, prevBusy = false;
    function scroller() { return document.scrollingElement || document.documentElement; }

    function goPrev() {
        if (prevBusy) return;
        prevBusy = true;
        prevIdBefore(IS.headId).then(function (pid) {
            if (pid) location.href = '/episode/' + pid;
            else prevBusy = false;
        }).catch(function () { prevBusy = false; });
    }

    function bindPrevGesture() {
        if (bindPrevGesture.done) return;
        bindPrevGesture.done = true;

        document.addEventListener('touchstart', function (e) {
            pullStartY = e.touches[0].clientY;
            pullAtTop = scroller().scrollTop <= 0;
        }, { passive: true });

        document.addEventListener('touchmove', function (e) {
            if (prevBusy || !pullAtTop) return;
            if ((e.touches[0].clientY - pullStartY) > 120 && scroller().scrollTop <= 0) goPrev();
        }, { passive: true });

        // Desktop / trackpad equivalent, and a safety net on devices without the
        // rubber-band pull.
        var wheelUp = 0;
        window.addEventListener('wheel', function (e) {
            if (prevBusy) return;
            if (scroller().scrollTop <= 0 && e.deltaY < 0) {
                wheelUp += -e.deltaY;
                if (wheelUp > 240) goPrev();
            } else { wheelUp = 0; }
        }, { passive: true });
    }

    /* --- Wiring ---------------------------------------------------------- */

    function startReader() {
        observeImages();
        setupContinuousScroll();
    }

    // New panels that Tapas itself streams in on the current page.
    var mo = null;
    function syncMutationObserver() {
        if (isReaderPage() && !mo) {
            mo = new MutationObserver(function () {
                if (syncMutationObserver.queued) return;
                syncMutationObserver.queued = true;
                requestAnimationFrame(function () {
                    syncMutationObserver.queued = false;
                    observeImages(IS.article || document);
                });
            });
            mo.observe(root, { childList: true, subtree: true });
        } else if (!isReaderPage() && mo) {
            mo.disconnect(); mo = null;
        }
    }

    function onRouteChange() {
        var lastPath = location.pathname;
        function check() {
            if (location.pathname === lastPath) return;
            lastPath = location.pathname;
            // A real chapter change (our own history.replaceState during continuous
            // scroll also lands here, but IS state is already correct then).
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

    // Both run at document start so the page never paints inset and then jump.
    markReader();
    coverViewport();

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', boot, { once: true });
    } else {
        boot();
    }
})();
