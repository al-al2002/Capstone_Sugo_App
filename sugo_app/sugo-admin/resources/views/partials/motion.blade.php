{{--
    The console's motion kit ("Dispatch, levelled up", 2026-11-17).

    Plain CSS and a few lines of plain JavaScript, for the same reason as
    partials/loading: the panel runs on `php artisan serve` with the Tailwind
    Play CDN and no build step, and these classes work without either.

    The same three rules as the app's motion kit (lib/core/widgets/
    sugo_motion.dart), so the console and the phone move one way:

      1. Once, never on a loop. Things rise in, bars grow, numbers count up,
         and then everything holds still. A dashboard is read; motion that
         keeps going is noise. (The loading spinner and progress bar are the
         exceptions, because they mean "still working".)
      2. Meaning, not decoration. A bar grows to its value; a number counts to
         its total; a section rises as it scrolls into view.
      3. Reduced motion means still. With the system setting on, everything
         renders in its final state at once.

    What is on offer:

      .sugo-page > *        direct children of the page rise in, staggered
      .sugo-rise            rise in once; delay with style="--d: 120ms"
      .sugo-grow-x          a bar grows from the left to its width; --d works
      .sugo-lift            a card that lifts slightly on hover
      .sugo-shine-once      one light sweep across a hero band on load
      .sugo-draw            an SVG path draws itself, end to start, once
                            (give the path pathLength="1")
      .sugo-pop             an SVG mark pops into place; --d delays it
      [data-reveal]         rises in when scrolled into view
      [data-count-to="1234"] counts up to that number when it appears;
                            data-decimals, data-prefix, data-suffix
      [data-flash]          a flash message; a [data-dismiss] inside closes it
--}}
<style>
    @keyframes sugo-rise {
        from { opacity: 0; transform: translateY(14px); }
        to { opacity: 1; transform: none; }
    }
    @keyframes sugo-grow-x {
        from { transform: scaleX(0); }
        to { transform: scaleX(1); }
    }
    @keyframes sugo-slide-down {
        from { opacity: 0; transform: translateY(-10px); }
        to { opacity: 1; transform: none; }
    }
    @keyframes sugo-shine {
        from { transform: translateX(-130%) skewX(-18deg); }
        to { transform: translateX(330%) skewX(-18deg); }
    }

    @keyframes sugo-draw {
        from { stroke-dashoffset: -1; }
        to { stroke-dashoffset: 0; }
    }
    @keyframes sugo-pop {
        0% { opacity: 0; transform: scale(.4); }
        70% { opacity: 1; transform: scale(1.08); }
        100% { opacity: 1; transform: scale(1); }
    }
    .sugo-draw {
        stroke-dasharray: 1;
        stroke-dashoffset: -1;
        animation: sugo-draw 1.6s cubic-bezier(.65, 0, .35, 1) .25s forwards;
    }
    .sugo-pop {
        transform-box: fill-box;
        transform-origin: center bottom;
        animation: sugo-pop .6s cubic-bezier(.2, .7, .2, 1) both;
        animation-delay: var(--d, 0ms);
    }

    .sugo-rise {
        animation: sugo-rise .6s cubic-bezier(.2, .7, .2, 1) both;
        animation-delay: var(--d, 0ms);
    }
    .sugo-grow-x {
        transform-origin: left center;
        animation: sugo-grow-x 1s cubic-bezier(.2, .7, .2, 1) both;
        animation-delay: var(--d, 0ms);
    }
    .sugo-slide-down { animation: sugo-slide-down .45s cubic-bezier(.2, .7, .2, 1) both; }

    /* Pages deal in top to bottom; past the eighth child, the rest arrive
       together rather than a second late. */
    .sugo-page > *:not([data-reveal]) { animation: sugo-rise .55s cubic-bezier(.2, .7, .2, 1) both; }
    .sugo-page > *:nth-child(2) { animation-delay: 60ms; }
    .sugo-page > *:nth-child(3) { animation-delay: 120ms; }
    .sugo-page > *:nth-child(4) { animation-delay: 180ms; }
    .sugo-page > *:nth-child(5) { animation-delay: 240ms; }
    .sugo-page > *:nth-child(6) { animation-delay: 300ms; }
    .sugo-page > *:nth-child(7) { animation-delay: 360ms; }
    .sugo-page > *:nth-child(n+8) { animation-delay: 420ms; }

    [data-reveal] {
        opacity: 0;
        transform: translateY(18px);
        transition: opacity .7s cubic-bezier(.2, .7, .2, 1), transform .7s cubic-bezier(.2, .7, .2, 1);
        transition-delay: var(--d, 0ms);
    }
    [data-reveal].is-in { opacity: 1; transform: none; }

    .sugo-lift { transition: transform .25s ease, box-shadow .25s ease, border-color .25s ease; }
    .sugo-lift:hover {
        transform: translateY(-3px);
        box-shadow: 0 16px 32px -16px rgba(6, 43, 92, .28);
        border-color: #CFE3FA;
    }

    .sugo-shine-once { position: relative; overflow: hidden; isolation: isolate; }
    .sugo-shine-once::after {
        content: '';
        position: absolute; top: 0; bottom: 0; left: 0; width: 35%;
        background: linear-gradient(90deg, transparent, rgba(255, 255, 255, .22), transparent);
        animation: sugo-shine 1.8s .45s ease-out both;
        pointer-events: none; z-index: 0;
    }

    @media (prefers-reduced-motion: reduce) {
        .sugo-rise, .sugo-grow-x, .sugo-slide-down, .sugo-draw, .sugo-pop,
        .sugo-page > *:not([data-reveal]), .sugo-shine-once::after { animation: none !important; }
        .sugo-shine-once::after { display: none; }
        .sugo-draw { stroke-dashoffset: 0; }
        [data-reveal] { opacity: 1; transform: none; transition: none; }
        .sugo-lift:hover { transform: none; }
    }
