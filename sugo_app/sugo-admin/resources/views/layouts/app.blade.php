<!DOCTYPE html>
<html lang="en" class="h-full">

<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>@yield('title', 'Review console') · SUGO Admin</title>

    {{--
        Tailwind via the Play CDN rather than a Vite build.

        The trade is deliberate: it removes `npm install` and `npm run build`
        from the setup, so the panel runs with nothing but `php artisan serve`.
        The cost is a CDN request at page load and slightly slower first paint.
        For an internal review console that a handful of staff open, that is
        the right side of the trade. Move it to the Vite pipeline already
        configured in this project if it ever faces real traffic.

        This CDN is Tailwind **v3**, so the views use v3 class names
        (`bg-gradient-to-b`, `border-white/[0.04]`). The editor may suggest v4
        spellings (`bg-linear-to-b`) because package.json lists v4 for the
        unused Vite pipeline; those do not exist in v3 and would render nothing.
    --}}
    <script src="https://cdn.tailwindcss.com"></script>
    <script>
        tailwind.config = {
            theme: {
                extend: {
                    colors: {
                        // The SUGO palette, taken from lib/core/constants/
                        // app_colors.dart so the console and the app read as
                        // one product (brought in line on 2026-09-29; it was
                        // still the retired #1877F2 blue and #FF7A00 orange).
                        //
                        // One rule carried over from the app: bright for
                        // marks, dark for words. `brand`, `accent` and `warn`
                        // are the *text* shades, because this console prints
                        // them as words and puts white words on them.
                        brand: {
                            DEFAULT: '#0663C4', // SUGO blue, text shade: 5.8:1
                            dark: '#054FA0',
                            light: '#087FEA', // SUGO blue, for fills only
                            soft: '#EAF5FF',
                            softer: '#F4F9FF',
                        },
                        navy: '#062B5C',
                        accent: {
                            DEFAULT: '#B45309', // orange as text: 5.0:1
                            light: '#F59E0B', // SUGO orange, for fills only
                            soft: '#FEF3DE'
                        },
                        ink: {
                            DEFAULT: '#10233F',
                            muted: '#5F6E84'
                        },
                        line: '#E3E8EF', // Hairline
                        canvas: '#F5F7FA', // Paper
                        ok: {
                            DEFAULT: '#157F4B',
                            soft: '#EAF7F0'
                        },
                        warn: {
                            DEFAULT: '#B45309',
                            soft: '#FEF3E0'
                        },
                        bad: {
                            DEFAULT: '#CE2C31',
                            soft: '#FDEBEC'
                        },
                    },
                    fontFamily: {
                        sans: ['Plus Jakarta Sans', 'Segoe UI', 'system-ui', 'sans-serif'],
                    },
                },
            },
        };
    </script>
    {{-- The S-road logo (2026-11-16), drawn by sugo_app/tool/make_logo.py:
         SVG where the browser takes it, the .ico for the rest. --}}
    <link rel="icon" type="image/svg+xml" href="{{ asset('images/sugo-logo.svg') }}">
    <link rel="icon" href="{{ asset('favicon.ico') }}" sizes="any">
    <link rel="apple-touch-icon" href="{{ asset('images/brand-emblem.png') }}">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap" rel="stylesheet">

    <style>
        [x-cloak] {
            display: none;
        }

        ::-webkit-scrollbar {
            width: 10px;
            height: 10px;
        }

        ::-webkit-scrollbar-thumb {
            background: #cbd5e1;
            border-radius: 999px;
        }

        ::-webkit-scrollbar-track {
            background: transparent;
        }
    </style>
    @stack('styles')
</head>

