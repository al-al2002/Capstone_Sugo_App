@php
    /**
     * Inline SVG icons for the console.
     *
     * Inline rather than an icon font or a CDN package, for the same reason the
     * layout uses the Tailwind Play CDN and nothing else: the panel runs with
     * `php artisan serve` and no build step. A handful of 24px outline paths
     * cost less than a single font request and can never fail to load.
     *
     * Usage: @include('partials.icon', ['name' => 'jobs', 'class' => 'h-4 w-4'])
     */
    $paths = [
        'dashboard'   => 'M4 5a1 1 0 011-1h5a1 1 0 011 1v5a1 1 0 01-1 1H5a1 1 0 01-1-1V5zm9 0a1 1 0 011-1h5a1 1 0 011 1v3a1 1 0 01-1 1h-5a1 1 0 01-1-1V5zM4 15a1 1 0 011-1h5a1 1 0 011 1v4a1 1 0 01-1 1H5a1 1 0 01-1-1v-4zm9-3a1 1 0 011-1h5a1 1 0 011 1v7a1 1 0 01-1 1h-5a1 1 0 01-1-1v-7z',
        'jobs'        => 'M9 6V5a2 2 0 012-2h2a2 2 0 012 2v1m-9 0h12a2 2 0 012 2v9a2 2 0 01-2 2H6a2 2 0 01-2-2V8a2 2 0 012-2zm-2 6h16',
        'id'          => 'M10 6H6a2 2 0 00-2 2v9a2 2 0 002 2h12a2 2 0 002-2V8a2 2 0 00-2-2h-4m-4 0V5a2 2 0 114 0v1m-4 0a2 2 0 104 0M9 14a2 2 0 100-4 2 2 0 000 4zm-3 3c.5-1.2 1.6-2 3-2s2.5.8 3 2m3-5h3m-3 3h2',
        'technician'  => 'M14.7 6.3a1 1 0 000 1.4l1.6 1.6a1 1 0 001.4 0l3.8-3.8a6 6 0 01-7.9 7.9l-6.9 6.9a2.1 2.1 0 01-3-3l6.9-6.9a6 6 0 017.9-7.9l-3.8 3.8z',
        'client'      => 'M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z',
        'logout'      => 'M17 16l4-4m0 0l-4-4m4 4H9m4 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1',
        'chart'       => 'M4 19h16M7 16V10m5 6V6m5 10v-4',
        'star'        => 'M12 3.5l2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.9l-5.2 2.7 1-5.8-4.3-4.1 5.9-.9L12 3.5z',
        'check'       => 'M5 13l4 4L19 7',
        'clock'       => 'M12 8v4l3 2m6-2a9 9 0 11-18 0 9 9 0 0118 0z',
        'map'         => 'M9 20l-5.4-2.7A1 1 0 013 16.4V5.6a1 1 0 011.4-.9L9 7m0 13l6-3m-6 3V7m6 10l4.6 2.3a1 1 0 001.4-.9V7.6a1 1 0 00-.6-.9L15 4m0 13V4m0 0L9 7',
        'forum'       => 'M8 10h8M8 14h5m-9 6l2.6-2.6A2 2 0 018 17h10a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v14z',
        'search'      => 'M21 21l-4.3-4.3M17 10.5a6.5 6.5 0 11-13 0 6.5 6.5 0 0113 0z',
        'arrow-right' => 'M9 5l7 7-7 7',
        'arrow-left'  => 'M15 19l-7-7 7-7',
        'menu'        => 'M4 6h16M4 12h16M4 18h16',
        'device'      => 'M4 5a1 1 0 011-1h14a1 1 0 011 1v10a1 1 0 01-1 1H5a1 1 0 01-1-1V5zm4 15h8m-4-4v4',
        'flag'        => 'M5 21V4m0 0h11.5l-2.5 4 2.5 4H5',
        'pin'         =>'M12 21s-7-6.2-7-11.5a7 7 0 1114 0C19 14.8 12 21 12 21zm0-9a2.5 2.5 0 100-5 2.5 2.5 0 000 5z',
    ];
    $d = $paths[$name] ?? $paths['dashboard'];
@endphp
<svg class="{{ $class ?? 'h-4 w-4' }}" fill="none" viewBox="0 0 24 24" stroke="currentColor"
     stroke-width="{{ $stroke ?? 1.8 }}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
    <path d="{{ $d }}"/>
</svg>
