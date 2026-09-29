@extends('layouts.app')

@section('title', Str::plural(Str::title($role)))


@section('content')

    @php
        $tabs = [
            'all' => 'All (' . $counts['all'] . ')',
            'pending_review' => 'Awaiting review (' . $counts['pending_review'] . ')',
            'active' => 'Active (' . $counts['active'] . ')',
            'incomplete' => 'Incomplete (' . $counts['incomplete'] . ')',
            'rejected' => 'Rejected (' . $counts['rejected'] . ')',
        ];
    @endphp

    <div class="mb-5 flex flex-wrap gap-2">
        @foreach ($tabs as $key => $label)
            <a href="{{ route('accounts.index', ['role' => $role, 'status' => $key]) }}"
                class="rounded-xl px-4 py-2 text-xs font-bold transition
                  {{ $status === $key ? 'bg-brand text-white' : 'border border-line bg-white text-ink-muted hover:text-ink' }}">
                {{ $label }}
            </a>
        @endforeach
    </div>

    <div class="overflow-hidden rounded-2xl border border-line bg-white">
        <div class="overflow-x-auto">
            <table class="w-full min-w-[900px] text-left">
                <thead class="border-b border-line bg-canvas/60">
                    <tr class="text-[11px] font-bold uppercase tracking-wider text-ink-muted">
                        <th class="px-5 py-3">Name</th>
                        <th class="px-5 py-3">Status</th>
                        @if ($role === 'technician')
                            <th class="px-5 py-3">Skills</th>
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
                        <tr class="border-b border-line last:border-0 hover:bg-canvas/60">
                            <td class="px-5 py-3.5">
                                <div class="flex items-center gap-3">
                                    <div
                                        class="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-brand-soft text-xs font-bold text-brand">
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
                                    class="rounded-lg border border-line px-3.5 py-2 text-[11px] font-bold text-brand transition hover:bg-brand-softer">
                                    View
                                </a>
                            </td>
                        </tr>
                    @empty
                        <tr>
                            <td colspan="7" class="px-5 py-14 text-center">
                                <p class="text-sm font-bold text-ink">No accounts</p>
                                <p class="mt-1 text-xs text-ink-muted">Nothing matches this filter.</p>
                            </td>
                        </tr>
                    @endforelse
                </tbody>
            </table>
        </div>
    </div>

@endsection
