{{--
    An empty list (2026-11-17): the icon on a soft gradient disc with a halo,
    then the title, then the message - each rising in a beat after the last.

    Usage:
        @include('partials.empty', [
            'icon' => 'jobs',
            'title' => 'No jobs here',
            'message' => 'Nothing matches this filter.',
        ])
--}}
<div class="px-5 py-16 text-center">
    <div class="sugo-rise relative mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-gradient-to-br from-brand-soft to-[#E0F7FC] text-brand">
        <span class="absolute -inset-2 rounded-full bg-brand-soft/40"></span>
        <span class="relative">@include('partials.icon', ['name' => $icon, 'class' => 'h-7 w-7'])</span>
    </div>
    <p class="sugo-rise text-sm font-bold text-ink" style="--d: 90ms">{{ $title }}</p>
    <p class="sugo-rise mt-1 text-xs text-ink-muted" style="--d: 160ms">{{ $message }}</p>
</div>