</style>

<script>
    (() => {
        const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

        // Writes v as the element's text, in its own format.
        const show = (el, v) => {
            const decimals = parseInt(el.dataset.decimals || '0', 10);
            const text = v.toLocaleString('en-US', {
                minimumFractionDigits: decimals,
                maximumFractionDigits: decimals,
            });
            el.textContent = (el.dataset.prefix || '') + text + (el.dataset.suffix || '');
        };

        // Counts up once, easing out. The server already printed the final
        // value, so without JavaScript the number is simply there.
        const countUp = (el) => {
            if (el.dataset.counted) return;
            el.dataset.counted = '1';
            const to = parseFloat(el.dataset.countTo);
            if (Number.isNaN(to)) return;
            if (reduce || to === 0) { show(el, to); return; }
            const duration = 1000;
            const start = performance.now();
            const step = (now) => {
                const p = Math.min(1, (now - start) / duration);
                show(el, to * (1 - Math.pow(1 - p, 4)));
                if (p < 1) requestAnimationFrame(step);
            };
            requestAnimationFrame(step);
        };

        const observer = !reduce && 'IntersectionObserver' in window
            ? new IntersectionObserver((entries) => {
                entries.forEach((entry) => {
                    if (!entry.isIntersecting) return;
                    entry.target.classList.add('is-in');
                    entry.target.querySelectorAll('[data-count-to]').forEach(countUp);
                    observer.unobserve(entry.target);
                });
            }, { threshold: 0.12 })
            : null;

        document.addEventListener('DOMContentLoaded', () => {
            document.querySelectorAll('[data-reveal]').forEach((el) => {
                if (observer) observer.observe(el); else el.classList.add('is-in');
            });
            // Numbers outside a revealed section count up straight away.
            document.querySelectorAll('[data-count-to]').forEach((el) => {
                if (!observer || !el.closest('[data-reveal]')) countUp(el);
            });
            document.querySelectorAll('[data-dismiss]').forEach((button) => {
                button.addEventListener('click', () => {
                    const box = button.closest('[data-flash]');
                    if (!box) return;
                    box.style.transition = 'opacity .25s ease, transform .25s ease';
                    box.style.opacity = '0';
                    box.style.transform = 'translateY(-6px)';
                    setTimeout(() => box.remove(), 260);
                });
            });
        });
    })();
</script>
