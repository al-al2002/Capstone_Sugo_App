@extends('layouts.app')

@section('title', 'Dashboard')


@push('styles')
    <style>
        /* The lines draw in left to right, then each day's dots fade in as the
           reveal passes them. `backwards` fill: the clip applies only while
           animating, so it never trims the stroke once the chart has settled. */
        .sugo-chart-reveal { animation: sugo-chart-reveal 1.1s cubic-bezier(.2, .7, .2, 1) backwards; }
        @keyframes sugo-chart-reveal {
            from { clip-path: inset(0 100% 0 0); }
            to { clip-path: inset(0 0 0 0); }
        }
        .sugo-chart-dot { animation: sugo-chart-dot .35s ease-out both; }
        @keyframes sugo-chart-dot {
            from { opacity: 0; }
            to { opacity: 1; }
        }
        @media (prefers-reduced-motion: reduce) {
            .sugo-chart-reveal, .sugo-chart-dot { animation: none; }
        }
    </style>
@endpush

@section('content')

    @php
        $pending = (int) ($stats['pending_verifications'] ?? 0);

        $users = $analytics['users'] ?? [];
        $jobs = $analytics['jobs'] ?? [];
        $ratings = $analytics['ratings'] ?? [];
        $comm = $analytics['community'] ?? [];
        $daily = $analytics['daily'] ?? [];
        $devices = $analytics['devices'] ?? [];
        $top = $analytics['top_technicians'] ?? [];
        $topClients = $analytics['top_clients'] ?? [];

        $num = fn($v) => number_format((int) ($v ?? 0));

        // Headline figures, ordered by what an admin asks first: is work flowing,
        // is it being finished, is it any good, and who is using it.
        $kpis = [
            [
                'label' => 'Jobs posted',
                'value' => $num($jobs['total'] ?? 0),
                'hint' => '+' . $num($jobs['last_7d'] ?? 0) . ' in the last 7 days',
                'icon' => 'jobs',
                'tone' => 'brand',
            ],
            [
                'label' => 'Completion rate',
                'value' =>
                    (($jobs['completion_rate'] ?? null) !== null
                        ? rtrim(rtrim(number_format((float) $jobs['completion_rate'], 1), '0'), '.')
                        : '0') . '%',
                'hint' => 'of jobs that reached an end state',
                'icon' => 'check',
                'tone' => 'ok',
            ],
            [
                'label' => 'Technician rating',
                'value' =>
                    ($ratings['technician_avg'] ?? null) !== null
                        ? number_format((float) $ratings['technician_avg'], 2)
                        : '—',
                'hint' => $num($ratings['technician_count'] ?? 0) . ' client reviews',
                'icon' => 'star',
                'tone' => 'accent',
            ],
            [
                'label' => 'People on SUGO',
                'value' => $num(($users['clients'] ?? 0) + ($users['technicians'] ?? 0)),
                'hint' =>
                    $num($users['clients'] ?? 0) . ' clients · ' . $num($users['technicians'] ?? 0) . ' technicians',
                'icon' => 'client',
                'tone' => 'navy',
            ],
        ];

        $tones = [
            'brand' => ['bg-brand-soft', 'text-brand'],
            'ok' => ['bg-ok-soft', 'text-ok'],
            'accent' => ['bg-accent-soft', 'text-accent'],
            'warn' => ['bg-warn-soft', 'text-warn'],
            'navy' => ['bg-navy/10', 'text-navy'],
            'ink' => ['bg-canvas', 'text-ink-muted'],
        ];

        // Status breakdown, in lifecycle order, for the stacked bar. Segments
        // are fills, so they use the bright `-light` shades where a colour has
        // one: `warn` and `accent` are the same dark amber as text, and would
        // merge into one segment.
        $statusOrder = [
            'pending' => ['Posted', 'bg-warn'],
            'matched' => ['Matched', 'bg-accent-light'],
            'confirmed' => ['Accepted', 'bg-brand-light'],
            'in_progress' => ['In progress', 'bg-brand'],
            'completed' => ['Completed', 'bg-ok'],
            'cancelled' => ['Cancelled', 'bg-ink-muted/40'],
        ];
        $statusTotal = max(1, array_sum(array_map(fn($k) => (int) ($jobs[$k] ?? 0), array_keys($statusOrder))));

        // The 14-day trend. Every coordinate is worked out in
        // App\Support\LineChart (unit-tested); this view only places them.
        $chart = new \App\Support\LineChart([
            'posted' => array_map(fn($d) => (int) $d['posted'], $daily),
            'completed' => array_map(fn($d) => (int) $d['completed'], $daily),
        ]);
        $series = [
            'posted' => ['Posted', 'bg-brand-light', '#087FEA'],
            'completed' => ['Completed', 'bg-ok', '#157F4B'],
        ];
        $periodPosted = array_sum(array_map(fn($d) => (int) $d['posted'], $daily));
        $periodDone = array_sum(array_map(fn($d) => (int) $d['completed'], $daily));

        $deviceMax = max(1, ...array_map(fn($d) => (int) $d['jobs'], $devices ?: [['jobs' => 0]]));
    @endphp

    @if ($pending > 0)
        <div
            class="mb-6 flex flex-wrap items-center justify-between gap-4 rounded-2xl border border-warn/25 bg-warn-soft px-5 py-4">
            <div class="flex items-center gap-3">
                <div class="flex h-10 w-10 items-center justify-center rounded-xl bg-warn text-white">
                    @include('partials.icon', ['name' => 'id', 'class' => 'h-5 w-5'])
                </div>
                <div>
                    <p class="text-sm font-extrabold text-ink">
                        {{ $pending }} {{ Str::plural('person', $pending) }} waiting to be verified
                    </p>
                    <p class="text-xs text-ink-muted">Nobody can book or accept work until their ID is reviewed.</p>
                </div>
            </div>
            <a href="{{ route('verifications.index') }}"
                class="rounded-xl bg-warn px-4 py-2 text-xs font-bold text-white transition hover:opacity-90">
                Open the queue
            </a>
        </div>
    @endif

    {{-- ------------------------------------------------------------ KPIs --}}
    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        @foreach ($kpis as $kpi)
            @php [$bg, $fg] = $tones[$kpi['tone']]; @endphp
            <div class="rounded-2xl border border-line bg-white p-5 shadow-sm transition hover:shadow-md">
                <div class="flex items-start justify-between">
                    <div>
                        <div class="text-[11px] font-bold uppercase tracking-wider text-ink-muted">{{ $kpi['label'] }}</div>
                        <div class="mt-2 text-3xl font-extrabold tabular-nums tracking-tight text-navy">{{ $kpi['value'] }}
                        </div>
                    </div>
                    <div
                        class="flex h-10 w-10 items-center justify-center rounded-xl {{ $bg }} {{ $fg }}">
                        @include('partials.icon', ['name' => $kpi['icon'], 'class' => 'h-5 w-5'])
                    </div>
                </div>
                <div class="mt-2 text-[11px] text-ink-muted">{{ $kpi['hint'] }}</div>
            </div>
        @endforeach
    </div>

    {{-- ------------------------------------------------ Activity + status --}}
    <div class="mt-6 grid gap-6 xl:grid-cols-[1.6fr_1fr]">

        <section class="rounded-2xl border border-line bg-white p-5 shadow-sm">
            <header class="mb-5 flex flex-wrap items-end justify-between gap-3">
                <div>
                    <h2 class="text-sm font-extrabold text-navy">Last 14 days</h2>
                    <p class="text-[11px] text-ink-muted">
                        {{ $periodPosted }} posted · {{ $periodDone }} completed
                    </p>
                </div>
                <div class="flex items-center gap-4 text-[11px] font-semibold text-ink-muted">
                    @foreach ($series as [$label, $bg])
                        <span class="flex items-center gap-1.5">
                            <span class="relative h-0.5 w-5 rounded-full {{ $bg }}">
                                <span class="absolute left-1/2 top-1/2 h-2 w-2 -translate-x-1/2 -translate-y-1/2 rounded-full border-2 border-white {{ $bg }}"></span>
                            </span>
                            {{ $label }}
                        </span>
                    @endforeach
                </div>
            </header>

            @if ($daily === [])
                <p class="py-16 text-center text-xs text-ink-muted">Analytics are unavailable right now.</p>
            @else
                @php $n = $chart->count(); $half = 50 / max(1, $n - 1); @endphp
                <div class="flex gap-3">
                    {{-- Y axis. HTML rather than SVG text, which would stretch with the plot. --}}
                    <div class="relative h-56 w-6 shrink-0" aria-hidden="true">
                        @foreach ($chart->ticks() as $tick)
                            <span class="absolute right-0 -translate-y-1/2 text-[10px] font-semibold tabular-nums text-ink-muted"
                                style="top: {{ $chart->yPercent($tick) }}%">{{ (int) $tick }}</span>
                        @endforeach
                    </div>

                    <div class="min-w-0 flex-1">
                        <div class="relative h-56">
                            {{-- Gridlines, shaded areas and the two lines. Stretched to the
                                 card's width; strokes stay crisp via non-scaling-stroke. --}}
                            <svg class="sugo-chart-reveal absolute inset-0 h-full w-full overflow-visible"
                                viewBox="0 0 {{ \App\Support\LineChart::WIDTH }} {{ \App\Support\LineChart::HEIGHT }}"
                                preserveAspectRatio="none" aria-hidden="true">
                                <defs>
                                    @foreach ($series as $key => [$label, $bg, $hex])
                                        <linearGradient id="fill-{{ $key }}" x1="0" y1="0" x2="0" y2="1">
                                            <stop offset="0" stop-color="{{ $hex }}" stop-opacity="{{ $key === 'posted' ? '.20' : '.14' }}" />
                                            <stop offset="1" stop-color="{{ $hex }}" stop-opacity="0" />
                                        </linearGradient>
                                    @endforeach
                                </defs>
                                @foreach ($chart->ticks() as $tick)
                                    @php $gy = round($chart->yPercent($tick) / 100 * \App\Support\LineChart::HEIGHT, 2); @endphp
                                    <line x1="0" x2="{{ \App\Support\LineChart::WIDTH }}" y1="{{ $gy }}" y2="{{ $gy }}"
                                        stroke="{{ $tick == 0 ? '#CBD5E1' : '#E3E8EF' }}" stroke-width="1"
                                        vector-effect="non-scaling-stroke" />
                                @endforeach
                                @foreach ($series as $key => [$label, $bg, $hex])
                                    <path d="{{ $chart->area($key) }}" fill="url(#fill-{{ $key }})" />
                                @endforeach
                                @foreach ($series as $key => [$label, $bg, $hex])
                                    <path d="{{ $chart->line($key) }}" fill="none" stroke="{{ $hex }}" stroke-width="2.5"
                                        stroke-linecap="round" stroke-linejoin="round" vector-effect="non-scaling-stroke" />
                                @endforeach
                            </svg>

                            {{-- One hover/focus column per day: guide line, the day's two
                                 dots, and a tooltip. Plain CSS (group-hover), no script. --}}
                            @foreach ($daily as $i => $day)
                                @php
                                    $x = $chart->xPercent($i);
                                    $date = \Carbon\Carbon::parse($day['day']);
                                    // Tooltip on the side with more room, so it never
                                    // covers the dots of the day it describes.
                                    $side = $i < $n / 2 ? 'left-1/2 ml-3' : 'right-1/2 mr-3';
                                @endphp
                                <div class="group absolute inset-y-0 outline-none" tabindex="0"
                                    style="left: {{ $x - $half }}%; width: {{ 2 * $half }}%"
                                    aria-label="{{ $date->format('l, d M') }}: {{ $day['posted'] }} posted, {{ $day['completed'] }} completed">
                                    <span class="absolute inset-y-0 left-1/2 w-px -translate-x-1/2 bg-navy/20 opacity-0 transition group-hover:opacity-100 group-focus:opacity-100"></span>

                                    @foreach ($series as $key => [$label, $bg, $hex])
                                        <span class="sugo-chart-dot absolute left-1/2 h-2.5 w-2.5 -translate-x-1/2 -translate-y-1/2 rounded-full border-2 border-white shadow-sm transition group-hover:scale-150 group-focus:scale-150 {{ $bg }}"
                                            style="top: {{ $chart->yPercent((int) $day[$key]) }}%; animation-delay: {{ (int) round(250 + $x * 8) }}ms"></span>
                                    @endforeach

                                    <div class="pointer-events-none absolute top-0 z-10 w-40 rounded-xl border border-line bg-white p-3 text-[11px] opacity-0 shadow-lg transition group-hover:opacity-100 group-focus:opacity-100 {{ $side }}">
                                        <div class="mb-2 font-bold text-navy">
                                            {{ $loop->last ? 'Today' : $date->format('D, d M') }}
                                        </div>
                                        @foreach ($series as $key => [$label, $bg, $hex])
                                            <div class="flex items-center justify-between {{ $loop->first ? 'mb-1' : '' }}">
                                                <span class="flex items-center gap-1.5 text-ink-muted">
                                                    <span class="h-2 w-2 rounded-full {{ $bg }}"></span>{{ $label }}
                                                </span>
                                                <span class="font-extrabold tabular-nums text-ink">{{ (int) $day[$key] }}</span>
                                            </div>
                                        @endforeach
                                    </div>
                                </div>
                            @endforeach
                        </div>

                        {{-- X axis: every other day counted back from today, so the
                             newest day is always labelled and no two labels touch. --}}
                        <div class="relative mt-2 h-4" aria-hidden="true">
                            @foreach ($daily as $i => $day)
                                @if (($n - 1 - $i) % 2 === 0)
                                    <span class="absolute -translate-x-1/2 whitespace-nowrap text-[10px] font-semibold {{ $loop->last ? 'text-brand' : 'text-ink-muted' }}"
                                        style="left: {{ $chart->xPercent($i) }}%">
                                        {{ $loop->last ? 'Today' : \Carbon\Carbon::parse($day['day'])->format('M j') }}
                                    </span>
                                @endif
                            @endforeach
                        </div>
                    </div>
                </div>

                {{-- The same figures for screen readers, which cannot read a drawing. --}}
                <table class="sr-only">
                    <caption>Jobs posted and completed per day, last 14 days</caption>
                    <thead><tr><th>Day</th><th>Posted</th><th>Completed</th></tr></thead>
                    <tbody>
                        @foreach ($daily as $day)
                            <tr>
                                <td>{{ \Carbon\Carbon::parse($day['day'])->format('d M') }}</td>
                                <td>{{ $day['posted'] }}</td>
                                <td>{{ $day['completed'] }}</td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            @endif
        </section>

        <section class="rounded-2xl border border-line bg-white p-5 shadow-sm">
            <header class="mb-4 flex items-center justify-between">
                <div>
                    <h2 class="text-sm font-extrabold text-navy">Where jobs stand</h2>
                    <p class="text-[11px] text-ink-muted">{{ $num($jobs['total'] ?? 0) }} jobs in total</p>
                </div>
                <a href="{{ route('jobs.index') }}" class="text-xs font-bold text-brand hover:underline">Open jobs</a>
            </header>

            {{-- One stacked bar: the whole pipeline at a glance. --}}
            <div class="mb-5 flex h-3 overflow-hidden rounded-full bg-canvas">
                @foreach ($statusOrder as $key => [$label, $color])
                    @php $n = (int) ($jobs[$key] ?? 0); @endphp
                    @if ($n > 0)
                        <div class="{{ $color }}" style="width: {{ ($n / $statusTotal) * 100 }}%"
                            title="{{ $label }}: {{ $n }}"></div>
                    @endif
                @endforeach
            </div>

            <ul class="space-y-2.5">
                @foreach ($statusOrder as $key => [$label, $color])
                    @php $n = (int) ($jobs[$key] ?? 0); @endphp
                    <li class="flex items-center gap-3 text-xs">
                        <span class="h-2.5 w-2.5 shrink-0 rounded-full {{ $color }}"></span>
                        <span class="flex-1 font-semibold text-ink">{{ $label }}</span>
                        <span class="tabular-nums font-bold text-navy">{{ $n }}</span>
                        <span
                            class="w-10 text-right tabular-nums text-ink-muted">{{ round(($n / $statusTotal) * 100) }}%</span>
                    </li>
                @endforeach
            </ul>
        </section>
    </div>

    {{-- --------------------------------------------- Both sides of the market --}}
    {{-- Technicians and clients side by side: the two leaderboards answer the
         same question - who is SUGO working for? - from each end of a job. --}}
    <div class="mt-6 grid gap-6 lg:grid-cols-2">

        <section class="rounded-2xl border border-line bg-white p-5 shadow-sm">
            <header class="mb-3 flex items-start justify-between gap-3">
                <div>
                    <h2 class="flex items-center gap-2 text-sm font-extrabold text-navy">
                        @include('partials.icon', ['name' => 'technician', 'class' => 'h-4 w-4 text-brand'])
                        Top technicians
                    </h2>
                    <p class="text-[11px] text-ink-muted">By completed jobs, then rating from clients</p>
                </div>
                <a href="{{ route('accounts.index', 'technician') }}" class="text-xs font-bold text-brand hover:underline">All</a>
            </header>
            @forelse ($top as $i => $t)
                <div class="flex items-center gap-3 border-b border-line py-2.5 last:border-0">
                    <span class="flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-[11px] font-extrabold
                                 {{ $i === 0 ? 'bg-accent text-white' : 'bg-canvas text-ink-muted' }}">{{ $i + 1 }}</span>
                    <div class="min-w-0 flex-1">
                        <div class="truncate text-sm font-bold">{{ $t['name'] ?: 'Unnamed' }}</div>
                        <div class="truncate text-[11px] text-ink-muted">{{ $t['jobs'] }} jobs · {{ $t['reviews'] }} reviews</div>
                    </div>
                    <span class="flex items-center gap-1 text-xs font-bold text-accent" title="Average rating from clients">
                        @include('partials.icon', ['name' => 'star', 'class' => 'h-3.5 w-3.5'])
                        {{ $t['rating'] !== null ? number_format((float) $t['rating'], 2) : '—' }}
                    </span>
                </div>
            @empty
                <p class="py-6 text-center text-xs text-ink-muted">No verified technicians yet.</p>
            @endforelse
        </section>

        <section class="rounded-2xl border border-line bg-white p-5 shadow-sm">
            <header class="mb-3 flex items-start justify-between gap-3">
                <div>
                    <h2 class="flex items-center gap-2 text-sm font-extrabold text-navy">
                        @include('partials.icon', ['name' => 'client', 'class' => 'h-4 w-4 text-accent'])
                        Top clients
                    </h2>
                    <p class="text-[11px] text-ink-muted">By completed jobs, then rating from technicians</p>
                </div>
                <a href="{{ route('accounts.index', 'client') }}" class="text-xs font-bold text-brand hover:underline">All</a>
            </header>
            @forelse ($topClients as $i => $c)
                @php
                    // Share of their jobs that ended in a finished repair - the
                    // difference between a client who books and one who cancels.
                    $followThrough = (int) $c['posted'] > 0 ? round($c['jobs'] / $c['posted'] * 100) : 0;
                @endphp
                <div class="flex items-center gap-3 border-b border-line py-2.5 last:border-0">
                    <span class="flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-[11px] font-extrabold
                                 {{ $i === 0 ? 'bg-accent text-white' : 'bg-canvas text-ink-muted' }}">{{ $i + 1 }}</span>
                    <div class="min-w-0 flex-1">
                        <div class="truncate text-sm font-bold">{{ $c['name'] ?: 'Unnamed' }}</div>
                        <div class="truncate text-[11px] text-ink-muted">
                            {{ $c['jobs'] }} completed · {{ $c['posted'] }} posted · {{ $followThrough }}% follow-through
                        </div>
                    </div>
                    <span class="flex items-center gap-1 text-xs font-bold text-brand"
                          title="Average rating from technicians ({{ $c['reviews'] }} {{ Str::plural('rating', (int) $c['reviews']) }})">
                        @include('partials.icon', ['name' => 'star', 'class' => 'h-3.5 w-3.5'])
                        {{ $c['rating'] !== null ? number_format((float) $c['rating'], 2) : '—' }}
                    </span>
                </div>
            @empty
                <p class="py-6 text-center text-xs text-ink-muted">No client has posted a job yet.</p>
            @endforelse
        </section>
    </div>

    {{-- ------------------------------------------- Devices, ratings, community --}}
    <div class="mt-6 grid gap-6 lg:grid-cols-2 xl:grid-cols-3">

        <section class="rounded-2xl border border-line bg-white p-5 shadow-sm lg:col-span-2 xl:col-span-1">
            <h2 class="text-sm font-extrabold text-navy">What gets repaired</h2>
            <p class="mb-4 text-[11px] text-ink-muted">Jobs by device category</p>
            @forelse ($devices as $d)
                <div class="mb-3 last:mb-0">
                    <div class="mb-1 flex items-center justify-between text-xs">
                        <span class="font-semibold">{{ \App\Support\JobProgress::device($d['device_type']) }}</span>
                        <span class="font-bold tabular-nums text-navy">{{ $d['jobs'] }}</span>
                    </div>
                    <div class="h-2 overflow-hidden rounded-full bg-canvas">
                        <div class="h-full rounded-full bg-brand"
                            style="width: {{ round(($d['jobs'] / $deviceMax) * 100) }}%"></div>
                    </div>
                </div>
            @empty
                <p class="py-6 text-center text-xs text-ink-muted">No jobs yet.</p>
            @endforelse
        </section>

        <section class="rounded-2xl border border-line bg-white p-5 shadow-sm">
            <h2 class="mb-3 text-sm font-extrabold text-navy">Ratings, both ways</h2>
            <div class="grid grid-cols-2 gap-3">
                <div class="rounded-xl bg-accent-soft/60 p-3">
                    <div class="text-[10px] font-bold uppercase tracking-wider text-accent">Clients rate techs</div>
                    <div class="mt-1 text-xl font-extrabold tabular-nums text-navy">
                        {{ ($ratings['technician_avg'] ?? null) !== null ? number_format((float) $ratings['technician_avg'], 2) : '—' }}
                    </div>
                    <div class="text-[11px] text-ink-muted">{{ $num($ratings['technician_count'] ?? 0) }} reviews</div>
                </div>
                <div class="rounded-xl bg-brand-soft/60 p-3">
                    <div class="text-[10px] font-bold uppercase tracking-wider text-brand">Techs rate clients</div>
                    <div class="mt-1 text-xl font-extrabold tabular-nums text-navy">
                        {{ ($ratings['client_avg'] ?? null) !== null ? number_format((float) $ratings['client_avg'], 2) : '—' }}
                    </div>
                    <div class="text-[11px] text-ink-muted">{{ $num($ratings['client_count'] ?? 0) }} ratings</div>
                </div>
            </div>
        </section>

        <section class="rounded-2xl border border-line bg-white p-5 shadow-sm">
            <h2 class="mb-3 flex items-center gap-2 text-sm font-extrabold text-navy">
                @include('partials.icon', ['name' => 'forum', 'class' => 'h-4 w-4 text-brand'])
                Community
            </h2>
            <div class="grid grid-cols-3 gap-2 text-center">
                @foreach ([['Questions', $comm['questions'] ?? 0], ['Answers', $comm['answers'] ?? 0], ['Helpful', $comm['helpful'] ?? 0]] as [$l, $v])
                    <div class="rounded-xl bg-canvas p-2.5">
                        <div class="text-lg font-extrabold tabular-nums text-navy">{{ $num($v) }}</div>
                        <div class="text-[10px] font-semibold text-ink-muted">{{ $l }}</div>
                    </div>
                @endforeach
            </div>
            {{-- Was "technicians online now"; the online switch was retired and
                 availability is vacation days now (20260922000004). --}}
            @php $away = (int) ($users['on_vacation'] ?? 0); @endphp
            <p class="mt-3 text-[11px] text-ink-muted">
                {{ $away === 0 ? 'No technicians on vacation today' : $num($away).' '.Str::plural('technician', $away).' on vacation today' }}
            </p>
        </section>
    </div>

    {{-- -------------------------------------------------- Live work + queue --}}
    <div class="mt-6 grid gap-6 xl:grid-cols-2">

        <section class="rounded-2xl border border-line bg-white shadow-sm">
            <header class="flex items-center justify-between border-b border-line px-5 py-4">
                <div>
                    <h2 class="text-sm font-extrabold text-navy">Live work</h2>
                    <p class="text-[11px] text-ink-muted">Jobs matched, accepted or underway</p>
                </div>
                <a href="{{ route('jobs.index') }}" class="text-xs font-bold text-brand hover:underline">View all</a>
            </header>
            @forelse ($liveJobs as $job)
                @php $p = \App\Support\JobProgress::for($job); @endphp
                <a href="{{ route('jobs.show', $job['id']) }}"
                    class="block border-b border-line px-5 py-3.5 last:border-0 hover:bg-canvas">
                    <div class="mb-2 flex items-center justify-between gap-3">
                        <div class="min-w-0">
                            <div class="truncate text-sm font-bold">
                                {{ \App\Support\JobProgress::symptom($job['problem_symptom'] ?? null) }}</div>
                            <div class="truncate text-[11px] text-ink-muted">
                                {{ $job['client_name'] ?: 'Client' }} →
                                {{ $job['technician_name'] ?: 'unassigned' }}
                            </div>
                        </div>
                        @include('partials.badge', ['value' => $job['status']])
                    </div>
                    <div class="flex items-center gap-3">
                        <div class="h-1.5 flex-1 overflow-hidden rounded-full bg-canvas">
                            <div class="h-full rounded-full bg-brand" style="width: {{ $p['percent'] }}%"></div>
                        </div>
                        <span
                            class="w-24 truncate text-right text-[11px] font-semibold text-ink-muted">{{ $p['label'] }}</span>
                    </div>
                </a>
            @empty
                <div class="px-5 py-10 text-center">
                    <p class="text-sm font-bold text-ink">Nothing in progress</p>
                    <p class="mt-1 text-xs text-ink-muted">Matched and active jobs appear here.</p>
                </div>
            @endforelse
        </section>

        <section class="rounded-2xl border border-line bg-white shadow-sm">
            <header class="flex items-center justify-between border-b border-line px-5 py-4">
                <div>
                    <h2 class="text-sm font-extrabold text-navy">Oldest waiting</h2>
                    <p class="text-[11px] text-ink-muted">First in, first reviewed</p>
                </div>
                <a href="{{ route('verifications.index') }}" class="text-xs font-bold text-brand hover:underline">View
                    all</a>
            </header>

            @forelse ($queue as $row)
                <a href="{{ route('verifications.show', $row['verification_id']) }}"
                    class="flex items-center gap-4 border-b border-line px-5 py-3.5 last:border-0 hover:bg-canvas">
                    @include('jobs._person', [
                        'name' => $row['full_name'] ?? null,
                        'sub' => $row['email'] ?? '',
                        'tone' => $row['role'] === 'client' ? 'accent' : 'brand',
                    ])
                    <div class="ml-auto flex shrink-0 items-center gap-3">
                        @include('partials.badge', ['value' => $row['role']])
                        <span class="w-16 text-right text-[11px] font-semibold text-ink-muted">
                            {{ \Carbon\Carbon::parse($row['submitted_at'])->diffForHumans(null, true) }}
                        </span>
                    </div>
                </a>
            @empty
                <div class="px-5 py-10 text-center">
                    <p class="text-sm font-bold text-ink">Queue is clear</p>
                    <p class="mt-1 text-xs text-ink-muted">Nothing is waiting on a decision.</p>
                </div>
            @endforelse
        </section>
    </div>

    {{-- ------------------------------------------------ Verification tiles --}}
    <section class="mt-6 rounded-2xl border border-line bg-white shadow-sm">
        <header class="border-b border-line px-5 py-4">
            <h2 class="text-sm font-extrabold text-navy">Registration pipeline</h2>
            <p class="text-[11px] text-ink-muted">Where every account is in sign-up and review</p>
        </header>
        @php
            $tiles = [
                ['label' => 'Waiting on review', 'value' => $pending, 'tone' => 'warn'],
                [
                    'label' => 'Credentials queued',
                    'value' => (int) ($stats['pending_documents'] ?? 0),
                    'tone' => 'warn',
                ],
                ['label' => 'Active accounts', 'value' => (int) ($stats['active_accounts'] ?? 0), 'tone' => 'ok'],
                ['label' => 'Incomplete', 'value' => (int) ($stats['incomplete_accounts'] ?? 0), 'tone' => 'ink'],
                [
                    'label' => 'Cleared to work',
                    'value' => (int) ($stats['verified_technicians'] ?? 0),
                    'tone' => 'brand',
                ],
                ['label' => 'New this week', 'value' => (int) ($users['new_7d'] ?? 0), 'tone' => 'brand'],
            ];
        @endphp
        <div class="grid grid-cols-2 divide-line sm:grid-cols-3 xl:grid-cols-6 xl:divide-x">
            @foreach ($tiles as $tile)
                @php [$bg, $fg] = $tones[$tile['tone']]; @endphp
                <div class="p-5">
                    <div class="mb-2 inline-flex h-2 w-2 rounded-full {{ str_replace('text-', 'bg-', $fg) }}"></div>
                    <div class="text-2xl font-extrabold tabular-nums text-navy">{{ $tile['value'] }}</div>
                    <div class="mt-0.5 text-xs font-semibold text-ink-muted">{{ $tile['label'] }}</div>
                </div>
            @endforeach
        </div>
    </section>

    {{-- ------------------------------------------------------- History --}}
    <section class="mt-6 rounded-2xl border border-line bg-white shadow-sm">
        <header class="border-b border-line px-5 py-4">
            <h2 class="text-sm font-extrabold text-navy">Recently decided</h2>
            <p class="text-[11px] text-ink-muted">The last few reviews and who made them</p>
        </header>

        @forelse ($recent as $row)
            <a href="{{ route('verifications.show', $row['verification_id']) }}"
                class="flex items-center gap-4 border-b border-line px-5 py-3.5 last:border-0 hover:bg-canvas">
                <div class="min-w-0 flex-1">
                    <div class="truncate text-sm font-bold">{{ $row['full_name'] ?: 'Unnamed applicant' }}</div>
                    <div class="truncate text-[11px] text-ink-muted">
                        by {{ $row['reviewed_by_name'] ?? 'system' }}
                        @if (!empty($row['reviewed_at']))
                            · {{ \Carbon\Carbon::parse($row['reviewed_at'])->diffForHumans() }}
                        @endif
                    </div>
                </div>
                @include('partials.badge', ['value' => $row['role']])
                @include('partials.badge', ['value' => $row['status']])
            </a>
        @empty
            <div class="px-5 py-10 text-center">
                <p class="text-sm font-bold text-ink">No decisions yet</p>
                <p class="mt-1 text-xs text-ink-muted">Reviewed submissions will appear here.</p>
            </div>
        @endforelse
    </section>

@endsection
