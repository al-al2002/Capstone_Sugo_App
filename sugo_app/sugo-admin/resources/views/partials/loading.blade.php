{{--
    Loading feedback for every page of the console, login included.

    Every page here is rendered on the server, and most of them wait on several
    Supabase requests before the first byte comes back. Without feedback, a
    click looks like nothing happened for a second or two - long enough that
    people click again, which on the review form means a second decision.

    Three pieces, all driven from here so no view has to opt in:

      1. A progress bar along the top of the window, from the moment a link or
         form is used until the next page replaces this one. It continues on
         the page that arrives (via sessionStorage), so signing in reads as
         one motion from the login button to the dashboard.
      2. The submit button that was pressed shows a spinner and says what is
         happening ("Signing in…", "Approving…"). Its label comes from
         `data-loading-text`; the rest of the form's buttons are held.
      3. A clicked link shows a spinner and is dimmed until the page changes.

    The pressed submit button is deliberately NOT disabled. A disabled button
    is left out of the submitted form data, and on the review form that button
    carries `decision=approve|reject` - disabling it would send a decision-less
    POST. A `data-busy` flag on the form blocks the second submit instead.

    Plain CSS and plain JavaScript: these classes are added at runtime, after
    the Tailwind Play CDN has already generated the page's styles.
--}}
<div id="sugo-progress" aria-hidden="true"><div></div></div>

<style>
    #sugo-progress {
        position: fixed; top: 0; left: 0; right: 0; z-index: 100;
        height: 3px; pointer-events: none; opacity: 0;
    }
    #sugo-progress > div {
        height: 100%; width: 0;
        background: linear-gradient(90deg, #11C5E8, #087FEA);
        box-shadow: 0 0 10px rgba(8, 127, 234, .45);
        border-radius: 0 3px 3px 0;
    }
    /* Fast at first, then slower and slower: it keeps moving for as long as
       the server takes, but never claims to have finished. */
    #sugo-progress.is-active { opacity: 1; }
    #sugo-progress.is-active > div { width: 88%; transition: width 9s cubic-bezier(.08, .8, .2, 1); }
    /* On the page that arrives: pick up where the last page left off... */
    #sugo-progress.is-arriving { opacity: 1; }
    #sugo-progress.is-arriving > div { width: 88%; transition: none; }
    /* ...then run to the end and fade out. */
    #sugo-progress.is-done { opacity: 0; transition: opacity .35s ease .2s; }
    #sugo-progress.is-done > div { width: 100%; transition: width .25s ease-out; }

    .sugo-spinner {
        display: inline-block; flex-shrink: 0;
        width: 1em; height: 1em;
        border: 2px solid currentColor; border-right-color: transparent;
        border-radius: 9999px;
        animation: sugo-spin .65s linear infinite;
    }
    @keyframes sugo-spin { to { transform: rotate(360deg); } }

    .sugo-busy { display: inline-flex; align-items: center; justify-content: center; gap: .5em; }

    button[aria-busy="true"] { cursor: progress; pointer-events: none; }
    button.is-held { opacity: .45; cursor: not-allowed; }
    a.is-loading { cursor: progress; pointer-events: none; opacity: .75; }
    a.is-loading > .sugo-spinner { margin-left: .4em; }
    a.is-loading.is-flex > .sugo-spinner { margin-left: 0; }

    @media (prefers-reduced-motion: reduce) {
        /* The spinner stays - it is the information - but turns slowly. */
        .sugo-spinner { animation-duration: 1.6s; }
        #sugo-progress > div { transition: none !important; }
    }
</style>

