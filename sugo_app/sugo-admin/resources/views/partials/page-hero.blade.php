{{--
    The summary strip at the top of an index page (2026-11-17).

    The page title is already in the sticky header, so this does not repeat
    it: it says the one number the page is about ("142 jobs") and a line of
    context, on the same gradient as the dashboard hero - so every page of the
    console opens the same way.

    Usage:
        @include('partials.page-hero', [
            'icon' => 'jobs',            // partials/icon name
            'kicker' => 'All jobs',      // small caps line
            'value' => 142,              // counts up on load
            'label' => 'jobs on SUGO',   // after the number
            'sub' => '12 active now',    // optional
            'tone' => 'brand',           // or 'warn' when something waits on you
            'action' => ['Review the oldest', route(...)], // optional
        ])
--}}
@php
    $tone = $tone ?? 'brand';
    $sub = $sub ?? null;
    $action = $action ?? null;
    $gradient = $tone === 'warn'
        ? 'from-[#7C2D12] via-accent to-accent-light shadow-accent/20'
        : 'from-navy via-[#0A4A9A] to-brand-light shadow-navy/15';
@endphp
<section
    class="sugo-shine-once relative mb-5 overflow-hidden rounded-2xl bg-gradient-to-br {{ $gradient }} px-5 py-4 text-white shadow-lg sm:px-6">
    <div class="pointer-events-none absolute -right-16 -top-20 h-56 w-56 rounded-full border-[22px] border-white/[0.06]"></div>
    <div class="pointer-events-none absolute -bottom-20 right-24 h-40 w-40 rounded-full bg-[#11C5E8]/20 blur-2xl"></div>

    <div class="relative z-10 flex flex-wrap items-center gap-4">
        <span class="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-white/15 ring-1 ring-white/20">
            @include('partials.icon', ['name' => $icon, 'class' => 'h-5 w-5'])
        </span>
        <div class="min-w-0 flex-1">
            <p class="text-[11px] font-bold uppercase tracking-[0.16em] text-white/60">{{ $kicker }}</p>
            <p class="mt-0.5 text-lg font-extrabold leading-tight">
                <span class="tabular-nums" data-count-to="{{ (int) $value }}">{{ number_format((int) $value) }}</span>
                {{ $label }}
            </p>
            @if ($sub)
                <p class="mt-0.5 text-xs text-white/75">{{ $sub }}</p>
            @endif
        </div>
        @if ($action)
            <a href="{{ $action[1] }}"
                class="group inline-flex shrink-0 items-center gap-2 rounded-xl bg-white px-4 py-2.5 text-xs font-extrabold text-navy shadow-lg shadow-black/10 transition hover:-translate-y-0.5 hover:shadow-xl">
                {{ $action[0] }}
                @include('partials.icon', ['name' => 'arrow-right', 'class' => 'h-3.5 w-3.5 transition group-hover:translate-x-0.5'])
            </a>
        @endif
    </div>
</section>
