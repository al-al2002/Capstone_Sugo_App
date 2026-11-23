<?php

namespace App\Support;

/**
 * Will a technician still travel to a client in the rain, or in heavy
 * traffic? (2026-11-22, migration 20261122000001.)
 *
 * Read from `technicians.rain_travel` ('any' | 'not_heavy' | 'never') and
 * `technicians.heavy_traffic_travel` (bool), which the app asks at the end of
 * the registration "Work type" step and in Edit profile. Matching uses them in
 * "Weather & traffic readiness" while it is raining or the traffic is heavy
 * at the job. Null means "not answered" - every technician registered before
 * the question existed - and is scored as an estimate, exactly as before.
 *
 * The wording matches the app's `RainTravel` / `TrafficTravel` short labels.
 * Read-only here: it is the technician's own answer, not a review decision.
 */
final class TravelConditions
{
    private const RAIN = [
        'any' => 'Even in heavy rain',
        'not_heavy' => 'In rain, not heavy rain',
        'never' => 'Not in the rain',
    ];

    /** "Even in heavy rain", "In rain, not heavy rain", "Not in the rain", "Not answered". */
    public static function rain(?array $row): string
    {
        return self::RAIN[$row['rain_travel'] ?? ''] ?? 'Not answered';
    }

    /** "Goes in heavy traffic", "Avoids heavy traffic", "Not answered". */
    public static function traffic(?array $row): string
    {
        return match ($row['heavy_traffic_travel'] ?? null) {
            true => 'Goes in heavy traffic',
            false => 'Avoids heavy traffic',
            default => 'Not answered',
        };
    }

    /**
     * A text colour class for each answer: ok when they go, warn when they do
     * not, muted when not answered. "In rain, not heavy rain" is neutral.
     *
     * @return array{rain: string, traffic: string}
     */
    public static function tones(?array $row): array
    {
        $rain = match ($row['rain_travel'] ?? null) {
            'any' => 'text-ok',
            'not_heavy' => '',
            'never' => 'text-warn',
            default => 'text-ink-muted',
        };

        $traffic = match ($row['heavy_traffic_travel'] ?? null) {
            true => 'text-ok',
            false => 'text-warn',
            default => 'text-ink-muted',
        };

        return ['rain' => $rain, 'traffic' => $traffic];
    }
}
