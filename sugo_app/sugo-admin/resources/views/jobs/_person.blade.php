@php
    /**
     * A person on a job: picture (or initial), name, one line of context.
     *
     * @var string|null $name
     * @var string|null $avatar
     * @var string|null $sub
     * @var string      $tone   'brand' for technicians, 'accent' for clients -
     *                          the same colours their role badges use, so the
     *                          two columns are told apart before being read.
     * @var bool        $warn   Amber sub-line, e.g. a request not yet accepted.
     */
    $display = trim((string) ($name ?? '')) !== '' ? $name : 'Unnamed';
    $initial = strtoupper(mb_substr($display, 0, 1));
    $tint = ($tone ?? 'brand') === 'accent' ? 'bg-accent-soft text-accent' : 'bg-brand-soft text-brand';
    $size = $size ?? 'h-9 w-9';
@endphp
<div class="flex min-w-0 items-center gap-3">
    @if (! empty($avatar))
        <img src="{{ $avatar }}" alt="" class="{{ $size }} shrink-0 rounded-full object-cover ring-2 ring-white">
    @else
        <div class="flex {{ $size }} shrink-0 items-center justify-center rounded-full text-xs font-bold {{ $tint }}">{{ $initial }}</div>
    @endif
    <div class="min-w-0">
        <div class="truncate text-sm font-bold">{{ $display }}</div>
        @if (! empty($sub))
            <div class="truncate text-[11px] {{ ! empty($warn) ? 'font-semibold text-warn' : 'text-ink-muted' }}">{{ $sub }}</div>
        @endif
    </div>
</div>
