@php
    /**
     * A technician's work type as two pills - Home Service and Shop Repair -
     * lit for the ones they take (2026-11-17).
     *
     * Usage: @include('partials.work-type', ['tech' => $row, 'compact' => true])
     *
     * @var array<string,mixed>|null $tech     A `technicians` row (or null).
     * @var bool                     $compact  Short labels, for table cells.
     */
    $work = \App\Support\WorkType::of($tech ?? null);
    $compact = $compact ?? false;
    $pills = [
        ['on' => $work['home'] ?? false, 'icon' => 'home', 'label' => $compact ? 'Home' : 'Home Service',
         'lit' => 'border-brand/30 bg-brand-soft text-brand'],
        ['on' => $work['shop'] ?? false, 'icon' => 'store', 'label' => $compact ? 'Shop' : 'Shop Repair',
         'lit' => 'border-accent/30 bg-accent-soft text-accent'],
    ];
@endphp
@if ($work === null)
    <span class="text-xs text-ink-muted">Not set</span>
@else
    <span class="inline-flex flex-wrap items-center gap-1.5"
          title="{{ \App\Support\WorkType::label($tech ?? null) }}">
        @foreach ($pills as $pill)
            <span class="inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[11px] font-bold
                         {{ $pill['on'] ? $pill['lit'] : 'border-line bg-canvas text-ink-muted/60 line-through decoration-1' }}">
                @include('partials.icon', ['name' => $pill['icon'], 'class' => 'h-3 w-3', 'stroke' => 2.2])
                {{ $pill['label'] }}
            </span>
        @endforeach
    </span>
@endif