<script>
    (function () {
        var bar = document.getElementById('sugo-progress');
        var KEY = 'sugo-admin:navigating';

        // sessionStorage can be unavailable (private windows, blocked site
        // data). Every use is wrapped: the worst case is simply no bar on the
        // page that arrives, never a broken page.
        function remember() {
            try { sessionStorage.setItem(KEY, '1'); } catch (e) {}
        }

        function arrivedFromClick() {
            try {
                var was = sessionStorage.getItem(KEY) === '1';
                sessionStorage.removeItem(KEY);
                return was;
            } catch (e) {
                return false;
            }
        }

        function startProgress() {
            bar.classList.remove('is-arriving', 'is-done');
            void bar.offsetWidth; // restart the transition from zero
            bar.classList.add('is-active');
            remember();
        }

        function finishProgress() {
            bar.classList.remove('is-active');
            bar.classList.add('is-arriving');
            void bar.offsetWidth;
            bar.classList.add('is-done');
        }

        function spinner() {
            var s = document.createElement('span');
            s.className = 'sugo-spinner';
            s.setAttribute('aria-hidden', 'true');
            return s;
        }

        function busyButton(button) {
            if (!button || button.getAttribute('aria-busy') === 'true') return;

            // Keep the width, so the button does not jump when its label changes.
            button.style.minWidth = button.offsetWidth + 'px';
            button.dataset.idleHtml = button.innerHTML;

            var hasText = button.textContent.trim() !== '';
            var label = button.dataset.loadingText || (hasText ? 'Please wait…' : '');

            var wrap = document.createElement('span');
            wrap.className = 'sugo-busy';
            wrap.appendChild(spinner());
            if (label) {
                var text = document.createElement('span');
                text.textContent = label;
                wrap.appendChild(text);
            }

            button.innerHTML = '';
            button.appendChild(wrap);
            button.setAttribute('aria-busy', 'true');
        }

        function busyLink(link) {
            link.classList.add('is-loading');
            link.setAttribute('aria-busy', 'true');

            // Row-style links (display: block) get the dimming and the top bar
            // only - a spinner there would wrap onto a line of its own.
            var display = window.getComputedStyle(link).display;
            if (display === 'block') return;
            if (display.indexOf('flex') !== -1) link.classList.add('is-flex');
            link.appendChild(spinner());
        }

        // ---- Forms: login, sign out, approve / reject, search -------------
        document.addEventListener('submit', function (event) {
            var form = event.target;

            // Something else stopped this submit (e.g. a cancelled confirm()).
            if (event.defaultPrevented || form.hasAttribute('data-no-loading')) return;

            // The double-submit guard.
            if (form.dataset.busy === '1') {
                event.preventDefault();
                return;
            }
            form.dataset.busy = '1';

            var buttons = form.querySelectorAll('button[type="submit"], button:not([type])');
            var pressed = event.submitter || buttons[0] || null;

            busyButton(pressed);
            buttons.forEach(function (b) {
                // Only the OTHER buttons are disabled - see the note at the top.
                if (b !== pressed) {
                    b.disabled = true;
                    b.classList.add('is-held');
                }
            });

            startProgress();
        });

        // ---- Links: navigation, tabs, "View", "Review", filters -----------
        document.addEventListener('click', function (event) {
            // Left clicks only. Ctrl/Cmd/Shift/middle-click open a new tab
            // or window, and this page is not going anywhere.
            if (event.defaultPrevented || event.button !== 0 ||
                event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;

            var link = event.target.closest ? event.target.closest('a[href]') : null;
            if (!link || link.hasAttribute('download') || link.hasAttribute('data-no-loading')) return;
            if (link.target && link.target !== '_self') return; // e.g. "Open full size"

            var href = link.getAttribute('href');
            if (!href || href.charAt(0) === '#') return;

            var url = new URL(link.href, window.location.href);
            if (url.origin !== window.location.origin) return;
            if (url.protocol !== 'http:' && url.protocol !== 'https:') return;

            // Same page, different anchor: the browser scrolls, nothing loads.
            if (url.pathname === window.location.pathname &&
                url.search === window.location.search && url.hash !== '') return;

            busyLink(link);
            startProgress();
        });

        // ---- Coming back with the Back button -----------------------------
        // Browsers restore the previous page from memory (the back/forward
        // cache) exactly as it was left - spinners and all. Put it back.
        window.addEventListener('pageshow', function (event) {
            if (!event.persisted) return;

            bar.classList.remove('is-active', 'is-arriving', 'is-done');

            document.querySelectorAll('button[data-idle-html]').forEach(function (b) {
                b.innerHTML = b.dataset.idleHtml;
                delete b.dataset.idleHtml;
                b.removeAttribute('aria-busy');
                b.style.minWidth = '';
            });
            document.querySelectorAll('button.is-held').forEach(function (b) {
                b.disabled = false;
                b.classList.remove('is-held');
            });
            document.querySelectorAll('form[data-busy]').forEach(function (f) {
                delete f.dataset.busy;
            });
            document.querySelectorAll('a.is-loading').forEach(function (a) {
                a.classList.remove('is-loading', 'is-flex');
                a.removeAttribute('aria-busy');
                var s = a.querySelector(':scope > .sugo-spinner');
                if (s) s.remove();
            });

            try { sessionStorage.removeItem(KEY); } catch (e) {}
        });

        if (arrivedFromClick()) finishProgress();
    })();
</script>
