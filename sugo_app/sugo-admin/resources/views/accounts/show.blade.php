@extends('layouts.app')

@section('title', $account['full_name'] ?: 'Account')
@section('subtitle', Str::title($role).' · '.($account['email'] ?? ''))

@section('actions')
    <a href="{{ route('accounts.index', $role) }}"
       class="rounded-xl border border-line px-4 py-2 text-xs font-bold text-ink-muted transition hover:text-ink">
        Back
    </a>
@endsection

@section('content')

<div class="grid gap-6 xl:grid-cols-[380px_1fr]">

    {{-- Profile --}}
    <div class="space-y-6">
        <section class="rounded-2xl border border-line bg-white p-5">
            <div class="mb-5 flex items-center gap-4">
                <div class="flex h-14 w-14 items-center justify-center rounded-full bg-brand-soft text-lg font-extrabold text-brand">
                    {{ strtoupper(substr($account['full_name'] ?? '?', 0, 1)) }}
                </div>
                <div class="min-w-0">
                    <div class="truncate text-base font-extrabold text-navy">{{ $account['full_name'] ?: 'Unnamed' }}</div>
                    <div class="truncate text-xs text-ink-muted">{{ $account['email'] ?? '' }}</div>
                </div>
            </div>

            <dl class="space-y-3">
                <div class="flex items-center justify-between gap-4">
                    <dt class="text-[11px] font-bold uppercase tracking-wider text-ink-muted">Account</dt>
                    <dd>@include('partials.badge', ['value' => $account['registration_status']])</dd>
                </div>
                <div class="flex items-center justify-between gap-4">
                    <dt class="text-[11px] font-bold uppercase tracking-wider text-ink-muted">Phone</dt>
                    <dd class="text-xs font-semibold">{{ $account['phone'] ?: '—' }}</dd>
                </div>
                <div class="flex items-center justify-between gap-4">
                    <dt class="text-[11px] font-bold uppercase tracking-wider text-ink-muted">Joined</dt>
                    <dd class="text-xs font-semibold">{{ \Carbon\Carbon::parse($account['created_at'])->format('d M Y') }}</dd>
                </div>
                @if (! empty($account['registration_step']))
                    <div class="flex items-center justify-between gap-4">
                        <dt class="text-[11px] font-bold uppercase tracking-wider text-ink-muted">Last step</dt>
                        <dd class="text-xs font-semibold">{{ Str::headline($account['registration_step']) }}</dd>
                    </div>
                @endif

                @if ($role === 'technician')
                    <div class="flex items-center justify-between gap-4">
                        <dt class="text-[11px] font-bold uppercase tracking-wider text-ink-muted">Cleared to work</dt>
                        <dd class="text-xs font-bold {{ ($account['technician_verified'] ?? false) ? 'text-ok' : 'text-ink-muted' }}">
                            {{ ($account['technician_verified'] ?? false) ? 'Yes' : 'Not yet' }}
                        </dd>
                    </div>
                    <div class="flex items-center justify-between gap-4">
                        <dt class="text-[11px] font-bold uppercase tracking-wider text-ink-muted">Verification tier</dt>
                        <dd>@include('partials.badge', ['value' => $account['verification_tier'] ?? 'basic'])</dd>
                    </div>
                    <div class="flex items-center justify-between gap-4">
                        <dt class="text-[11px] font-bold uppercase tracking-wider text-ink-muted">Service radius</dt>
                        <dd class="text-xs font-semibold">
                            {{ $account['service_radius_km'] ? $account['service_radius_km'].' km' : '—' }}
                        </dd>
                    </div>
                @else
                    <div class="flex items-center justify-between gap-4">
                        <dt class="text-[11px] font-bold uppercase tracking-wider text-ink-muted">Trust level</dt>
                        <dd>@include('partials.badge', ['value' => $account['trust_level'] ?? 'new'])</dd>
                    </div>
                    <div class="flex items-center justify-between gap-4">
                        <dt class="text-[11px] font-bold uppercase tracking-wider text-ink-muted">Phone verified</dt>
                        <dd class="text-xs font-bold {{ ($account['phone_verified'] ?? false) ? 'text-ok' : 'text-ink-muted' }}">
                            {{ ($account['phone_verified'] ?? false) ? 'Yes' : 'No' }}
                        </dd>
                    </div>
                    <div class="flex items-center justify-between gap-4">
                        <dt class="text-[11px] font-bold uppercase tracking-wider text-ink-muted">No-shows</dt>
                        <dd class="text-xs font-semibold">{{ $account['no_show_count'] ?? 0 }}</dd>
                    </div>
                @endif
            </dl>
        </section>

        {{-- Why the console cannot edit these --}}
        <p class="rounded-xl border border-line bg-white px-4 py-3 text-[11px] leading-relaxed text-ink-muted">
            These values are read-only here. Activation, verification tier and trust
            level are consequences of a review decision and are set by database
            functions that enforce the conditions — an editable field would be a way
            around them.
        </p>
    </div>

    {{-- Detail --}}
    <div class="space-y-6">

        {{-- Verifications --}}
        <section class="rounded-2xl border border-line bg-white">
            <header class="border-b border-line px-5 py-4">
                <h2 class="text-sm font-extrabold text-navy">ID submissions</h2>
            </header>
            @forelse ($verifications as $v)
                <div class="flex items-center gap-4 border-b border-line px-5 py-3.5 last:border-0">
                    <div class="min-w-0 flex-1">
                        <div class="text-xs font-bold">
                            {{ \Carbon\Carbon::parse($v['submitted_at'])->format('d M Y, H:i') }}
                        </div>
                        @if (! empty($v['admin_notes']))
                            <div class="mt-1 truncate text-[11px] italic text-ink-muted">“{{ $v['admin_notes'] }}”</div>
                        @endif
                    </div>
                    @include('partials.badge', ['value' => $v['status']])
                    <a href="{{ route('verifications.show', $v['verification_id']) }}"
                       class="text-[11px] font-bold text-brand hover:underline">Open</a>
                </div>
            @empty
                <p class="px-5 py-8 text-center text-xs text-ink-muted">No ID submitted yet.</p>
            @endforelse
        </section>

        @if ($role === 'technician')
            <section class="rounded-2xl border border-line bg-white">
                <header class="border-b border-line px-5 py-4">
                    <h2 class="text-sm font-extrabold text-navy">Specialisations</h2>
                    <p class="text-[11px] text-ink-muted">A tick means the assessment for that brand was passed</p>
                </header>
                @forelse ($specializations as $spec)
                    <div class="flex items-center gap-4 border-b border-line px-5 py-3 last:border-0">
                        <div class="flex-1 text-xs font-semibold">
                            {{ Str::headline($spec['device_type']) }} · {{ $spec['brand'] }}
                        </div>
                        @if ($spec['skill_level'])
                            @include('partials.badge', ['value' => $spec['skill_level']])
                        @else
                            <span class="text-[11px] text-ink-muted">Not assessed</span>
                        @endif
                        <span class="w-6 text-right text-sm {{ $spec['verified'] ? 'text-ok' : 'text-line' }}">
                            {{ $spec['verified'] ? '✓' : '—' }}
                        </span>
                    </div>
                @empty
                    <p class="px-5 py-8 text-center text-xs text-ink-muted">None declared yet.</p>
                @endforelse
            </section>

            <section class="rounded-2xl border border-line bg-white">
                <header class="flex items-center justify-between border-b border-line px-5 py-4">
                    <div>
                        <h2 class="text-sm font-extrabold text-navy">Credentials</h2>
                        <p class="text-[11px] text-ink-muted">
                            Optional — these never gate the account, and are decided
                            with the ID on the review screen
                        </p>
                    </div>

                </header>
                @forelse ($documents as $doc)
                    <div class="flex items-center gap-4 border-b border-line px-5 py-3 last:border-0">
                        <div class="flex-1 text-xs font-semibold">{{ Str::headline($doc['doc_type']) }}</div>
                        <div class="text-[11px] text-ink-muted">
                            {{ \Carbon\Carbon::parse($doc['uploaded_at'])->format('d M Y') }}
                        </div>
                        @include('partials.badge', ['value' => $doc['status']])
                    </div>
                @empty
                    <p class="px-5 py-8 text-center text-xs text-ink-muted">No credentials uploaded.</p>
                @endforelse
            </section>
        @else
            <section class="rounded-2xl border border-line bg-white">
                <header class="border-b border-line px-5 py-4">
                    <h2 class="text-sm font-extrabold text-navy">Saved addresses</h2>
                </header>
                @forelse ($addresses as $address)
                    <div class="flex items-start gap-4 border-b border-line px-5 py-3.5 last:border-0">
                        <div class="min-w-0 flex-1">
                            <div class="text-xs font-bold">
                                {{ $address['label'] }}
                                @if ($address['is_default'])
                                    <span class="ml-1 rounded bg-brand-soft px-1.5 py-0.5 text-[10px] text-brand">Default</span>
                                @endif
                            </div>
                            <div class="mt-0.5 text-[11px] leading-relaxed text-ink-muted">{{ $address['address_text'] }}</div>
                        </div>
                        <div class="shrink-0 text-[11px] tabular-nums text-ink-muted">
                            {{ number_format((float) $address['latitude'], 4) }},
                            {{ number_format((float) $address['longitude'], 4) }}
                        </div>
                    </div>
                @empty
                    <p class="px-5 py-8 text-center text-xs text-ink-muted">No address saved yet.</p>
                @endforelse
            </section>
        @endif
    </div>
</div>

@endsection
