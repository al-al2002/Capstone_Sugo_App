<?php

namespace App\Support;

/**
 * Where a job has got to, in a form the jobs pages can draw.
 *
 * The database stores two separate facts about progress: `jobs.status` - the
 * booking's lifecycle - and, for shop pickups only, `job_tracking.stage` -
 * where the physical unit is. Neither alone answers "how far along is this
 * repair?", which is what an admin looking at the jobs list actually wants.
 * This folds them into one five-step timeline and one percentage.
 *
 * It lives in PHP rather than in the `admin_jobs` view so the steps can be
 * relabelled, or the weighting changed, without a database migration - the
 * view returns the raw facts, and presentation is decided here.
 */
final class JobProgress
{
    /** The lifecycle, in order. Keys are `jobs.status` values. */
    public const STEPS = [
        'pending'     => 'Posted',
        'matched'     => 'Matched',
        'confirmed'   => 'Accepted',
        'in_progress' => 'In progress',
        'completed'   => 'Completed',
    ];

    /** Pickup journey, in order, as written by the technician's app. */
    private const STAGES = [
        'heading_to_pickup'    => 'Heading to pick up',
        'collected'            => 'Unit collected',
        'returning_to_shop'    => 'Heading to the shop',
        'in_repair'            => 'Being repaired',
        'out_for_delivery'     => 'Out for delivery',
        'ready_for_collection' => 'Ready for collection',
        'delivered'            => 'Delivered',
    ];

    /**
     * @param  array<string,mixed>  $job  A row of `admin_jobs`.
     * @return array{
     *     steps: list<array{key:string,label:string,state:string}>,
     *     percent: int,
     *     label: string,
     *     cancelled: bool,
     *     stage: ?string
     * }
     */
    public static function for(array $job): array
    {
        $status = (string) ($job['status'] ?? 'pending');
        $stage = $job['tracking_stage'] ?? null;
        $cancelled = $status === 'cancelled';

        $keys = array_keys(self::STEPS);
        $current = array_search($status, $keys, true);
        if ($current === false) {
            $current = 0;
        }

        $steps = [];
        foreach (self::STEPS as $key => $label) {
            $index = array_search($key, $keys, true);
            $state = match (true) {
                $cancelled => 'todo',
                $status === 'completed', $index < $current => 'done',
                $index === $current => 'current',
                default => 'todo',
            };

            // The "In progress" step names the pickup stage when there is one,
            // so the timeline says "Being repaired" rather than a generic word.
            if ($key === 'in_progress' && $stage !== null && isset(self::STAGES[$stage])) {
                $label = self::STAGES[$stage];
            }

            $steps[] = ['key' => $key, 'label' => $label, 'state' => $state];
        }

        return [
            'steps' => $steps,
            'percent' => self::percent($status, $stage),
            'label' => $cancelled
                ? 'Cancelled'
                : ($status === 'in_progress' && $stage !== null && isset(self::STAGES[$stage])
                    ? self::STAGES[$stage]
                    : self::STEPS[$status] ?? ucfirst($status)),
            'cancelled' => $cancelled,
            'stage' => $stage !== null ? (self::STAGES[$stage] ?? null) : null,
        ];
    }

    /**
     * 0-100. Each lifecycle step is worth a share; a pickup job's travel
     * stages then fill the "in progress" share gradually, so a unit on the
     * bench shows further along than one still on the road to collection.
     */
    private static function percent(string $status, ?string $stage): int
    {
        return match ($status) {
            'cancelled' => 0,
            'pending' => 10,
            'matched' => 25,
            'confirmed' => 45,
            'completed' => 100,
            'in_progress' => (function () use ($stage): int {
                $order = array_keys(self::STAGES);
                $at = $stage !== null ? array_search($stage, $order, true) : false;

                // An on-site repair has no stages: it is simply underway.
                if ($at === false) {
                    return 70;
                }

                return (int) round(55 + (($at + 1) / count($order)) * 40);
            })(),
            default => 0,
        };
    }

    /** "laptop_screen_broken" -> "Screen broken". */
    public static function symptom(?string $code): string
    {
        if ($code === null || $code === '') {
            return 'Unspecified issue';
        }

        // Catalog codes lead with the device ("laptop_...", "cctv_..."), which
        // the device column already says. Strip it so the label is the fault.
        $clean = preg_replace('/^(laptop|phone|appliance|network|cctv|printer|router)_/', '', $code) ?? $code;

        return ucfirst(str_replace('_', ' ', $clean));
    }

    /** Device wire value to a display name. */
    public static function device(?string $wire): string
    {
        return match ($wire) {
            'laptop' => 'Laptop / PC',
            'phone' => 'Phone / Tablet',
            'appliance' => 'Appliance',
            'network' => 'Network / CCTV',
            default => ucfirst((string) $wire),
        };
    }

    /** A short, quotable job reference, matching the app's `Job.reference`. */
    public static function reference(string $id): string
    {
        return '#'.strtoupper(substr(str_replace('-', '', $id), 0, 6));
    }
}
