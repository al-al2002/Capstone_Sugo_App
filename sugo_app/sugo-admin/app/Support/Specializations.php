<?php

namespace App\Support;

/**
 * The five client-facing specializations, for the admin's dispute remedy and
 * certificate review.
 *
 * The keys are the database values: the same list `jobs.pref_specialization`,
 * `job_disputes.remedy_specialization` and
 * `technician_verification_documents.specialization` are checked against,
 * and that `specialization_devices()` maps onto device types (2026-11-15).
 * The labels match the Flutter app's `PreferredSpecialization`.
 */
final class Specializations
{
    public const LABELS = [
        'computer'      => 'Computer/Laptop',
        'pc_building'   => 'PC Building',
        'phone_tablet'  => 'Phone/Tablet',
        'network_setup' => 'Network & Device Setup',
        'appliance'     => 'Appliance Service',
    ];
}
