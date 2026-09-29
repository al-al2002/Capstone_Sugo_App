@extends('layouts.app')

@section('title', \App\Support\JobProgress::symptom($job['problem_symptom'] ?? null))
@section('subtitle', \App\Support\JobProgress::device($job['device_type'] ?? null) . ' · Job ' .
    \App\Support\JobProgress::reference($job['id']))

@section('actions')
    <a href="{{ route('jobs.index') }}"
        class="inline-flex items-center gap-1.5 rounded-xl border border-line px-4 py-2 text-xs font-bold text-ink-muted transition hover:text-ink">
        @include('partials.icon', ['name' => 'arrow-left', 'class' => 'h-3.5 w-3.5', 'stroke' => 2.5])
        All jobs
    </a>
@endsection

@section('content')

    @php
        $p = \App\Support\JobProgress::for($job);
        $money = fn($v) => $v === null ? null : '₱' . number_format((float) $v);
        $budget = collect([$money($job['budget_min'] ?? null), $money($job['budget_max'] ?? null)])
            ->filter()
            ->implode(' – ');
        $stars = function (?int $n): string {
            if ($n === null) {
                return '';
            }
            return str_repeat('★', $n) . str_repeat('☆', 5 - $n);
        };
    @endphp

    {{-- ----------------------------------------------------------- Progress --}}
    <section class="mb-6 rounded-2xl border border-line bg-white p-6 shadow-sm">
        <div class="mb-5 flex flex-wrap items-center justify-between gap-3">
            <div class="flex items-center gap-3">
                @include('partials.badge', ['value' => $job['status']])
                @if (!empty($job['service_path']))
                    @include('partials.badge', ['value' => $job['service_path']])
                @endif
            </div>
            <div class="text-right">
                <div class="text-2xl font-extrabold tabular-nums text-navy">{{ $p['percent'] }}%</div>
                <div class="text-[11px] font-semibold text-ink-muted">{{ $p['label'] }}</div>
            </div>
        </div>

        @if ($p['cancelled'])
            <div class="rounded-xl border border-line bg-canvas px-4 py-3 text-sm font-semibold text-ink-muted">
                This job was cancelled{{ empty($job['technician_name']) ? ' before anyone was assigned' : '' }}.
            </div>
        @else
            {{-- The five lifecycle steps. Done steps are ticked, the current one is
             ringed, and the connector fills as the job moves - so "how far has
             it got?" is answered before any row of detail is read. --}}
            <ol class="grid grid-cols-5 gap-2">
                @foreach ($p['steps'] as $i => $step)
                    @php
                        $done = $step['state'] === 'done';
                        $current = $step['state'] === 'current';
                    @endphp
                    <li class="relative flex flex-col items-center text-center">
                        @if (!$loop->last)
                            <span class="absolute left-1/2 top-4 h-0.5 w-full {{ $done ? 'bg-ok' : 'bg-line' }}"></span>
                        @endif
                        <span
                            class="relative z-10 flex h-8 w-8 items-center justify-center rounded-full border-2 text-xs font-extrabold
                                 {{ $done ? 'border-ok bg-ok text-white' : ($current ? 'border-brand bg-white text-brand ring-4 ring-brand/15' : 'border-line bg-white text-ink-muted') }}">
                            @if ($done)
                                @include('partials.icon', [
                                    'name' => 'check',
                                    'class' => 'h-4 w-4',
                                    'stroke' => 3,
                                ])
                            @else
                                {{ $i + 1 }}
                            @endif
                        </span>
                        <span
                            class="mt-2 text-[11px] font-bold leading-tight {{ $done || $current ? 'text-ink' : 'text-ink-muted' }}">{{ $step['label'] }}</span>
                    </li>
                @endforeach
            </ol>

            <div class="mt-5 h-2 overflow-hidden rounded-full bg-canvas">
                <div class="h-full rounded-full {{ $p['percent'] >= 100 ? 'bg-ok' : 'bg-brand' }}"
                    style="width: {{ $p['percent'] }}%"></div>
            </div>

            @if ($p['stage'])
                <p class="mt-3 flex items-center gap-2 text-xs text-ink-muted">
                    @include('partials.icon', ['name' => 'map', 'class' => 'h-3.5 w-3.5'])
                    Pickup journey: <span class="font-bold text-ink">{{ $p['stage'] }}</span>
                    @if (!empty($job['tracking_updated_at']))
                        · updated {{ \Carbon\Carbon::parse($job['tracking_updated_at'])->diffForHumans() }}
                    @endif
                </p>
            @endif
        @endif
    </section>

    <div class="grid gap-6 xl:grid-cols-[1fr_360px]">

        <div class="space-y-6">
            {{-- ---------------------------------------------------- The people --}}
            <div class="grid gap-4 md:grid-cols-2">
                <section class="rounded-2xl border border-line bg-white p-5 shadow-sm">
                    <div class="mb-4 flex items-center justify-between">
                        <h2 class="text-[11px] font-bold uppercase tracking-wider text-ink-muted">Client</h2>
                        @include('partials.badge', ['value' => 'client'])
                    </div>
                    @include('jobs._person', [
                        'name' => $job['client_name'] ?? null,
                        'avatar' => $job['client_avatar'] ?? null,
                        'sub' => $job['client_email'] ?? null,
                        'tone' => 'accent',
                        'size' => 'h-11 w-11',
                    ])
                    <div class="mt-4 flex flex-wrap gap-2">
                        @if (!empty($job['client_id']))
                            <a href="{{ route('accounts.show', ['client', $job['client_id']]) }}"
                                class="rounded-lg border border-line px-3 py-1.5 text-[11px] font-bold text-brand hover:bg-brand-softer">Open
                                account</a>
                        @endif
                    </div>
                </section>

                <section class="rounded-2xl border border-line bg-white p-5 shadow-sm">
                    <div class="mb-4 flex items-center justify-between">
                        <h2 class="text-[11px] font-bold uppercase tracking-wider text-ink-muted">Technician</h2>
                        @include('partials.badge', ['value' => 'technician'])
                    </div>
                    @if (!empty($job['technician_name']))
                        @include('jobs._person', [
                            'name' => $job['technician_name'],
                            'avatar' => $job['technician_avatar'] ?? null,
                            'sub' => !empty($job['awaiting_technician'])
                                ? 'Requested ' .
                                    \Carbon\Carbon::parse($job['requested_at'] ?? now())->diffForHumans() .
                                    ' - not yet accepted'
                                : 'Assigned',
                            'tone' => 'brand',
                            'warn' => !empty($job['awaiting_technician']),
                            'size' => 'h-11 w-11',
                        ])
                        @if (!empty($job['technician_id']))
                            <div class="mt-4">
                                <a href="{{ route('accounts.show', ['technician', $job['technician_id']]) }}"
                                    class="rounded-lg border border-line px-3 py-1.5 text-[11px] font-bold text-brand hover:bg-brand-softer">Open
                                    account</a>
                            </div>
                        @endif
                    @else
                        <div class="flex items-center gap-3 rounded-xl bg-canvas px-4 py-3">
                            @include('partials.icon', [
                                'name' => 'clock',
                                'class' => 'h-5 w-5 text-ink-muted',
                            ])
                            <div>
                                <div class="text-sm font-bold">
                                    {{ $job['status'] === 'cancelled' ? 'Nobody was assigned' : 'Finding a technician' }}
                                </div>
                                <div class="text-[11px] text-ink-muted">{{ (int) ($job['match_count'] ?? 0) }} ranked by
                                    RB-CARS</div>
                            </div>
                        </div>
                    @endif
                </section>
            </div>

            {{-- ------------------------------------------------------ Ratings --}}
            <section class="rounded-2xl border border-line bg-white p-5 shadow-sm">
                <h2 class="mb-4 flex items-center gap-2 text-sm font-extrabold text-navy">
                    @include('partials.icon', ['name' => 'star', 'class' => 'h-4 w-4 text-accent'])
                    Ratings
                </h2>
                <div class="grid gap-4 md:grid-cols-2">
                    <div class="rounded-xl border border-line p-4">
                        <div class="mb-1 text-[11px] font-bold uppercase tracking-wider text-ink-muted">Client → technician
                        </div>
                        @if (isset($job['client_rating_of_technician']))
                            <div class="text-lg tracking-wider text-accent">
                                {{ $stars((int) $job['client_rating_of_technician']) }}</div>
                            @if (!empty($job['client_review_comment']))
                                <p class="mt-2 text-xs italic leading-relaxed text-ink">
                                    "{{ $job['client_review_comment'] }}"</p>
                            @endif
                        @else
                            <p class="text-xs text-ink-muted">Not rated yet.</p>
                        @endif
                    </div>
                    <div class="rounded-xl border border-line p-4">
                        <div class="mb-1 text-[11px] font-bold uppercase tracking-wider text-ink-muted">Technician → client
                        </div>
                        @if (isset($job['technician_rating_of_client']))
                            <div class="text-lg tracking-wider text-accent">
                                {{ $stars((int) $job['technician_rating_of_client']) }}</div>
                        @else
                            <p class="text-xs text-ink-muted">Not rated yet.</p>
                        @endif
                    </div>
                </div>
            </section>
        </div>

        {{-- -------------------------------------------------------- Details --}}
        <aside class="space-y-6">
            <section class="rounded-2xl border border-line bg-white p-5 shadow-sm">
                <h2 class="mb-4 text-sm font-extrabold text-navy">Job details</h2>
                @php
                    $rows = array_filter(
                        [
                            'Device' => \App\Support\JobProgress::device($job['device_type'] ?? null),
                            'Brand' => $job['brand'] ?? null,
                            'Fault' => \App\Support\JobProgress::symptom($job['problem_symptom'] ?? null),
                            'Urgency' => ($job['urgency'] ?? null) === 'need_today' ? 'Needed today' : 'Can wait',
                            'Budget' => $budget ?: null,
                            'Schedule' => !empty($job['preferred_schedule'])
                                ? \Carbon\Carbon::parse($job['preferred_schedule'])->format('d M Y, H:i')
                                : 'Flexible',
                            'Address' => $job['address_text'] ?? null,
                            'Posted' => \Carbon\Carbon::parse($job['created_at'])->format('d M Y, H:i'),
                            'Completed' => !empty($job['completed_at'])
                                ? \Carbon\Carbon::parse($job['completed_at'])->format('d M Y, H:i')
                                : null,
                            'Diagnosis' =>
                                array_key_exists('diagnosis_correct', $job) && $job['diagnosis_correct'] !== null
                                    ? ($job['diagnosis_correct']
                                        ? 'Correct first time'
                                        : 'Needed re-diagnosis')
                                    : null,
                        ],
                        fn($v) => $v !== null && $v !== '',
                    );
                @endphp
                <dl class="space-y-3">
                    @foreach ($rows as $label => $value)
                        <div class="flex items-start justify-between gap-4">
                            <dt class="shrink-0 text-[11px] font-bold uppercase tracking-wider text-ink-muted">
                                {{ $label }}</dt>
                            <dd class="text-right text-xs font-semibold">{{ $value }}</dd>
                        </div>
                    @endforeach
                </dl>
            </section>


        </aside>
    </div>

@endsection
