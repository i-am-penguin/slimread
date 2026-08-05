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

    var TWEAKS_VERSION = '1.26 chapter-end fix';
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

    /* READ THIS BEFORE TUNING THE NEXT THREE.

       LOAD_MARGIN, AHEAD_PANELS and PRIME_COUNT describe a buffer that travels
       with the reader, loading a window of panels around wherever they are. That
       is what they are for. It is not what they do.

       They are all INERT while RESERVE is off, which is the default. An unloaded
       panel is a zero-height box, so before anything has loaded the whole chapter
       is collapsed into a few pixels - and every panel in it is therefore inside
       LOAD_MARGIN on the observer's very first pass, whatever LOAD_MARGIN says.
       Every panel is promoted at once, so there is no window left for AHEAD_PANELS
       to widen and nothing for PRIME_COUNT to get a head start on.

       This is not a theory. Measured across every release on a 130-panel chapter,
       all of 1.15 through 1.25 load 130 of 130 panels on arrival - identically -
       while LOAD_MARGIN goes 300, 800, 1600, 600 and PRIME_COUNT goes 6 to 12
       across those same versions. Tuning them has changed nothing since 1.15.

       So: changing these three does nothing unless you also set reserve=on. With
       reserve=on they become live for the first time and the numbers below start
       meaning what they say. */

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

    /* Whether panels reserve their space before loading - see reserveSpace().

       OFF by default, on the reader's evidence rather than mine. Reserving space
       makes the buffer above roll properly, which is the behaviour the loader was
       written for and holds far less artwork at once. But it also moves every
       panel's load - and the box resize that follows it, because the reserved size
       is a guess - out of the moment a chapter opens and into the scroll.

       That matters more than it sounds. scrollHeight is read on every scroll frame
       and every watchdog tick, and it is free while layout is clean and a full
       reflow while it is dirty: measured at 0.001ms against 0.105ms on a 227k-px,
       520-panel page, a hundredfold. Loading panels is what dirties layout. Loading
       them all on arrival means layout settles once and the page is cheap to scroll
       afterwards; loading them as you go means it is never settled while you are
       moving. On the device, the second one is reported as scrolling that gets
       sluggish and recovers the moment you stop, and that report is the only
       measurement of the thing that actually matters here.

       Turn it on with ?slimread=reserve=on. Worth revisiting if the reserved size
       can be made exact enough that a loading panel does not resize - at that point
       the buffer rolls without dirtying layout, and both properties are available
       at once. */
    var RESERVE = false;

    /* --- Runtime knobs ----------------------------------------------------
       Every number above is a guess about a device this file cannot be measured
       from. Rather than push a new guess and wait to hear how it felt, set them
       from the app's address bar and find out in seconds.

       Type any of these into the control bar's address field:

           tapas.io/?slimread=hud=on              turn the meter on (see startHUD)
           tapas.io/?slimread=stitch=2            2 chapters live instead of 4
           tapas.io/?slimread=stitch=2,ahead=6    several at once, comma separated
           tapas.io/?slimread=reserve=on          roll the buffer (see RESERVE)
           tapas.io/?slimread=reset               clear everything, back to defaults

       The knobs, their defaults, and what they cost:

           hud=on|off     off   The meter. Costs a 16ms timer while it is on, so
                                turn it off when you are done reading numbers.
           stitch=N       4     MAX_STITCHED. Chapters kept on one page before the
                                reader navigates instead. Lower = less artwork
                                live, at one page load per N chapters.
           reserve=on|off off   RESERVE. On, panels reserve space and load as you
                                reach them; off, the whole chapter loads at once.
                                Read the RESERVE comment before changing this - the
                                two are not simply better and worse.
           ahead=N        12    AHEAD_PANELS  }  all three are INERT while
           prime=N        12    PRIME_COUNT   }  reserve=off, which is the default.
           margin=N       600   LOAD_MARGIN   }  See the note on those three above.

       Two things that are easy to trip over:

       Setting knobs REPLACES the stored set, it does not merge into it. After
       `?slimread=reserve=on`, typing `?slimread=hud=on` turns the meter on AND
       puts reserve back to its default. To keep both, name both:
       `?slimread=hud=on,reserve=on`.

       They are stored in localStorage under KNOB_KEY, so they survive navigating
       between chapters, backgrounding the app, and relaunching it. They are not
       cleared by anything else - a knob set and forgotten stays set. `reset` (or
       `off`) is the only way back. Nothing here is announced on screen either,
       apart from the meter, so `?slimread=reset` is worth trying first if the
       reader is ever behaving unlike this file says it should.

       Everything below is inert unless something has been stored: with no knobs
       set it reads one localStorage key and stops. */

    var KNOB_KEY = 'slimread.knobs';
    var knobs = {};

    (function readKnobs() {
        // Whatever was set last time. Private browsing throws on localStorage
        // rather than returning null, hence the catch - no knobs is a fine state.
        var stored = '';
        try { stored = localStorage.getItem(KNOB_KEY) || ''; } catch (e) {}

        var m = location.search.match(/[?&]slimread=([^&]*)/);
        if (m) {
            var given = decodeURIComponent(m[1]);

            // The whole set is replaced, never merged - see the note above. Merging
            // would be friendlier to type but there would then be no way to unset a
            // single knob from the address bar, only to add more.
            //
            // `reset` and `off` both mean "clear": `off` because it is the word
            // that comes to mind first when the meter is on and you want it gone.
            stored = (given === 'reset' || given === 'off') ? '' : given;
            try {
                if (stored) localStorage.setItem(KNOB_KEY, stored);
                else localStorage.removeItem(KNOB_KEY);
            } catch (e) {}
        }
        if (!stored) return;      // the common case: one read, nothing else

        // `a=1,b=2` -> { a: '1', b: '2' }. Anything malformed is dropped silently:
        // this is typed on a phone keyboard, and a typo that half-applied would be
        // worse to diagnose than one that did nothing.
        stored.split(',').forEach(function (pair) {
            var kv = pair.split('=');
            if (kv.length === 2) knobs[kv[0].trim()] = kv[1].trim();
        });

        // Overwrite the defaults above. The `> 0` guards mean a knob that is absent,
        // zero, or not a number leaves its default alone - `+'abc'` is NaN and NaN
        // fails every comparison, so garbage falls through rather than disabling
        // the buffer outright.
        if (+knobs.ahead > 0) AHEAD_PANELS = +knobs.ahead;
        if (+knobs.prime > 0) PRIME_COUNT = +knobs.prime;
        if (+knobs.stitch > 0) MAX_STITCHED = +knobs.stitch;
        // Vertical only, matching LOAD_MARGIN's own shape - a horizontal margin
        // would do nothing here, the panels being full width.
        if (+knobs.margin > 0) LOAD_MARGIN = knobs.margin + '% 0px ' + knobs.margin + '% 0px';
        // Spelled out both ways rather than `!== 'off'`, so that a typo like
        // `reserve=yes` leaves the default rather than silently meaning "on".
        if (knobs.reserve === 'on') RESERVE = true;
        if (knobs.reserve === 'off') RESERVE = false;
    })();

    /* The meter, shown by ?slimread=hud=on. Bottom-left, so it does not sit under
       the top-left corner that opens the control bar.

       It reports how late a 16ms timer actually runs, which reads how blocked the
       main thread is. A frame counter would not do: iOS suspends
       requestAnimationFrame during momentum scrolling, so it reports dropped frames
       whether or not anything is wrong.

       Scroll for ten seconds or so and read it. Every figure is for the last second
       only - the window resets each tick, so it shows what is happening now rather
       than an average that hides the spikes.

           block 34ms worst / 12% late | panels 24/130 | page 67k | ch 2
                 |              |               |             |        |
                 |              |               |             |        chapters
                 |              |               |             |        stitched
                 |              |               |             page height, px/1000
                 |              |               panels holding artwork / panels
                 |              |               present. Reads N/N with reserve
                 |              |               off - that is expected, not a fault
                 |              share of ticks that ran more than 8ms late
                 worst single stall. Under ~10ms is fine. 30ms+ is a visible
                 hitch. 50ms+ and something is genuinely wrong.

       Worth knowing what it cannot see: this measures the MAIN THREAD only. If
       scrolling feels bad while these numbers stay low, the cost is in compositing
       - WebKit rasterising a very tall page full of large panels - and nothing in
       this file will fix it. That is a useful answer, not a failed measurement:
       it says stop tuning the page and reduce how much page there is (stitch=N). */
    function startHUD() {
        var el = document.createElement('div');
        el.className = 'slimread-hud';
        (document.body || root).appendChild(el);

        var last = performance.now(), worst = 0, late = 0, ticks = 0;

        // The probe. A timer asked to run every 16ms can only run late, never
        // early, and it runs late exactly when the main thread is busy with
        // something else - so lateness IS the measurement. Subtracting the 16ms it
        // was asked to wait leaves the part that is the page's fault.
        setInterval(function () {
            var now = performance.now();
            var behind = Math.max(0, now - last - 16);
            last = now;
            ticks++;
            // 8ms is half a frame at 60Hz and a whole one at 120Hz - the point where
            // being late has begun to cost something visible rather than just
            // showing timer jitter.
            if (behind > 8) late++;
            if (behind > worst) worst = behind;
        }, 16);

        setInterval(function () {
            // Counts panels holding real artwork. currentSrc is the image the
            // browser actually settled on, so it stays empty for a panel that was
            // asked to load and has not - which is the number worth seeing. The
            // placeholder is a data: URI, hence excluding those.
            //
            // This walks every image once a second. That is affordable precisely
            // because the meter is off unless asked for; it would not be something
            // to run by default.
            var live = 0, imgs = document.getElementsByTagName('img');
            for (var i = 0; i < imgs.length; i++) {
                if (imgs[i].currentSrc && imgs[i].currentSrc.indexOf('data:') !== 0) live++;
            }
            el.textContent =
                'block ' + worst.toFixed(0) + 'ms worst / ' +
                (ticks ? Math.round(late * 100 / ticks) : 0) + '% late | ' +
                'panels ' + live + '/' + imgs.length + ' | ' +
                'page ' + Math.round(document.documentElement.scrollHeight / 1000) + 'k | ' +
                // +1: blocks holds the chapters APPENDED to this page, so the one
                // the page was opened on is not among them.
                'ch ' + (IS.blocks.length + 1);
            worst = 0; late = 0; ticks = 0;      // per-second window
        }, 1000);
    }

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

    /* Give a panel its space before it loads.

       This is what makes the rolling buffer above actually roll. An unloaded panel
       is a zero-height box, so before anything has loaded the whole chapter is
       collapsed into a few pixels - and every panel in it therefore falls inside
       LOAD_MARGIN at once. The buffer degrades into "fetch all ~130 panels of this
       chapter immediately, at high priority, and hold them all decoded", which is
       the opposite of what it is for, and it is what makes scrolling heavy while an
       idle page feels fine. Measured on a 130-panel chapter: 130 promoted on
       arrival with no reserved height, 12 with it, the rest arriving as they are
       reached.

       The site's markup carries the dimensions sometimes but not always, so fall
       back to a neutral guess and drop it the moment the real panel lands. A wrong
       guess cannot move the page under your thumb: only panels you have not reached
       are unloaded, and content resizing BELOW the viewport does not shift what is
       in it. Against today's behaviour it is strictly less layout shift, not more -
       a zero-height box is a 100% wrong guess. */
    function reserveSpace(img) {
        if (!RESERVE) return;
        if (img.__slimreadSized) return;
        if (!lazyURL(img)) return;      // not a lazy panel - nothing to reserve
        img.__slimreadSized = true;

        var w = img.getAttribute('width') || img.getAttribute('data-width');
        var h = img.getAttribute('height') || img.getAttribute('data-height');
        if (w && h && +w > 0 && +h > 0) {
            img.style.aspectRatio = w + ' / ' + h;
            return;
        }

        // No dimensions to go on. Hold a plausible panel's worth of space until the
        // real one arrives - including if it fails, or the gap never closes.
        img.classList.add('slimread-unsized');
        function settled() { img.classList.remove('slimread-unsized'); }
        img.addEventListener('load', settled, { once: true });
        img.addEventListener('error', settled, { once: true });
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
            // Before the skip below: a panel already promoted or already observed
            // still needs its space reserved, or the collapse this prevents simply
            // happens to the panels that got in first.
            reserveSpace(img);
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
        lastError: false,   // last episode-list lookup failed - transient, never latched
        unresolved: false,  // walked the list and this chapter was not in it - also transient
        tailId: null,
        headId: null,
        article: null,
        blocks: [],        // { id, title, anchor } per appended chapter
        appending: false,
        misses: 0,          // consecutive appends that produced nothing definite
        nextAttemptAt: 0,   // backoff floor, so a broken endpoint is not hammered
        ended: false,
        active: false
    };

    // Only a stop against runaway recursion. The walk below starts at page 1 on
    // every page load, so the reader who runs out of it is the one deepest into a
    // long series - the last person who should be cut off. It is not a budget.
    var MAX_LIST_PAGES = 120;

    function seriesIdFromDom() {
        var el = document.querySelector('[data-series-id]');
        return el ? el.getAttribute('data-series-id') : null;
    }

    function apiEpisodes(page) {
        IS.lastError = false;
        return fetchWithTimeout('/series/' + IS.seriesId + '/episodes?page=' + page + '&sort=OLDEST',
            { credentials: 'include', headers: { 'x-requested-with': 'XMLHttpRequest' } }, 15000)
            .then(function (r) { return r.ok ? r.text() : null; })
            .then(function (text) {
                if (!text) { IS.lastError = true; return false; }   // server refused - try again later
                var ids = [], re = /\/episode\/(\d+)/g, m;
                while ((m = re.exec(text))) {
                    if (IS.order.indexOf(m[1]) < 0 && ids.indexOf(m[1]) < 0) ids.push(m[1]);
                }
                IS.order = IS.order.concat(ids);
                IS.hasMore = /"has_next"\s*:\s*true/.test(text);

                // Progress. A lookup that answers is the endpoint working, so the
                // backoff below must not keep growing across a walk that is simply
                // long, or a series deep enough to need several pages ends up
                // waiting seconds between attempts for no reason.
                IS.misses = 0;
                IS.nextAttemptAt = 0;

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
            .catch(function () {
                // A network blip, not an answer. Clearing hasMore here made a single
                // failure the last word forever: the lookup then gave up instantly,
                // the caller read that as "no next chapter" and latched IS.ended, and
                // the endless scroll was over for the rest of the page.
                IS.lastError = true;
                return false;
            });
    }

    function ensureIndexOf(id) {
        // Clear the flags for THIS attempt. They exist to stop the recursion below
        // from hammering a failing endpoint - not to remember across attempts,
        // which would leave a stale failure blocking every later retry.
        IS.lastError = false;
        IS.unresolved = false;

        var guard = 0;
        function step() {
            var i = IS.order.indexOf(id);
            if (i >= 0) return Promise.resolve(i);
            // Stop on an error too, but without recording anything permanent -
            // the append watchdog comes back around in under a second.
            if (IS.lastError || !IS.hasMore || guard++ > MAX_LIST_PAGES) {
                // Ran out of list without finding this chapter. That is "could not
                // find out", NOT "there is no next chapter" - the caller must not be
                // allowed to conclude the series has ended from it.
                IS.unresolved = true;
                return Promise.resolve(i);
            }
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

    /* fetch has no timeout of its own. A request that never settles - a stalled
       radio, a captive portal, a hung connection - leaves IS.appending stuck true,
       and since that flag blocks every future append, the reader stops dead at the
       end of a chapter with nothing to indicate why. */
    function fetchWithTimeout(url, options, ms) {
        options = options || {};
        if (typeof AbortController === 'function') {
            var ac = new AbortController();
            options.signal = ac.signal;
            var timer = setTimeout(function () { ac.abort(); }, ms);
            return fetch(url, options).then(
                function (r) { clearTimeout(timer); return r; },
                function (e) { clearTimeout(timer); throw e; }
            );
        }
        // No AbortController: race it instead. The request keeps running, but the
        // caller is released and can try again.
        return Promise.race([
            fetch(url, options),
            new Promise(function (_, reject) {
                setTimeout(function () { reject(new Error('timeout')); }, ms);
            })
        ]);
    }

    /* An attempt that produced nothing, without establishing that there is nothing
       to produce: a lookup that did not resolve, a fetch that came back empty.

       Never latch on this. "There is no next chapter" and "could not find out" look
       identical from here and only the first one is permanent; treating the second
       as the first is what ends the reader for the rest of the page. Back off so an
       endpoint that answers nothing at all is not hammered at watchdog speed, and
       say something once the retries have gone on long enough to stop looking like a
       blip.

       The backoff stays short deliberately. Retrying briskly is what gets a reader
       through a patchy connection - anything long enough to notice is worse than the
       hammering it avoids, and any answer at all clears it. */
    function appendMissed() {
        IS.appending = false;
        IS.misses++;
        IS.nextAttemptAt = Date.now() + Math.min(700 * IS.misses, 5000);

        // A list that was walked to its end without containing the chapter being
        // read is a list that is wrong - a partial page, a response that changed
        // shape. Drop it so the next attempt rebuilds it instead of re-deciding on
        // the same bad data.
        if (IS.unresolved && !IS.hasMore) {
            IS.order = [];
            IS.page = 0;
            IS.hasMore = true;
        }

        if (IS.misses === 5) toast('Still looking for the next chapter...');
    }

    function appendNextChapter() {
        if (!IS.active || IS.appending || IS.ended || !IS.article) return;
        // Serving a backoff from a run of failures - see appendMissed(). The
        // watchdog keeps calling every 700ms regardless; this is what stops that
        // becoming 700ms of retries against an endpoint that is not answering.
        if (Date.now() < IS.nextAttemptAt) return;
        IS.appending = true;
        IS.appendingSince = Date.now();

        nextIdAfter(IS.tailId).then(function (nid) {
            if (!nid) {
                // Only conclude the series has ended when the lookup actually
                // succeeded, placed this chapter in the list, and showed nothing
                // after it. Anything less is a failure to find out, and latching on
                // one of those is permanent - one blip would end the reader.
                if (IS.lastError || IS.unresolved) { appendMissed(); return; }
                IS.ended = true;
                toast('Reached the latest chapter');
                IS.appending = false;
                return;
            }

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
            return fetchWithTimeout('/episode/' + nid, { credentials: 'include' }, 20000)
                .then(function (r) { return r.ok ? r.text() : null; })
                .then(function (html) {
                    if (!html) { appendMissed(); return; }   // network blip, retry later

                    var data = extractPanels(html);
                    // Fetched fine but no panels: locked/paid chapter, or the end.
                    // Say so - silently stopping is indistinguishable from a bug.
                    if (!data.panels.length) {
                        IS.ended = true;
                        IS.appending = false;
                        toast('Next chapter is locked or unavailable');
                        return;
                    }

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
                    // A chapter landed, so whatever run of failures preceded it is
                    // over. Clearing both here means a reader who scrolls through a
                    // patchy stretch does not carry its backoff into the next
                    // chapter boundary, where the connection may be fine again.
                    IS.misses = 0;
                    IS.nextAttemptAt = 0;
                    observeImages(IS.article);   // hand the new panels to the observer

                    // Draw the start of the new chapter straight away, so arriving
                    // at it never lands on blank panels.
                    primeFrom(anchor, PRIME_COUNT);
                });
        }).catch(function () { appendMissed(); });
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

    /* Is the bottom of the page the real bottom?

       The page's height means nothing until the panels down there have resolved.
       Before that a chapter of ANY length is barely taller than the screen - the
       placeholders carry no dimensions, so they take up no space - and "you are at
       the end" is true of a chapter you have not started. That is the whole reason
       an arrival can turn into four chapters and a navigation.

       Asking the panels is the same question the old minimum-height check was
       reaching for, without its false negative. Height cannot tell a chapter that
       is short from a chapter that has not drawn yet, so a minimum dead-ends every
       chapter below it; the panels distinguish the two exactly, and a two-panel
       chapter satisfies this the moment those two have drawn.

       `complete` deliberately counts a panel that FAILED to load as resolved: one
       broken image at the end of a chapter must not become a dead end of its own. */
    function tailResolved() {
        var imgs = IS.article.querySelectorAll('.content__img');
        if (!imgs.length) imgs = IS.article.getElementsByTagName('img');

        var checked = 0;
        for (var i = imgs.length - 1; i >= 0 && checked < 3; i--) {
            var img = imgs[i];
            if (!img.__slimreadDone) return false;   // never even asked to load
            if (!img.complete) return false;         // asked, still in flight
            checked++;
        }
        return checked > 0;
    }

    // How long the end has to stay the end. Cheap belt-and-braces on top of
    // tailResolved(), covering the moment between a panel arriving and the reflow.
    var END_DWELL_MS = 1200;

    // A panel whose request never settles either way - a hung connection rather
    // than a failure - would otherwise hold the reader at the end of a chapter for
    // good. Only ever reached after you have scrolled, so it cannot fire on arrival.
    var STALL_ESCAPE_MS = 20000;

    var nearEndSince = 0;
    var stalledSince = 0;

    function maybeAppend() {
        // !IS.article is not redundant with !IS.active: tailResolved() below reads
        // IS.article directly, so this is what keeps it from throwing on a page
        // where the reader never found an article to work with.
        if (!IS.active || IS.ended || !IS.article) return;

        var vh = window.innerHeight;
        var height = document.documentElement.scrollHeight;
        var now = Date.now();

        if (height - (window.scrollY + vh) >= vh * 2.5) {
            nearEndSince = 0;
            stalledSince = 0;
            return;
        }

        // You have to have moved, so opening a chapter never advances it. The
        // exception is a chapter too short to scroll at all - a notice, an author's
        // note, a bonus page. No scroll is coming there, and waiting for one is a
        // dead end: the chapter simply stops and nothing can ever load.
        var moved = window.scrollY > 0;
        if (!moved && height > vh + 4) return;

        if (tailResolved()) {
            stalledSince = 0;
        } else if (!moved) {
            // Sitting at the top of a chapter whose panels have not drawn yet. This
            // is the ordinary state of a chapter you just opened, and the state the
            // reader used to mistake for the end of one. Wait.
            nearEndSince = 0;
            return;
        } else {
            if (!stalledSince) stalledSince = now;
            if (now - stalledSince < STALL_ESCAPE_MS) { nearEndSince = 0; return; }
        }

        if (!nearEndSince) { nearEndSince = now; return; }
        if (now - nearEndSince < END_DWELL_MS) return;

        appendNextChapter();
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

            // Release a wedged in-progress flag. The fetches have their own
            // timeouts now, but this flag blocks every future append, so it is
            // worth guaranteeing it can never be stuck regardless of the cause.
            if (IS.appending && Date.now() - IS.appendingSince > 30000) {
                IS.appending = false;
            }

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
            // Distinguish "there is no next one" from "could not find out".
            toast(IS.lastError ? 'Could not reach the next chapter' : 'This is the latest chapter');
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
        // Reserve the whole chapter's space before promoting anything, so the
        // observer is created against a page of a believable height rather than a
        // collapsed one. Otherwise its first pass finds every panel inside the band.
        for (var i = 0; i < imgs.length; i++) reserveSpace(imgs[i]);
        var n = Math.min(imgs.length, PRIME_COUNT);
        for (var j = 0; j < n; j++) promote(imgs[j]);
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
        // Before the reader starts, so the meter is already counting while the
        // first chapter loads - which is the busiest the main thread ever gets.
        if (knobs.hud === 'on') startHUD();
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
