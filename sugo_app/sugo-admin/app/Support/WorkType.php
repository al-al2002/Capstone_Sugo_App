<?php

namespace App\Support;

/**
 * The work a technician takes: Home Service, Shop Repair, or both
 * (2026-11-17, migration 20261117000007).
 *
 * Read from `technicians.offers_home_service` / `offers_shop_repair`, which
 * the app writes at registration (the "Work type" step) and from Profile.
 * Matching only offers a technician jobs of a kind they take, so an admin
 * looking at an account should see it at a glance.
 *
 * Read-only here, like every other account fact: it is the technician's own
 * choice, not a review decision.
 */
final class WorkType
{
    /**
     * The two flags, with the database default (both) for a missing one.
     * Null when there is no technician row at all - a registration that has
     * not reached the technician profile yet.
     *
     * @param  array<string,mixed>|null  $row  A `technicians` row.
     * @return array{home: bool, shop: bool}|null
     */
    public static function of(?array $row): ?array
    {
        if ($row === null) {
            return null;
        }

        return [
            'home' => (bool) ($row['offers_home_service'] ?? true),
            'shop' => (bool) ($row['offers_shop_repair'] ?? true),
        ];
    }

    /** "Home Service and Shop Repair", "Home Service", "Shop Repair", "Not set". */
    public static function label(?array $row): string
    {
        $work = self::of($row);

        return match (true) {
            $work === null => 'Not set',
            $work['home'] && $work['shop'] => 'Home Service and Shop Repair',
            $work['home'] => 'Home Service',
            $work['shop'] => 'Shop Repair',
            default => 'Not set',
        };
    }

    /** Whether the shop is pinned - Shop Repair needs it. */
    public static function hasShop(?array $row): bool
    {
        return $row !== null
            && ($row['shop_latitude'] ?? null) !== null
            && ($row['shop_longitude'] ?? null) !== null;
    }
}
