@extends('layouts.app')

@section('title', 'Disputes')
@section('subtitle', 'Problems reported on bookings. Your decision is shown to both people, word for word.')

@section('content')

    @php
        $reasons = [
            'not_fixed' => 'The problem was not fixed',
            'overcharged' => 'Charged more than agreed',
            'no_show' => 'Did not show up',
            'damage' => 'Something was damaged',
            'conduct' => 'Rude or unsafe behaviour',
            'payment' => 'Was not paid',
            'other' => 'Something else',
        ];
        $openCount = (int) ($counts['open'] ?? 0);
    @endphp

    @include('partials.page-hero', [
        'icon' => 'flag',
        'kicker' => 'Disputes',
        'value' => $openCount,
        'label' => 'open ' . Str::plural('report', $openCount),
        'sub' => $openCount > 0
            ? 'Read the booking\'s chat before deciding: it is the other half of the evidence.'
            : 'Nothing is waiting on a decision. ' . (int) ($counts['decided'] ?? 0) . ' decided so far.',
        'tone' => $openCount > 0 ? 'warn' : 'brand',
    ])

    {{-- Filters --}}
    <div class="mb-5 flex flex-wrap gap-2">
        @foreach (\App\Http\Controllers\DisputeController::FILTERS as $key => $label)
            <a href="{{ route('disputes.index', ['status' => $key]) }}"
                class="inline-flex items-center gap-2 rounded-xl px-4 py-2 text-xs font-bold transition
                  {{ $filter === $key ? 'bg-gradient-to-r from-brand to-brand-light text-white shadow-md shadow-brand/25' : 'border border-line bg-white text-ink-muted hover:-translate-y-0.5 hover:text-ink hover:shadow-sm' }}">
                {{ $label }}
                <span class="rounded-full px-1.5 text-[10px] {{ $filter === $key ? 'bg-white/25' : 'bg-canvas' }}">{{ $counts[$key] }}</span>
            </a>
        @endforeach
    </div>

    <div class="space-y-4">
        @forelse ($disputes as $dispute)
            @php
                $isOpen = $dispute['status'] === 'open';
                $reported = \Carbon\Carbon::parse($dispute['created_at']);
                $byClient = $dispute['raised_by_role'] === 'client';
            @endphp
            {{-- A status edge down the left (amber open, green resolved,
                 grey closed), rising in one after another. --}}
            <article class="sugo-rise sugo-lift relative overflow-hidden rounded-2xl border border-line bg-white p-5 pl-6 shadow-sm"
                style="--d: {{ min($loop->index, 8) * 60 }}ms">
                <span class="absolute inset-y-0 left-0 w-1.5 bg-gradient-to-b
                    {{ $isOpen ? 'from-accent-light to-accent' : ($dispute['status'] === 'resolved' ? 'from-[#34C77B] to-ok' : 'from-line to-ink-muted/40') }}"></span>
                <div class="flex flex-wrap items-start justify-between gap-3">
                    <div class="min-w-0">
                        <div class="flex flex-wrap items-center gap-2">
                            <span class="inline-flex items-center gap-1.5 rounded-lg px-2.5 py-1 text-[11px] font-bold
                                {{ $isOpen ? 'bg-warn-soft text-warn' : ($dispute['status'] === 'resolved' ? 'bg-ok-soft text-ok' : 'bg-canvas text-ink-muted') }}">
                                @include('partials.icon', ['name' => $isOpen ? 'clock' : 'check', 'class' => 'h-3.5 w-3.5'])
                                {{ $isOpen ? 'Open' : ($dispute['status'] === 'resolved' ? 'Resolved' : 'Closed') }}
                            </span>
                            <h2 class="text-sm font-extrabold text-ink">{{ $reasons[$dispute['reason']] ?? 'Something else' }}</h2>
                        </div>
                        <p class="mt-1 text-[11px] text-ink-muted">
                            Reported by the {{ $byClient ? 'client' : 'technician' }},
                            <span class="font-semibold text-ink">{{ $dispute['raised_by_name'] ?? 'Unknown' }}</span>
                            &middot; {{ $reported->diffForHumans() }} ({{ $reported->format('d M, H:i') }})
                        </p>
                    </div>
                    <a href="{{ route('jobs.show', $dispute['job_id']) }}"
                        class="inline-flex items-center gap-1 rounded-lg border border-line px-3 py-2 text-[11px] font-bold text-ink transition hover:bg-canvas">
                        Open the booking
                        @include('partials.icon', ['name' => 'arrow-right', 'class' => 'h-3 w-3', 'stroke' => 2.5])
                    </a>
                </div>

                <div class="mt-4 grid gap-4 lg:grid-cols-3">
                    <div class="lg:col-span-2">
                        <p class="whitespace-pre-line text-sm leading-relaxed text-ink">{{ $dispute['details'] }}</p>

                        @if (! empty($dispute['photo_urls']))
                            <div class="mt-3 flex flex-wrap gap-2">
                                @foreach ($dispute['photo_urls'] as $url)
                                    <a href="{{ $url }}" target="_blank" rel="noopener">
                                        <img src="{{ $url }}" alt="Photo attached to the report"
                                            class="h-24 w-24 rounded-xl border border-line object-cover transition duration-300 hover:scale-105 hover:shadow-lg">
                                    </a>
                                @endforeach
                            </div>
                        @endif
                    </div>

                    <dl class="space-y-2 rounded-xl bg-canvas p-3 text-[11px]">
                        <div>
                            <dt class="font-bold uppercase tracking-wider text-ink-muted">Booking</dt>
                            <dd class="font-semibold text-ink">
                                {{ \App\Support\JobProgress::symptom($dispute['problem_symptom'] ?? null) }}
                                &middot; {{ \App\Support\JobProgress::device($dispute['device_type'] ?? null) }}
                                <span class="font-mono text-ink-muted">{{ \App\Support\JobProgress::reference($dispute['job_id']) }}</span>
                            </dd>
                        </div>
                        <div>
                            <dt class="font-bold uppercase tracking-wider text-ink-muted">Client</dt>
                            <dd class="font-semibold text-ink">{{ $dispute['client_name'] ?? '—' }}</dd>
                        </div>
                        <div>
                            <dt class="font-bold uppercase tracking-wider text-ink-muted">Technician</dt>
                            <dd class="font-semibold text-ink">{{ $dispute['technician_name'] ?? '—' }}</dd>
                        </div>
                    </dl>
                </div>

                @if ($isOpen)
                    {{-- The chat on the booking is the other half of the evidence:
                         read it before deciding. --}}
                    <form method="POST" action="{{ route('disputes.update', $dispute['id']) }}" class="mt-4 border-t border-line pt-4">
                        @csrf
                        <input type="hidden" name="form_id" value="{{ $dispute['id'] }}">
                        <label for="note-{{ $dispute['id'] }}" class="text-[11px] font-bold uppercase tracking-wider text-ink-muted">
                            Your decision (both people will read this)
                        </label>
                        <textarea id="note-{{ $dispute['id'] }}" name="note" rows="3" maxlength="2000"
                            class="mt-1.5 w-full rounded-xl border border-line bg-white px-3 py-2 text-sm outline-none transition focus:border-brand focus:ring-2 focus:ring-brand/15"
                            placeholder="What you found, and what happens next.">{{ old('form_id') === $dispute['id'] ? old('note') : '' }}</textarea>
                        @if (old('form_id') === $dispute['id'])
                            @error('note')
                                <p class="mt-1 text-xs font-semibold text-bad">{{ $message }}</p>
                            @enderror
                        @endif

                        {{-- Progressive Trust Badge: only "Mark resolved" reads these.
                             An upheld CLIENT report counts against the technician's
                             Community Trusted badge; the remedy drops them one level. --}}
                        @php($oldHere = old('form_id') === $dispute['id'])
                        <div class="mt-3 grid gap-3 sm:grid-cols-3">
                            <label class="text-[11px] font-bold uppercase tracking-wider text-ink-muted">
                                Finding
                                <select name="outcome"
                                    class="mt-1.5 w-full rounded-xl border border-line bg-white px-3 py-2 text-sm font-normal normal-case tracking-normal text-ink outline-none focus:border-brand focus:ring-2 focus:ring-brand/15">
                                    <option value="upheld" @selected(! $oldHere || old('outcome', 'upheld') === 'upheld')>Upheld: the report was right</option>
                                    <option value="not_upheld" @selected($oldHere && old('outcome') === 'not_upheld')>Not upheld: nobody at fault</option>
                                </select>
                            </label>
                            @if ($byClient && ! empty($dispute['technician_id']))
                                <label class="text-[11px] font-bold uppercase tracking-wider text-ink-muted">
                                    Remedy
                                    <select name="remedy"
                                        class="mt-1.5 w-full rounded-xl border border-line bg-white px-3 py-2 text-sm font-normal normal-case tracking-normal text-ink outline-none focus:border-brand focus:ring-2 focus:ring-brand/15">
                                        <option value="none" @selected(! $oldHere || old('remedy', 'none') === 'none')>None</option>
                                        <option value="skill_deverification" @selected($oldHere && old('remedy') === 'skill_deverification')>Skill de-verification (one level down)</option>
                                    </select>
                                </label>
                                <label class="text-[11px] font-bold uppercase tracking-wider text-ink-muted">
                                    Specialization
                                    <select name="remedy_specialization"
                                        class="mt-1.5 w-full rounded-xl border border-line bg-white px-3 py-2 text-sm font-normal normal-case tracking-normal text-ink outline-none focus:border-brand focus:ring-2 focus:ring-brand/15">
                                        <option value="">Only for de-verification</option>
                                        @foreach (\App\Support\Specializations::LABELS as $value => $label)
                                            <option value="{{ $value }}" @selected($oldHere && old('remedy_specialization') === $value)>{{ $label }}</option>
                                        @endforeach
                                    </select>
                                </label>
                            @endif
                        </div>
                        @if ($oldHere)
                            @error('remedy_specialization')
                                <p class="mt-1 text-xs font-semibold text-bad">{{ $message }}</p>
                            @enderror
                        @endif

                        <div class="mt-3 flex flex-wrap justify-end gap-2">
                            <button type="submit" name="decision" value="dismissed"
                                class="rounded-lg border border-line px-4 py-2 text-xs font-bold text-ink-muted transition hover:bg-canvas">
                                Close without action
                            </button>
                            <button type="submit" name="decision" value="resolved"
                                class="rounded-lg bg-gradient-to-r from-brand to-brand-light px-4 py-2 text-xs font-bold text-white shadow-sm transition hover:-translate-y-0.5 hover:shadow-md">
                                Mark resolved
                            </button>
                        </div>
                    </form>
                @else
                    <div class="mt-4 rounded-xl border border-line bg-brand-softer p-3">
                        <p class="text-[11px] font-bold uppercase tracking-wider text-ink-muted">
                            Decision
                            @if (! empty($dispute['resolved_by_name']))
                                by {{ $dispute['resolved_by_name'] }}
                            @endif
                            @if (! empty($dispute['resolved_at']))
                                &middot; {{ \Carbon\Carbon::parse($dispute['resolved_at'])->format('d M, H:i') }}
                            @endif
                        </p>
                        <p class="mt-1 whitespace-pre-line text-sm text-ink">{{ $dispute['resolution_note'] }}</p>
                        @if (! empty($dispute['outcome']))
                            <p class="mt-2 text-xs font-semibold text-ink-muted">
                                {{ $dispute['outcome'] === 'upheld' ? 'Upheld' : 'Not upheld' }}
                                @if (($dispute['remedy'] ?? 'none') === 'skill_deverification')
                                    &middot; Skill de-verification:
                                    {{ \App\Support\Specializations::LABELS[$dispute['remedy_specialization']] ?? $dispute['remedy_specialization'] }}
                                @endif
                            </p>
                        @endif
                    </div>
                @endif
            </article>
        @empty
            <div class="rounded-2xl border border-line bg-white shadow-sm">
                @include('partials.empty', [
                    'icon' => 'flag',
                    'title' => 'No reports here',
                    'message' => $filter === 'open' ? 'Nothing is waiting on a decision.' : 'Nothing yet.',
                ])
            </div>
        @endforelse
    </div>

@endsection
