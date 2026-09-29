@extends('layouts.app')

@section('title', ($verification['role'] ?? null) === 'client' ? 'Review client' : 'Review technician')
@section('subtitle', $verification['full_name'] ?: 'Unnamed applicant')

@section('actions')
    <a href="{{ route('verifications.index') }}"
       class="rounded-xl border border-line px-4 py-2 text-xs font-bold text-ink-muted transition hover:text-ink">
        Back to queue
    </a>
@endsection

@section('content')

@php
    $isPending = $verification['status'] === 'pending';
    $attempt = (int) ($verification['attempt_number'] ?? 1);
    $priorRejections = collect($history)->where('status', 'rejected')->count();
    $pendingDocs = collect($documents)->where('status', 'pending');
    $isTechnician = ($verification['role'] ?? null) === 'technician';
    $name = $verification['full_name'] ?: 'Unnamed applicant';
@endphp

{{-- Who this is, before what they sent. Clients and technicians are held to
     different bars - a technician also brings credentials and, once cleared,
     is sent into strangers' homes - so the role leads the page instead of
     sitting as a small badge in the sidebar. --}}
<section class="mb-5 overflow-hidden rounded-2xl border bg-white shadow-sm {{ $isTechnician ? 'border-brand/25' : 'border-accent/30' }}">
    <div class="h-1.5 {{ $isTechnician ? 'bg-brand' : 'bg-accent' }}"></div>
    <div class="flex flex-wrap items-center gap-5 p-5">
        <div class="flex h-14 w-14 shrink-0 items-center justify-center rounded-2xl text-xl font-extrabold
                    {{ $isTechnician ? 'bg-brand-soft text-brand' : 'bg-accent-soft text-accent' }}">
            {{ strtoupper(mb_substr($name, 0, 1)) }}
        </div>

        <div class="min-w-0 flex-1">
            <span class="mb-1.5 inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-[11px] font-extrabold uppercase tracking-wider
                         {{ $isTechnician ? 'bg-brand text-white' : 'bg-accent text-white' }}">
                @include('partials.icon', ['name' => $isTechnician ? 'technician' : 'client', 'class' => 'h-3.5 w-3.5', 'stroke' => 2.5])
                {{ $isTechnician ? 'Technician applicant' : 'Client applicant' }}
            </span>
            <h2 class="truncate text-lg font-extrabold text-navy">{{ $name }}</h2>
            <p class="truncate text-xs text-ink-muted">
                {{ $verification['email'] ?? '' }}
                · submitted {{ \Carbon\Carbon::parse($verification['submitted_at'])->diffForHumans() }}
            </p>
        </div>

        <div class="grid w-full grid-cols-3 gap-2 sm:w-auto">
            <div class="rounded-xl bg-canvas px-3 py-2 text-center">
                <div class="text-[10px] font-bold uppercase tracking-wider text-ink-muted">Attempt</div>
                <div class="text-sm font-extrabold text-navy">#{{ $attempt }}</div>
            </div>
            <div class="rounded-xl bg-canvas px-3 py-2 text-center">
                <div class="text-[10px] font-bold uppercase tracking-wider text-ink-muted">To check</div>
                <div class="text-sm font-extrabold text-navy">
                    {{ $isTechnician ? 'ID + '.count($documents) : 'ID only' }}
                </div>
            </div>
            <div class="flex flex-col items-center justify-center rounded-xl bg-canvas px-3 py-2">
                <div class="mb-1 text-[10px] font-bold uppercase tracking-wider text-ink-muted">Status</div>
                @include('partials.badge', ['value' => $verification['status']])
            </div>
        </div>
    </div>
    <p class="border-t border-line bg-canvas/50 px-5 py-2.5 text-[11px] leading-relaxed text-ink-muted">
        @if ($isTechnician)
            Approving lets this person <span class="font-bold text-ink">accept repair jobs</span> once registration is finished,
            and approves any credentials attached below.
        @else
            Approving lets this person <span class="font-bold text-ink">book technicians</span> once registration is finished.
        @endif
    </p>
</section>

@if ($attempt > 1)
    <div class="mb-5 rounded-2xl border border-warn/25 bg-warn-soft px-5 py-4">
        <p class="text-sm font-extrabold text-ink">
            Attempt #{{ $attempt }} — {{ $priorRejections }} previous {{ Str::plural('rejection', $priorRejections) }}
        </p>
        <p class="mt-1 text-xs leading-relaxed text-ink-muted">
            Check the reasons below before deciding. If the same fault is still
            present, say so in the same words so they know what to change.
        </p>
    </div>
