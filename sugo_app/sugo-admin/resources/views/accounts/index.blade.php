@extends('layouts.app')

@section('title', Str::plural(Str::title($role)))


@section('content')

    @php
        $tabs = [
            'all' => 'All (' . $counts['all'] . ')',
            'active' => 'Active (' . $counts['active'] . ')',
            'incomplete' => 'Incomplete (' . $counts['incomplete'] . ')',
            'rejected' => 'Rejected (' . $counts['rejected'] . ')',
        ];
    @endphp

    @include('partials.page-hero', [
        'icon' => $role === 'technician' ? 'technician' : 'client',
        'kicker' => Str::plural(Str::title($role)),
        'value' => $counts['all'],
        'label' => Str::plural($role, $counts['all']),
        'sub' => $counts['active'] . ' active · ' . $counts['incomplete'] . ' incomplete · ' . $counts['rejected'] . ' rejected',
    ])

    {{-- Accounts awaiting review are not listed here: they are decided in ID
         review, so that is where they are (2026-11-17). --}}
    @if (($counts['pending_review'] ?? 0) > 0)
        <a href="{{ route('verifications.index', ['role' => $role]) }}"
           class="sugo-rise group mb-5 flex items-center gap-3 rounded-2xl border border-warn/25 bg-warn-soft px-5 py-3.5 transition hover:-translate-y-0.5 hover:shadow-md"
           style="--d: 60ms">
            <span class="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-white text-warn shadow-sm">
                @include('partials.icon', ['name' => 'id', 'class' => 'h-4 w-4', 'stroke' => 2])
            </span>
            <span class="min-w-0 flex-1">
                <span class="block text-sm font-extrabold text-ink">
                    {{ $counts['pending_review'] }} {{ Str::plural($role, $counts['pending_review']) }} awaiting review
                </span>
                <span class="block text-[11px] text-ink-muted">
                    They are in ID review until a reviewer decides, then they appear here.
                </span>
            </span>
            <span class="inline-flex shrink-0 items-center gap-1 text-xs font-bold text-warn">
                Open ID review
                @include('partials.icon', ['name' => 'arrow-right', 'class' => 'h-3.5 w-3.5 transition group-hover:translate-x-0.5', 'stroke' => 2.4])
            </span>
        </a>
    @endif

    <div class="mb-5 flex flex-wrap gap-2">
        @foreach ($tabs as $key => $label)
            <a href="{{ route('accounts.index', ['role' => $role, 'status' => $key]) }}"
                class="rounded-xl px-4 py-2 text-xs font-bold transition
                  {{ $status === $key ? 'bg-gradient-to-r from-brand to-brand-light text-white shadow-md shadow-brand/25' : 'border border-line bg-white text-ink-muted hover:-translate-y-0.5 hover:text-ink hover:shadow-sm' }}">
                {{ $label }}
            </a>
        @endforeach
    </div>

    <div class="overflow-hidden rounded-2xl border border-line bg-white shadow-sm" data-reveal>
        <div class="overflow-x-auto">
            <table class="w-full min-w-[900px] text-left">
                <thead class="border-b border-line bg-canvas/60">
                    <tr class="text-[11px] font-bold uppercase tracking-wider text-ink-muted">
                        <th class="px-5 py-3">Name</th>
                        <th class="px-5 py-3">Status</th>
                        @if ($role === 'technician')
                            <th class="px-5 py-3">Skills</th>
                            <th class="px-5 py-3">Work</th>
                            <th class="px-5 py-3">Tier</th>
                            <th class="px-5 py-3">Can work</th>
                        @else
                            <th class="px-5 py-3">Phone</th>
                            <th class="px-5 py-3">Trust</th>
                            <th class="px-5 py-3">Addresses</th>
                        @endif
                        <th class="px-5 py-3">Joined</th>
                        <th class="px-5 py-3"></th>
                    </tr>
                </thead>
                <tbody>
                    @forelse ($rows as $row)
                        <tr class="sugo-rise border-b border-line last:border-0 transition hover:bg-brand-softer/70"
                            style="--d: {{ min($loop->index, 12) * 35 }}ms">
                            <td class="px-5 py-3.5">
                                <div class="flex items-center gap-3">
                                    <div
                                        class="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-gradient-to-br text-xs font-extrabold text-white shadow-sm
                                            {{ $role === 'client' ? 'from-accent-light to-[#FBBF24]' : 'from-brand-light to-[#11C5E8]' }}">
                                        {{ strtoupper(substr($row['full_name'] ?? '?', 0, 1)) }}
                                    </div>
                                    <div class="min-w-0">
                                        <div class="truncate text-sm font-bold">{{ $row['full_name'] ?: 'Unnamed' }}</div>
                                        <div class="truncate text-[11px] text-ink-muted">{{ $row['email'] ?? '' }}</div>
                                    </div>
                                </div>
                            </td>
                            <td class="px-5 py-3.5">@include('partials.badge', ['value' => $row['registration_status']])</td>

                            @if ($role === 'technician')
                                <td class="px-5 py-3.5 text-xs">
                                    <span class="font-bold">{{ $row['verified_specializations'] ?? 0 }}</span>
                                    <span class="text-ink-muted">/ {{ $row['specialization_count'] ?? 0 }} passed</span>
                                </td>
                                <td class="px-5 py-3.5">
                                    @include('partials.work-type', [
                                        'tech' => ($workTypes ?? [])[$row['user_id']] ?? null,
                                        'compact' => true,
                                    ])
                                </td>
                                <td class="px-5 py-3.5">@include('partials.badge', [
                                    'value' => $row['verification_tier'] ?? 'basic',
                                ])</td>
                                <td class="px-5 py-3.5">
                                    @if ($row['technician_verified'] ?? false)
                                        <span class="text-xs font-bold text-ok">Yes</span>
                                    @else
                                        <span class="text-xs text-ink-muted">Not yet</span>
                                    @endif
                                </td>
                            @else
                                <td class="px-5 py-3.5">
                                    @if ($row['phone_verified'] ?? false)
                                        <span class="text-xs font-bold text-ok">Verified</span>
                                    @else
                                        <span class="text-xs text-ink-muted">Unverified</span>
                                    @endif
                                </td>
                                <td class="px-5 py-3.5">@include('partials.badge', ['value' => $row['trust_level'] ?? 'new'])</td>
                                <td class="px-5 py-3.5 text-xs text-ink-muted">{{ $row['address_count'] ?? 0 }}</td>
                            @endif

                            <td class="px-5 py-3.5 text-[11px] text-ink-muted">
                                {{ \Carbon\Carbon::parse($row['created_at'])->format('d M Y') }}
                            </td>
                            <td class="px-5 py-3.5 text-right">
                                <a href="{{ route('accounts.show', [$role, $row['user_id']]) }}"
                                    class="rounded-lg border border-line px-3.5 py-2 text-[11px] font-bold text-brand transition hover:-translate-y-0.5 hover:border-brand hover:bg-brand hover:text-white hover:shadow-md">
                                    View
                                </a>
                            </td>
                        </tr>
                    @empty
                        <tr>
                            <td colspan="{{ $role === 'technician' ? 8 : 7 }}">
                                @include('partials.empty', [
                                    'icon' => $role === 'technician' ? 'technician' : 'client',
                                    'title' => 'No accounts',
                                    'message' => 'Nothing matches this filter.',
                                ])
                            </td>
                        </tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

@endsection
