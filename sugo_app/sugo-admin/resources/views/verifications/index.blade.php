@extends('layouts.app')

@section('title', 'ID review')
@section('subtitle', 'Government ID and selfie submissions')

@section('content')

@php
    $tabs = [
        'pending'  => 'Waiting ('.$counts['pending'].')',
        'approved' => 'Approved ('.$counts['approved'].')',
        'rejected' => 'Rejected ('.$counts['rejected'].')',
        'all'      => 'All',
    ];
@endphp

<div class="mb-5 flex flex-wrap items-center justify-between gap-3">
    <div class="flex flex-wrap gap-2">
        @foreach ($tabs as $key => $label)
            <a href="{{ route('verifications.index', ['status' => $key, 'role' => $role]) }}"
               class="rounded-xl px-4 py-2 text-xs font-bold transition
                      {{ $status === $key ? 'bg-brand text-white shadow-md shadow-brand/25' : 'border border-line bg-white text-ink-muted hover:text-ink' }}">
                {{ $label }}
            </a>
        @endforeach
    </div>

    {{-- Role filter. Segmented rather than more tabs, because it narrows
         whichever status tab is open instead of replacing it. --}}
    <div class="inline-flex rounded-xl border border-line bg-white p-1">
        @foreach (['all' => ['Everyone', null], 'technician' => ['Technicians', 'technician'], 'client' => ['Clients', 'client']] as $key => [$label, $icon])
            @php
                $on = $role === $key;
                $tint = match ($key) {
                    'technician' => 'bg-brand text-white',
                    'client' => 'bg-accent text-white',
                    default => 'bg-navy text-white',
                };
            @endphp
            <a href="{{ route('verifications.index', ['status' => $status, 'role' => $key]) }}"
               class="inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-bold transition
                      {{ $on ? $tint : 'text-ink-muted hover:text-ink' }}">
                @if ($icon)
                    @include('partials.icon', ['name' => $icon, 'class' => 'h-3.5 w-3.5'])
                @endif
                {{ $label }}
                <span class="rounded-full px-1.5 text-[10px] {{ $on ? 'bg-white/25' : 'bg-canvas' }}">{{ $roleCounts[$key] }}</span>
            </a>
        @endforeach
    </div>
</div>

<div class="overflow-hidden rounded-2xl border border-line bg-white shadow-sm">
    <div class="overflow-x-auto">
        <table class="w-full min-w-[860px] text-left">
            <thead class="border-b border-line bg-canvas/60">
                <tr class="text-[11px] font-bold uppercase tracking-wider text-ink-muted">
                    <th class="px-5 py-3">Applicant</th>
                    <th class="px-5 py-3">Role</th>
                    <th class="px-5 py-3">Attempt</th>
                    <th class="px-5 py-3">Submitted</th>
                    <th class="px-5 py-3">Status</th>
                    <th class="px-5 py-3"></th>
                </tr>
            </thead>
            <tbody>
                @forelse ($rows as $row)
                    @php
                        $attempt = (int) ($row['attempt_number'] ?? 1);
                        $waiting = \Carbon\Carbon::parse($row['submitted_at']);
                        // Anything sitting more than a day is called out. The
                        // promise made to applicants in the app is "usually
                        // less than a day", so this is the line where the
                        // console starts contradicting the product.
                        $stale = $row['status'] === 'pending' && $waiting->diffInHours(now()) >= 24;
                    @endphp
                    <tr class="border-b border-line last:border-0 hover:bg-canvas/60">
                        <td class="px-5 py-3.5">
                            <div class="flex items-center gap-3">
                                {{-- Avatar tinted by role: blue technician, orange
                                     client - the colours the app uses for them. --}}
                                <div class="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-xs font-bold
                                            {{ $row['role'] === 'client' ? 'bg-accent-soft text-accent' : 'bg-brand-soft text-brand' }}">
                                    {{ strtoupper(mb_substr($row['full_name'] ?: '?', 0, 1)) }}
                                </div>
                                <div class="min-w-0">
                                    <div class="truncate text-sm font-bold">{{ $row['full_name'] ?: 'Unnamed applicant' }}</div>
                                    <div class="truncate text-[11px] text-ink-muted">{{ $row['email'] ?? '' }}</div>
                                </div>
                            </div>
                        </td>
                        <td class="px-5 py-3.5">
                            <span class="inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[11px] font-bold
                                         {{ $row['role'] === 'client' ? 'bg-accent-soft text-accent' : 'bg-brand-soft text-brand' }}">
                                @include('partials.icon', ['name' => $row['role'] === 'client' ? 'client' : 'technician', 'class' => 'h-3.5 w-3.5'])
                                {{ $row['role'] === 'client' ? 'Client' : 'Technician' }}
                            </span>
                        </td>
                        <td class="px-5 py-3.5">
                            @if ($attempt > 1)
                                <span class="inline-flex items-center rounded-full bg-warn-soft px-2.5 py-1 text-[11px] font-bold text-warn"
                                      title="This person has been rejected before">
                                    #{{ $attempt }}
                                </span>
                            @else
                                <span class="text-xs text-ink-muted">First</span>
                            @endif
                        </td>
                        <td class="px-5 py-3.5">
                            <div class="text-xs font-semibold {{ $stale ? 'text-bad' : 'text-ink' }}">
                                {{ $waiting->diffForHumans() }}
                            </div>
                            <div class="text-[11px] text-ink-muted">{{ $waiting->format('d M, H:i') }}</div>
                        </td>
                        <td class="px-5 py-3.5">@include('partials.badge', ['value' => $row['status']])</td>
                        <td class="px-5 py-3.5 text-right">
                            <a href="{{ route('verifications.show', $row['verification_id']) }}"
                               class="rounded-lg bg-brand px-3.5 py-2 text-[11px] font-bold text-white transition hover:bg-brand-dark">
                                {{ $row['status'] === 'pending' ? 'Review' : 'View' }}
                            </a>
                        </td>
                    </tr>
                @empty
                    <tr>
                        <td colspan="6" class="px-5 py-14 text-center">
                            <p class="text-sm font-bold text-ink">Nothing here</p>
                            <p class="mt-1 text-xs text-ink-muted">
                                No {{ $status === 'all' ? '' : $status }}
                                {{ $role === 'all' ? '' : $role }} submissions.
                            </p>
                        </td>
                    </tr>
                @endforelse
            </tbody>
        </table>
    </div>
</div>

@endsection
