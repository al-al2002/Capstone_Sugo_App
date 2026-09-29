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
    <link rel="icon" href="{{ asset('favicon.ico') }}">
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
        <aside class="sticky top-0 hidden h-screen w-64 shrink-0 flex-col border-r border-line bg-white lg:flex">
            <div class="flex h-16 items-center gap-3 border-b border-line px-5">
                <img src="{{ asset('images/brand-emblem.png') }}" alt=""
                    class="h-9 w-9 rounded-xl object-cover">
                <div>
                    <div class="text-sm font-extrabold leading-none text-navy">SUGO</div>
                    <div class="mt-0.5 text-[11px] font-medium text-ink-muted">Admin console</div>
                </div>
            </div>

            <nav class="flex-1 overflow-y-auto px-3 py-4">
                @foreach ($sections as $heading => $items)
                    <div
                        class="px-3 pb-2 {{ $loop->first ? '' : 'pt-5' }} text-[10px] font-bold uppercase tracking-[0.12em] text-ink-muted/80">
                        {{ $heading }}</div>
                    <div class="space-y-0.5">
                        @foreach ($items as $item)
                            @php $active = ($item['match'])(); @endphp
                            <a href="{{ route($item['route'], $item['params']) }}"
                                class="group relative flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-semibold transition
                                  {{ $active ? 'bg-brand-soft text-brand' : 'text-ink-muted hover:bg-canvas hover:text-ink' }}">
                                {{-- Active marker: a short bar on the left edge, so
                                 the current page reads even in peripheral vision. --}}
                                @if ($active)
                                    <span class="absolute -left-3 top-2 bottom-2 w-1 rounded-r-full bg-brand"></span>
                                @endif
                                @include('partials.icon', [
                                    'name' => $item['icon'],
                                    'class' => 'h-[18px] w-[18px] shrink-0',
                                ])
                                <span class="flex-1">{{ $item['label'] }}</span>
                                @php $count = $badges[$item['badge'] ?? ''] ?? 0; @endphp
                                @if ($count > 0)
                                    <span
                                        class="rounded-full bg-warn px-2 py-0.5 text-[10px] font-bold text-white">{{ $count }}</span>
                                @endif
                            </a>
                        @endforeach
                    </div>
                @endforeach
            </nav>

            <div class="border-t border-line p-4">
                <div class="mb-3 flex items-center gap-3 rounded-xl bg-canvas p-2.5">
                    <div
                        class="flex h-9 w-9 items-center justify-center rounded-full bg-navy text-xs font-bold text-white">
                        {{ strtoupper(substr($admin['name'] ?? 'A', 0, 1)) }}
                    </div>
                    <div class="min-w-0">
                        <div class="truncate text-xs font-bold">{{ $admin['name'] ?? 'Administrator' }}</div>
                        <div class="truncate text-[11px] text-ink-muted">{{ $admin['email'] ?? '' }}</div>
                    </div>
                </div>
                <form method="POST" action="{{ route('logout') }}">
                    @csrf
                    <button type="submit" data-loading-text="Signing out…"
                        class="flex w-full items-center justify-center gap-2 rounded-xl border border-line px-3 py-2 text-xs font-semibold text-ink-muted transition hover:border-bad hover:text-bad">
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
            <div class="border-b border-line bg-white lg:hidden">
                <div class="flex h-14 items-center justify-between px-4">
                    <div class="flex items-center gap-2">
                        <img src="{{ asset('images/brand-emblem.png') }}" alt=""
                            class="h-8 w-8 rounded-lg object-cover">
                        <span class="text-sm font-extrabold text-navy">SUGO Admin</span>
                    </div>
                    <form method="POST" action="{{ route('logout') }}">
                        @csrf
                        <button type="submit" class="rounded-lg p-2 text-ink-muted hover:text-bad" title="Sign out">
                            @include('partials.icon', ['name' => 'logout', 'class' => 'h-5 w-5'])
                        </button>
                    </form>
                </div>
                <nav class="flex gap-1 overflow-x-auto px-3 pb-2">
                    @foreach ($sections as $items)
                        @foreach ($items as $item)
                            @php $active = ($item['match'])(); @endphp
                            <a href="{{ route($item['route'], $item['params']) }}"
                                class="flex shrink-0 items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-bold
                                  {{ $active ? 'bg-brand text-white' : 'text-ink-muted hover:bg-canvas' }}">
                                @include('partials.icon', [
                                    'name' => $item['icon'],
                                    'class' => 'h-3.5 w-3.5',
                                ])
                                {{ $item['label'] }}
                                @php $count = $badges[$item['badge'] ?? ''] ?? 0; @endphp
                                @if ($count > 0)
                                    <span
                                        class="rounded-full bg-warn px-1.5 text-[10px] text-white">{{ $count }}</span>
                                @endif
                            </a>
                        @endforeach
                    @endforeach
                </nav>
            </div>

            <header
                class="flex min-h-18 flex-wrap items-center justify-between gap-3 border-b border-line bg-white/80 px-6 py-3 backdrop-blur">
                <div class="min-w-0">
                    <h1 class="truncate text-lg font-extrabold tracking-tight text-navy">@yield('title', 'Review console')</h1>
                    @hasSection('subtitle')
                        <p class="truncate text-xs text-ink-muted">@yield('subtitle')</p>
                    @endif
                </div>
                <div class="flex items-center gap-3">
                    @yield('actions')
                    <span
                        class="hidden rounded-lg bg-canvas px-3 py-1.5 text-[11px] font-semibold text-ink-muted sm:inline">
                        {{ now()->format('D, d M Y') }}
                    </span>
                </div>
            </header>

            <main class="flex-1 p-4 sm:p-6">
                @if (session('status'))
                    <div class="mb-5 flex items-start gap-3 rounded-xl border border-ok/25 bg-ok-soft px-4 py-3">
                        <svg class="mt-0.5 h-4 w-4 shrink-0 text-ok" fill="currentColor" viewBox="0 0 20 20">
                            <path fill-rule="evenodd"
                                d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.7-9.3a1 1 0 00-1.4-1.4L9 10.6 7.7 9.3a1 1 0 00-1.4 1.4l2 2a1 1 0 001.4 0l4-4z"
                                clip-rule="evenodd" />
                        </svg>
                        <p class="text-sm font-semibold text-ink">{{ session('status') }}</p>
                    </div>
                @endif

                @if (session('error'))
                    <div class="mb-5 flex items-start gap-3 rounded-xl border border-bad/25 bg-bad-soft px-4 py-3">
                        <svg class="mt-0.5 h-4 w-4 shrink-0 text-bad" fill="currentColor" viewBox="0 0 20 20">
                            <path fill-rule="evenodd"
                                d="M10 18a8 8 0 100-16 8 8 0 000 16zM9 5a1 1 0 012 0v5a1 1 0 11-2 0V5zm1 9a1.25 1.25 0 100-2.5A1.25 1.25 0 0010 14z"
                                clip-rule="evenodd" />
                        </svg>
                        <p class="text-sm font-semibold text-ink">{{ session('error') }}</p>
                    </div>
                @endif

                @yield('content')
            </main>
        </div>
    </div>

    @include('partials.loading')
</body>

</html>