<body class="h-full bg-canvas font-sans text-ink antialiased">

    @php
        $admin = session('admin');

        /*
         * Navigation, grouped by what the admin is doing rather than listed flat.
         * "Overview" is watching the platform, "Review" is the queue that needs a
         * decision, "Accounts" is looking somebody up. Grouping is what lets the
         * sidebar grow a Jobs entry without turning into an undifferentiated list.
         */
        $sections = [
            'Overview' => [
                [
                    'route' => 'dashboard',
                    'params' => [],
                    'label' => 'Dashboard',
                    'icon' => 'dashboard',
                    'match' => fn() => request()->routeIs('dashboard'),
                ],
                [
                    'route' => 'jobs.index',
                    'params' => [],
                    'label' => 'Jobs',
                    'icon' => 'jobs',
                    'match' => fn() => request()->routeIs('jobs.*'),
                ],
            ],
            'Review' => [
                // No separate Credentials entry: credentials are reviewed on the
                // applicant's ID review screen, in the same decision.
        [
            'route' => 'verifications.index',
            'params' => [],
            'label' => 'ID review',
            'icon' => 'id',
            'match' => fn() => request()->routeIs('verifications.*'),
            'badge' => 'pending',
        ],
        [
            'route' => 'disputes.index',
            'params' => [],
            'label' => 'Disputes',
            'icon' => 'flag',
            'match' => fn() => request()->routeIs('disputes.*'),
            'badge' => 'disputes',
        ],
    ],
    'Accounts' => [
        [
            'route' => 'accounts.index',
            'params' => ['technician'],
            'label' => 'Technicians',
            'icon' => 'technician',
            'match' => fn() => request()->routeIs('accounts.*') && request()->route('role') === 'technician',
        ],
        [
            'route' => 'accounts.index',
            'params' => ['client'],
            'label' => 'Clients',
            'icon' => 'client',
            'match' => fn() => request()->routeIs('accounts.*') && request()->route('role') === 'client',
        ],
    ],
];
// One count per badged entry: ID reviews waiting, reports still open.
$badges = [
    'pending' => (int) ($pendingBadge ?? 0),
    'disputes' => (int) ($disputeBadge ?? 0),
        ];
    @endphp

    <div class="flex min-h-full">

        {{-- ------------------------------------------------------------ Sidebar --}}
        {{-- Navy since the 2026-11-17 renovation: the same brand gradient as the
             app's hero bands, so the console and the phone read as one product.
             The rings are drawn with borders and blur, no images. --}}
        <aside
            class="sticky top-0 hidden h-screen w-64 shrink-0 flex-col overflow-hidden bg-gradient-to-b from-navy to-[#0B3F84] text-white lg:flex">
            <div class="pointer-events-none absolute -right-20 -top-20 h-56 w-56 rounded-full border-[22px] border-white/[0.04]"></div>
            <div class="pointer-events-none absolute -bottom-24 -left-16 h-64 w-64 rounded-full bg-[#11C5E8]/10 blur-3xl"></div>

            <div class="relative flex h-16 items-center gap-3 border-b border-white/10 px-5">
                {{-- The app's logo, the same geometry as the phone icon, on a
                     white tile so its own colours survive the navy. --}}
                <span class="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-white shadow-lg shadow-black/20">
                    <img src="{{ asset('images/sugo-logo.svg') }}" alt="SUGO" class="h-8 w-8">
                </span>
                <div>
                    <div class="text-sm font-extrabold leading-none tracking-wide">SUGO</div>
                    <div class="mt-1 text-[11px] font-medium text-white/60">Admin console</div>
                </div>
            </div>

            <nav class="relative flex-1 overflow-y-auto px-3 py-5">
                @foreach ($sections as $heading => $items)
                    <div
                        class="px-3 pb-2 {{ $loop->first ? '' : 'pt-6' }} text-[10px] font-bold uppercase tracking-[0.16em] text-white/40">
                        {{ $heading }}</div>
                    <div class="space-y-1">
                        @foreach ($items as $item)
                            @php $active = ($item['match'])(); @endphp
                            <a href="{{ route($item['route'], $item['params']) }}"
                                class="group relative flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-semibold transition duration-200
                                  {{ $active ? 'bg-white/[0.12] text-white shadow-[inset_0_0_0_1px_rgba(255,255,255,0.08)]' : 'text-white/65 hover:bg-white/[0.07] hover:text-white' }}">
                                {{-- Active marker: a glowing cyan bar on the left
                                     edge, so the current page reads even in
                                     peripheral vision. --}}
                                @if ($active)
                                    <span
                                        class="absolute -left-3 bottom-2 top-2 w-1 rounded-r-full bg-gradient-to-b from-[#11C5E8] to-brand-light shadow-[0_0_12px_rgba(17,197,232,0.8)]"></span>
                                @endif
                                @include('partials.icon', [
                                    'name' => $item['icon'],
                                    'class' => 'h-[18px] w-[18px] shrink-0 transition duration-200 group-hover:scale-110 ' . ($active ? 'text-[#11C5E8]' : ''),
                                ])
                                <span class="flex-1">{{ $item['label'] }}</span>
                                @php $count = $badges[$item['badge'] ?? ''] ?? 0; @endphp
                                @if ($count > 0)
                                    <span
                                        class="rounded-full bg-accent-light px-2 py-0.5 text-[10px] font-extrabold text-navy shadow-sm">{{ $count }}</span>
                                @endif
                            </a>
                        @endforeach
                    </div>
                @endforeach
            </nav>

            <div class="relative border-t border-white/10 p-4">
                <div class="mb-3 flex items-center gap-3 rounded-xl bg-white/[0.07] p-2.5 ring-1 ring-white/10">
                    <div
                        class="flex h-9 w-9 items-center justify-center rounded-full bg-gradient-to-br from-[#11C5E8] to-brand-light text-xs font-extrabold text-white shadow-md">
                        {{ strtoupper(substr($admin['name'] ?? 'A', 0, 1)) }}
                    </div>
                    <div class="min-w-0">
                        <div class="truncate text-xs font-bold">{{ $admin['name'] ?? 'Administrator' }}</div>
                        <div class="truncate text-[11px] text-white/55">{{ $admin['email'] ?? '' }}</div>
                    </div>
                </div>
                <form method="POST" action="{{ route('logout') }}">
                    @csrf
                    <button type="submit" data-loading-text="Signing out…"
                        class="flex w-full items-center justify-center gap-2 rounded-xl border border-white/15 px-3 py-2 text-xs font-semibold text-white/75 transition hover:border-bad hover:bg-bad hover:text-white">
                        @include('partials.icon', ['name' => 'logout', 'class' => 'h-4 w-4'])
                        Sign out
                    </button>
                </form>
            </div>
        </aside>

        {{-- --------------------------------------------------------------- Main --}}
        <div class="flex min-w-0 flex-1 flex-col">

            {{-- Mobile navigation.
             The sidebar is desktop-only, and there used to be no alternative -
             below the lg breakpoint the console simply had no navigation. A
             scrollable strip keeps every page one tap away without any JS. --}}
            <div class="bg-gradient-to-r from-navy to-[#0B3F84] text-white lg:hidden">
                <div class="flex h-14 items-center justify-between px-4">
                    <div class="flex items-center gap-2">
                        <span class="flex h-8 w-8 items-center justify-center rounded-lg bg-white">
                            <img src="{{ asset('images/sugo-logo.svg') }}" alt="SUGO" class="h-6 w-6">
                        </span>
                        <span class="text-sm font-extrabold">SUGO Admin</span>
                    </div>
                    <form method="POST" action="{{ route('logout') }}">
                        @csrf
                        <button type="submit" class="rounded-lg p-2 text-white/75 transition hover:bg-white/10 hover:text-white"
                            title="Sign out">
                            @include('partials.icon', ['name' => 'logout', 'class' => 'h-5 w-5'])
                        </button>
                    </form>
                </div>
                <nav class="flex gap-1 overflow-x-auto px-3 pb-2.5">
                    @foreach ($sections as $items)
                        @foreach ($items as $item)
                            @php $active = ($item['match'])(); @endphp
                            <a href="{{ route($item['route'], $item['params']) }}"
                                class="flex shrink-0 items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-bold transition
                                  {{ $active ? 'bg-white text-navy shadow' : 'text-white/75 hover:bg-white/10 hover:text-white' }}">
                                @include('partials.icon', [
                                    'name' => $item['icon'],
                                    'class' => 'h-3.5 w-3.5',
                                ])
                                {{ $item['label'] }}
                                @php $count = $badges[$item['badge'] ?? ''] ?? 0; @endphp
                                @if ($count > 0)
                                    <span
                                        class="rounded-full bg-accent-light px-1.5 text-[10px] font-extrabold text-navy">{{ $count }}</span>
                                @endif
                            </a>
                        @endforeach
                    @endforeach
                </nav>
            </div>

            {{-- Sticky and frosted: the page title stays in view while a long
                 page scrolls under it. --}}
            <header
                class="sticky top-0 z-30 flex min-h-[4.5rem] flex-wrap items-center justify-between gap-3 border-b border-line/80 bg-white/75 px-6 py-3 backdrop-blur-xl">
                <div class="flex min-w-0 items-center gap-3">
                    <span class="hidden h-8 w-1 rounded-full bg-gradient-to-b from-[#11C5E8] to-brand-light sm:block"></span>
                    <div class="min-w-0">
                        <h1 class="truncate text-lg font-extrabold tracking-tight text-navy">@yield('title', 'Review console')</h1>
                        @hasSection('subtitle')
                            <p class="truncate text-xs text-ink-muted">@yield('subtitle')</p>
                        @endif
                    </div>
                </div>
                <div class="flex items-center gap-3">
                    @yield('actions')
                    <span
                        class="hidden items-center gap-1.5 rounded-lg border border-line bg-white px-3 py-1.5 text-[11px] font-semibold text-ink-muted shadow-sm sm:inline-flex">
                        @include('partials.icon', ['name' => 'clock', 'class' => 'h-3.5 w-3.5 text-brand'])
                        {{ now()->format('D, d M Y') }}
                    </span>
                </div>
            </header>

            <main class="flex-1 p-4 sm:p-6">
                @if (session('status'))
                    <div data-flash
                        class="sugo-slide-down mb-5 flex items-start gap-3 rounded-xl border border-ok/25 bg-ok-soft px-4 py-3 shadow-sm">
                        <svg class="mt-0.5 h-4 w-4 shrink-0 text-ok" fill="currentColor" viewBox="0 0 20 20">
                            <path fill-rule="evenodd"
                                d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.7-9.3a1 1 0 00-1.4-1.4L9 10.6 7.7 9.3a1 1 0 00-1.4 1.4l2 2a1 1 0 001.4 0l4-4z"
                                clip-rule="evenodd" />
                        </svg>
                        <p class="flex-1 text-sm font-semibold text-ink">{{ session('status') }}</p>
                        <button type="button" data-dismiss class="-m-1 rounded-md p-1 text-ink-muted transition hover:bg-white hover:text-ink"
                            aria-label="Dismiss">&times;</button>
                    </div>
                @endif

                @if (session('error'))
                    <div data-flash
                        class="sugo-slide-down mb-5 flex items-start gap-3 rounded-xl border border-bad/25 bg-bad-soft px-4 py-3 shadow-sm">
                        <svg class="mt-0.5 h-4 w-4 shrink-0 text-bad" fill="currentColor" viewBox="0 0 20 20">
                            <path fill-rule="evenodd"
                                d="M10 18a8 8 0 100-16 8 8 0 000 16zM9 5a1 1 0 012 0v5a1 1 0 11-2 0V5zm1 9a1.25 1.25 0 100-2.5A1.25 1.25 0 0010 14z"
                                clip-rule="evenodd" />
                        </svg>
                        <p class="flex-1 text-sm font-semibold text-ink">{{ session('error') }}</p>
                        <button type="button" data-dismiss class="-m-1 rounded-md p-1 text-ink-muted transition hover:bg-white hover:text-ink"
                            aria-label="Dismiss">&times;</button>
                    </div>
                @endif

                {{-- Direct children deal in top to bottom (partials/motion). --}}
                <div class="sugo-page">
                    @yield('content')
                </div>
            </main>
        </div>
    </div>

    @include('partials.loading')
    @include('partials.motion')
</body>

</html>