@endif

<div class="grid gap-6 xl:grid-cols-[1fr_380px]">

    {{-- Everything being judged --}}
    <div class="space-y-6">

        {{-- The identity photos --}}
        <section class="rounded-2xl border border-line bg-white p-5">
            <div class="mb-4">
                <h2 class="text-sm font-extrabold text-navy">1. Identity</h2>
                <p class="text-[11px] leading-relaxed text-ink-muted">
                    The ID proves a document exists. The selfie ties that document to
                    the person holding it. Approve only if the face matches and the ID
                    in the selfie is the same one.
                </p>
            </div>

            <div class="grid gap-4 md:grid-cols-2">
                @foreach ([['Government ID', $idUrl], ['Selfie holding the ID', $selfieUrl]] as [$caption, $url])
                    <figure>
                        <figcaption class="mb-2 text-[11px] font-bold uppercase tracking-wider text-ink-muted">{{ $caption }}</figcaption>
                        @if ($url)
                            {{-- Opens full size in a new tab: detail on an ID is
                                 often unreadable at card size. --}}
                            <a href="{{ $url }}" target="_blank" rel="noopener"
                               class="group relative block overflow-hidden rounded-xl border border-line bg-canvas">
                                <img src="{{ $url }}" alt="{{ $caption }}"
                                     class="h-72 w-full bg-white object-contain">
                                <span class="absolute bottom-2 right-2 rounded-lg bg-navy/80 px-2 py-1 text-[10px] font-bold text-white opacity-0 transition group-hover:opacity-100">
                                    Open full size
                                </span>
                            </a>
                        @else
                            <div class="flex h-72 items-center justify-center rounded-xl border border-dashed border-line bg-canvas px-6 text-center">
                                <div>
                                    <p class="text-xs font-bold text-bad">Image unavailable</p>
                                    <p class="mt-1 text-[11px] leading-relaxed text-ink-muted">
                                        The signed URL could not be created. Do not approve
                                        a submission you cannot see.
                                    </p>
                                </div>
                            </div>
                        @endif
                    </figure>
                @endforeach
            </div>

            <p class="mt-4 rounded-xl bg-canvas px-4 py-3 text-[11px] leading-relaxed text-ink-muted">
                These links are signed and expire in
                {{ (int) (config('supabase.signed_url_ttl') / 60) }} minutes. The bucket
                is private, so an identity document is never reachable from a
                guessable URL. Reload the page if an image stops loading.
            </p>
        </section>

        {{--
            Credentials, on the same screen and in the same decision.

            These used to live on a separate `/documents` page, so reviewing a
            technician meant approving the ID, remembering there were credentials
            attached, and navigating away to find them. Two queues for one person.
        --}}
        @if (count($documents) > 0)
            <section class="rounded-2xl border border-line bg-white p-5">
                <div class="mb-4 flex items-start justify-between gap-4">
                    <div>
                        <h2 class="text-sm font-extrabold text-navy">2. Credentials</h2>
                        <p class="text-[11px] leading-relaxed text-ink-muted">
                            The NBI or police clearance is required — a technician cannot
                            submit without one, because clients let them into their homes.
                            Certificates and portfolio photos are optional. There is
                            nothing to click here: the single decision below covers these
                            as well as the ID, so a blurred or wrong clearance is a reason
                            to reject the whole submission.
                        </p>
                    </div>
                    @if ($pendingDocs->count() > 0)
                        <span class="shrink-0 rounded-full bg-warn-soft px-2.5 py-1 text-[11px] font-bold text-warn">
                            {{ $pendingDocs->count() }} to review
                        </span>
                    @endif
                </div>

                <div class="grid gap-4 sm:grid-cols-2">
                    @foreach ($documents as $doc)
                        <article class="overflow-hidden rounded-xl border border-line">
                            @if ($doc['preview_url'] ?? null)
                                <a href="{{ $doc['preview_url'] }}" target="_blank" rel="noopener"
                                   class="block border-b border-line bg-canvas">
                                    <img src="{{ $doc['preview_url'] }}" alt="{{ $doc['doc_type'] }}"
                                         class="h-40 w-full bg-white object-contain">
                                </a>
                            @else
                                <div class="flex h-40 items-center justify-center border-b border-line bg-canvas px-4 text-center">
                                    <p class="text-[11px] leading-relaxed text-ink-muted">
                                        Preview unavailable.<br>May be a PDF, or the link could not be signed.
                                    </p>
                                </div>
                            @endif

                            <div class="p-3">
                                <div class="mb-2 flex items-start justify-between gap-2">
                                    <h3 class="truncate text-xs font-extrabold text-navy">
                                        {{ Str::headline($doc['doc_type']) }}
                                    </h3>
                                    @include('partials.badge', ['value' => $doc['status']])
                                </div>

                                @if (! empty($doc['caption']))
                                    <p class="mb-2 text-[11px] italic text-ink-muted">"{{ $doc['caption'] }}"</p>
                                @endif

                                @if (! empty($doc['admin_notes']))
                                    <p class="rounded-lg bg-canvas px-2 py-1.5 text-[11px] italic text-ink">
                                        "{{ $doc['admin_notes'] }}"
                                    </p>
                                @endif
                            </div>
                        </article>
                    @endforeach
                </div>
            </section>
        @endif

        {{-- History --}}
        @if (count($history) > 1)
            <section class="rounded-2xl border border-line bg-white">
                <header class="border-b border-line px-5 py-4">
                    <h2 class="text-sm font-extrabold text-navy">Previous attempts</h2>
                </header>
                @foreach ($history as $past)
                    @if ($past['verification_id'] !== $verification['verification_id'])
                        <div class="border-b border-line px-5 py-3.5 last:border-0">
                            <div class="flex items-center justify-between gap-3">
                                <div class="text-[11px] text-ink-muted">
                                    {{ \Carbon\Carbon::parse($past['submitted_at'])->format('d M Y, H:i') }}
                                    @if (! empty($past['reviewed_by_name']))
                                        · reviewed by {{ $past['reviewed_by_name'] }}
                                    @endif
                                </div>
                                @include('partials.badge', ['value' => $past['status']])
                            </div>
                            @if (! empty($past['admin_notes']))
                                <p class="mt-2 rounded-lg bg-canvas px-3 py-2 text-xs italic text-ink">
                                    "{{ $past['admin_notes'] }}"
                                </p>
                            @endif
                        </div>
                    @endif
                @endforeach
            </section>
        @endif
    </div>

    {{-- Sidebar --}}
    <div class="space-y-6">

        {{-- Applicant --}}
        <section class="rounded-2xl border border-line bg-white p-5">
            <h2 class="mb-4 text-sm font-extrabold text-navy">Applicant</h2>

            @php
                $rows = [
                    'Name' => $verification['full_name'] ?: '—',
                    'Email' => $verification['email'] ?? '—',
                    'Phone' => $verification['phone'] ?: '—',
                    'Submitted' => \Carbon\Carbon::parse($verification['submitted_at'])->format('d M Y, H:i'),
                ];
            @endphp

            <dl class="space-y-3">
                @foreach ($rows as $label => $value)
                    <div class="flex items-start justify-between gap-4">
                        <dt class="text-[11px] font-bold uppercase tracking-wider text-ink-muted">{{ $label }}</dt>
                        <dd class="text-right text-xs font-semibold">{{ $value }}</dd>
                    </div>
                @endforeach
                <div class="flex items-center justify-between gap-4">
                    <dt class="text-[11px] font-bold uppercase tracking-wider text-ink-muted">Role</dt>
                    <dd>@include('partials.badge', ['value' => $verification['role']])</dd>
                </div>
                <div class="flex items-center justify-between gap-4">
                    <dt class="text-[11px] font-bold uppercase tracking-wider text-ink-muted">Account</dt>
                    <dd>@include('partials.badge', ['value' => $verification['registration_status']])</dd>
                </div>
            </dl>

            @if (! empty($verification['user_id']))
                <a href="{{ route('accounts.show', [$verification['role'], $verification['user_id']]) }}"
                   class="mt-4 block rounded-xl border border-line px-4 py-2 text-center text-xs font-bold text-brand transition hover:bg-brand-softer">
                    Open full account
                </a>
            @endif
        </section>

        {{-- Technician context --}}
        @if ($verification['role'] === 'technician' && $specializations !== [])
            <section class="rounded-2xl border border-line bg-white p-5">
                <h2 class="mb-1 text-sm font-extrabold text-navy">What they claim to fix</h2>
                <p class="mb-4 text-[11px] leading-relaxed text-ink-muted">
                    Context only — this is not what you are judging. A long list with
                    nothing passed is worth a second look at the ID.
                </p>
                <div class="flex flex-wrap gap-1.5">
                    @foreach ($specializations as $spec)
                        <span class="inline-flex items-center gap-1 rounded-full border px-2.5 py-1 text-[11px] font-semibold
                                     {{ $spec['verified'] ? 'border-ok/30 bg-ok-soft text-ok' : 'border-line bg-canvas text-ink-muted' }}">
                            {{ Str::headline($spec['device_type']) }} · {{ $spec['brand'] }}
                            @if ($spec['verified'])
                                <span class="font-bold">✓</span>
                            @endif
                        </span>
                    @endforeach
                </div>
            </section>
        @endif

        {{-- One decision, covering both --}}
        <section class="rounded-2xl border border-line bg-white p-5">
            <h2 class="mb-1 text-sm font-extrabold text-navy">Decision</h2>

            @if ($isPending)
                <p class="mb-4 text-[11px] leading-relaxed text-ink-muted">
                    One decision covers the ID and every credential above.
                    Approving a client whose registration is finished activates them
                    immediately. If they are still mid-flow, their ID is cleared and
                    the account activates when they finish.
                </p>

                @if ($pendingDocs->count() > 0)
                    <p class="mb-4 rounded-xl bg-canvas px-3 py-2 text-[11px] leading-relaxed text-ink-muted">
                        Approving also approves
                        <span class="font-bold text-ink">{{ $pendingDocs->count() }}</span>
                        credential{{ $pendingDocs->count() === 1 ? '' : 's' }}.
                        Rejecting leaves them pending, so the applicant keeps their
                        uploads and only has to fix what you name below.
                    </p>
                @endif

                <form id="review-form" method="POST"
                      action="{{ route('verifications.update', $verification['verification_id']) }}"
                      class="space-y-4">
                    @csrf

                    <div>
                        <label for="notes" class="mb-1.5 block text-xs font-bold">
                            Reason <span class="font-normal text-ink-muted">(required to reject)</span>
                        </label>
                        <textarea id="notes" name="notes" rows="4"
                                  class="w-full rounded-xl border border-line bg-white px-3 py-2.5 text-xs outline-none transition focus:border-brand focus:ring-2 focus:ring-brand/20"
                                  placeholder="e.g. The ID in your selfie is not readable. Please retake it in better light.">{{ old('notes') }}</textarea>
                        <p class="mt-1.5 text-[11px] leading-relaxed text-ink-muted">
                            Shown to the applicant word for word, and reused as the note
                            on any credential you reject. Write what they should change.
                        </p>
                    </div>

                    <div class="grid grid-cols-2 gap-3">
                        <button type="submit" name="decision" value="reject" data-loading-text="Rejecting…"
                                class="rounded-xl border border-bad/30 bg-bad-soft px-4 py-2.5 text-xs font-bold text-bad transition hover:bg-bad hover:text-white">
                            Reject
                        </button>
                        <button type="submit" name="decision" value="approve" data-loading-text="Approving…"
                                onclick="return confirm('Approve this applicant? This is what lets the account trade on SUGO.')"
                                class="rounded-xl bg-ok px-4 py-2.5 text-xs font-bold text-white transition hover:opacity-90">
                            Approve all
                        </button>
                    </div>
                </form>
            @else
                <div class="rounded-xl bg-canvas px-4 py-4">
                    <div class="mb-2 flex items-center justify-between">
                        @include('partials.badge', ['value' => $verification['status']])
                        <span class="text-[11px] text-ink-muted">
                            {{ ! empty($verification['reviewed_at']) ? \Carbon\Carbon::parse($verification['reviewed_at'])->format('d M Y, H:i') : '' }}
                        </span>
                    </div>
                    <p class="text-[11px] text-ink-muted">
                        Reviewed by {{ $verification['reviewed_by_name'] ?? 'system' }}
                    </p>
                    @if (! empty($verification['admin_notes']))
                        <p class="mt-3 border-t border-line pt-3 text-xs italic text-ink">
                            "{{ $verification['admin_notes'] }}"
                        </p>
                    @endif
                </div>

                <p class="mt-3 text-[11px] leading-relaxed text-ink-muted">
                    A decision is final for this attempt. If the applicant submits new
                    photos, they arrive as a new row in the queue.
                </p>
            @endif
        </section>
    </div>
</div>

@endsection
