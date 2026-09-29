@extends('layouts.app')

@section('title', 'Jobs')


@section('content')

    @php
        $tabs = [
            'active' => 'Active',
            'completed' => 'Completed',
            'cancelled' => 'Cancelled',
            'all' => 'All',
        ];
    @endphp

    {{-- Filters --}}
    <div class="mb-5 flex flex-wrap items-center justify-between gap-3">
        <div class="flex flex-wrap gap-2">
            @foreach ($tabs as $key => $label)
                <a href="{{ route('jobs.index', array_filter(['status' => $key, 'q' => $search])) }}"
                    class="inline-flex items-center gap-2 rounded-xl px-4 py-2 text-xs font-bold transition
                      {{ $filter === $key ? 'bg-brand text-white shadow-md shadow-brand/25' : 'border border-line bg-white text-ink-muted hover:text-ink' }}">
                    {{ $label }}
                    <span
                        class="rounded-full px-1.5 text-[10px] {{ $filter === $key ? 'bg-white/25' : 'bg-canvas' }}">{{ $counts[$key] }}</span>
                </a>
            @endforeach
        </div>

        <form method="GET" action="{{ route('jobs.index') }}" class="relative">
            <input type="hidden" name="status" value="{{ $filter }}">
            <span class="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-ink-muted">
                @include('partials.icon', ['name' => 'search', 'class' => 'h-4 w-4'])
            </span>
            <input type="text" name="q" value="{{ $search }}" placeholder="Client, technician or fault"
                class="w-64 rounded-xl border border-line bg-white py-2 pl-9 pr-3 text-xs font-semibold outline-none transition focus:border-brand focus:ring-2 focus:ring-brand/15">
        </form>
    </div>

    <div class="overflow-hidden rounded-2xl border border-line bg-white shadow-sm">
        <div class="overflow-x-auto">
            <table class="w-full min-w-[980px] text-left">
                <thead class="border-b border-line bg-canvas/60">
                    <tr class="text-[11px] font-bold uppercase tracking-wider text-ink-muted">
                        <th class="px-5 py-3">Job</th>
                        <th class="px-5 py-3">Client</th>
                        <th class="px-5 py-3">Technician</th>
                        <th class="px-5 py-3 w-56">Progress</th>
                        <th class="px-5 py-3">Status</th>
                        <th class="px-5 py-3">Posted</th>
                        <th class="px-5 py-3"></th>
                    </tr>
                </thead>
                <tbody>
                    @forelse ($jobs as $job)
                        @php
                            $p = \App\Support\JobProgress::for($job);
                            $bar = $p['cancelled'] ? 'bg-ink-muted/40' : ($p['percent'] >= 100 ? 'bg-ok' : 'bg-brand');
                        @endphp
                        <tr class="border-b border-line last:border-0 transition hover:bg-canvas/60">
                            <td class="px-5 py-3.5">
                                <div class="flex items-center gap-3">
                                    <div
                                        class="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-brand-soft text-brand">
                                        @include('partials.icon', [
                                            'name' => 'device',
                                            'class' => 'h-4 w-4',
                                        ])
                                    </div>
                                    <div class="min-w-0">
                                        <div class="truncate text-sm font-bold">
                                            {{ \App\Support\JobProgress::symptom($job['problem_symptom'] ?? null) }}</div>
                                        <div class="truncate text-[11px] text-ink-muted">
                                            {{ \App\Support\JobProgress::device($job['device_type'] ?? null) }}{{ !empty($job['brand']) ? ' · ' . $job['brand'] : '' }}
                                            · <span
                                                class="font-mono">{{ \App\Support\JobProgress::reference($job['id']) }}</span>
                                        </div>
                                    </div>
                                </div>
                            </td>

                            <td class="px-5 py-3.5">
                                @include('jobs._person', [
                                    'name' => $job['client_name'] ?? null,
                                    'avatar' => $job['client_avatar'] ?? null,
                                    'sub' => $job['client_email'] ?? 'Client',
                                    'tone' => 'accent',
                                ])
                            </td>

                            <td class="px-5 py-3.5">
                                @if (!empty($job['technician_name']))
                                    @include('jobs._person', [
                                        'name' => $job['technician_name'],
                                        'avatar' => $job['technician_avatar'] ?? null,
                                        'sub' => !empty($job['awaiting_technician'])
                                            ? 'Requested - not yet accepted'
                                            : 'Assigned',
                                        'tone' => 'brand',
                                        'warn' => !empty($job['awaiting_technician']),
                                    ])
                                @else
                                    <span
                                        class="inline-flex items-center gap-1.5 rounded-lg bg-canvas px-2.5 py-1 text-[11px] font-semibold text-ink-muted">
                                        @include('partials.icon', [
                                            'name' => 'clock',
                                            'class' => 'h-3.5 w-3.5',
                                        ])
                                        {{ $job['status'] === 'cancelled' ? 'Nobody assigned' : 'Finding a technician' }}
                                    </span>
                                @endif
                            </td>

                            <td class="px-5 py-3.5">
                                <div class="mb-1.5 flex items-center justify-between text-[11px]">
                                    <span
                                        class="truncate font-bold {{ $p['cancelled'] ? 'text-ink-muted' : 'text-ink' }}">{{ $p['label'] }}</span>
                                    <span class="font-bold tabular-nums text-ink-muted">{{ $p['percent'] }}%</span>
                                </div>
                                <div class="h-1.5 overflow-hidden rounded-full bg-canvas">
                                    <div class="h-full rounded-full {{ $bar }}"
                                        style="width: {{ $p['percent'] }}%"></div>
                                </div>
                            </td>

                            <td class="px-5 py-3.5">@include('partials.badge', ['value' => $job['status']])</td>

                            <td class="px-5 py-3.5">
                                @php $posted = \Carbon\Carbon::parse($job['created_at']); @endphp
                                <div class="text-xs font-semibold">{{ $posted->diffForHumans() }}</div>
                                <div class="text-[11px] text-ink-muted">{{ $posted->format('d M, H:i') }}</div>
                            </td>

                            <td class="px-5 py-3.5 text-right">
                                <a href="{{ route('jobs.show', $job['id']) }}"
                                    class="inline-flex items-center gap-1 rounded-lg bg-brand px-3.5 py-2 text-[11px] font-bold text-white transition hover:bg-brand-dark">
                                    View
                                    @include('partials.icon', [
                                        'name' => 'arrow-right',
                                        'class' => 'h-3 w-3',
                                        'stroke' => 2.5,
                                    ])
                                </a>
                            </td>
                        </tr>
                    @empty
                        <tr>
                            <td colspan="7" class="px-5 py-16 text-center">
                                <div
                                    class="mx-auto mb-3 flex h-12 w-12 items-center justify-center rounded-2xl bg-canvas text-ink-muted">
                                    @include('partials.icon', ['name' => 'jobs', 'class' => 'h-6 w-6'])
                                </div>
                                <p class="text-sm font-bold text-ink">No jobs here</p>
                                <p class="mt-1 text-xs text-ink-muted">
                                    {{ $search !== '' ? 'Nothing matches "' . $search . '".' : 'Nothing ' . ($filter === 'all' ? '' : $filter) . ' yet.' }}
                                </p>
                            </td>
                        </tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

    @if (count($jobs) >= 200)
        <p class="mt-3 text-center text-[11px] text-ink-muted">Showing the 200 most recent. Use search to narrow it down.
        </p>
    @endif

@endsection
