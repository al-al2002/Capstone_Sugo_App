@php
    /**
     * One badge component for every status in the system, so `pending` looks
     * the same on the dashboard, the queue and an account page.
     */
    $map = [
        'pending'        => ['Pending',       'bg-warn-soft text-warn'],
        'pending_review' => ['Pending review', 'bg-warn-soft text-warn'],
        'approved'       => ['Approved',      'bg-ok-soft text-ok'],
        'active'         => ['Active',        'bg-ok-soft text-ok'],
        'rejected'       => ['Rejected',      'bg-bad-soft text-bad'],
        'incomplete'     => ['Incomplete',    'bg-canvas text-ink-muted'],
        'technician'     => ['Technician',    'bg-brand-soft text-brand'],
        'client'         => ['Client',        'bg-accent-soft text-accent'],
        'admin'          => ['Admin',         'bg-navy text-white'],
        'basic'          => ['Basic',         'bg-canvas text-ink-muted'],
        'verified'       => ['Verified',      'bg-brand-soft text-brand'],
        'certified_pro'  => ['Certified Pro', 'bg-ok-soft text-ok'],
        'new'            => ['New',           'bg-canvas text-ink-muted'],
        'trusted'        => ['Trusted',       'bg-ok-soft text-ok'],
        'expert'         => ['Expert',        'bg-ok-soft text-ok'],
        'intermediate'   => ['Intermediate',  'bg-brand-soft text-brand'],
        'beginner'       => ['Beginner',      'bg-canvas text-ink-muted'],

        // Job lifecycle, for the jobs console. Tones follow the app's own
        // status chips: waiting is amber, live work is blue, done is green.
        'matched'        => ['Matched',       'bg-warn-soft text-warn'],
        'confirmed'      => ['Confirmed',     'bg-brand-soft text-brand'],
        'in_progress'    => ['In progress',   'bg-brand-soft text-brand'],
        'completed'      => ['Completed',     'bg-ok-soft text-ok'],
        'cancelled'      => ['Cancelled',     'bg-canvas text-ink-muted'],

        // Service paths.
        'home_service'   => ['Home service',  'bg-brand-soft text-brand'],
        'pickup'         => ['Shop pickup',   'bg-accent-soft text-accent'],
        'it_community'   => ['IT community',  'bg-ok-soft text-ok'],
    ];

    $key = (string) ($value ?? '');
    [$text, $classes] = $map[$key] ?? [ucfirst(str_replace('_', ' ', $key ?: 'unknown')), 'bg-canvas text-ink-muted'];

    // An override is read from `$badgeLabel`, never from `$label`.
    //
    // @include hands a partial every variable of the page that includes it.
    // Pages loop `as $key => $label` for tabs and legends, so a badge that
    // honoured `$label` printed the last tab's name on every badge - "All"
    // on every job, "Cancelled" on every dashboard badge. A name no page
    // uses for anything else cannot be picked up by accident.
    $text = $badgeLabel ?? $text;
@endphp

<span class="inline-flex items-center rounded-full px-2.5 py-1 text-[11px] font-bold {{ $classes }}">
    {{ $text }}
</span>
