import 'package:flutter/foundation.dart';

import 'technician_preferences.dart';

/// One of the client's must-haves, checked against one technician
/// (2026-11-17), for the "Meets your must-haves" row on a match card.
@immutable
class PreferenceCheck {
  const PreferenceCheck({
    required this.field,
    required this.label,
    this.detail,
    this.met,
  });

  final PreferenceField field;

  /// The preference as the client set it, e.g. "Within 5 km".
  final String label;

  /// The technician's own value, e.g. "3.2 km" or "4.8★". Null when the card
  /// does not carry it.
  final String? detail;

  /// True or false when the card's data can confirm it; null when it cannot
  /// (the specialisation, a picked date). Null is still a pass: everyone in
  /// the Top 3 got there through the server's pre-filter, which checked
  /// every preference. False only appears when something changed since
  /// matching ran - a technician who went on leave, say.
  final bool? met;

  bool get passed => met ?? true;
}

/// Checks each preference the client set against what the match card knows.
///
/// The server's pre-filter (`scoring/preferences.ts`) is the rule; this only
/// shows its result with real numbers, so the client sees WHY a technician
/// qualifies - "Within 5 km · 3.2 km" - rather than taking it on trust.
List<PreferenceCheck> checkPreferences(
  TechnicianPreferences preferences, {
  double? distanceKm,
  double? rating,
  TrustBadge? trustForJob,
  bool away = false,
  bool busy = false,
}) {
  return <PreferenceCheck>[
    for (final PreferenceField field in preferences.active)
      switch (field) {
        PreferenceField.specialization => PreferenceCheck(
          field: field,
          label: preferences.labelFor(field),
        ),
        PreferenceField.maxDistance => PreferenceCheck(
          field: field,
          label: preferences.labelFor(field),
          detail: distanceKm == null
              ? null
              : '${distanceKm.toStringAsFixed(1)} km',
          met: distanceKm == null
              ? null
              : distanceKm <= preferences.maxDistance!.km,
        ),
        PreferenceField.minRating => PreferenceCheck(
          field: field,
          label: preferences.labelFor(field),
          detail: rating == null || rating <= 0
              ? null
              : '${rating.toStringAsFixed(1)}★',
          met: rating == null ? null : rating >= preferences.minRating!.value,
        ),
        PreferenceField.availability =>
          preferences.availability == AvailabilityPreference.now
              ? PreferenceCheck(
                  field: field,
                  label: preferences.labelFor(field),
                  detail: away
                      ? 'on leave'
                      : busy
                      ? 'on a job now'
                      : 'free now',
                  met: !away && !busy,
                )
              : PreferenceCheck(
                  field: field,
                  label: preferences.labelFor(field),
                ),
        PreferenceField.minTrust => PreferenceCheck(
          field: field,
          label: '${preferences.labelFor(field)}+',
          detail: trustForJob?.label,
          met: trustForJob?.atLeast(preferences.minTrust!),
        ),
      },
  ];
}

/// One of the client's preferences drawn as a bar on a match card
/// (2026-11-17): how well this technician fits it, in the same
/// label-bar-percent form as the card's Match and Acceptance rows.
///
/// The user's request: "show the client preference like on the picture -
/// location, skills, and the trust badge they want". Only the preferences
/// the client actually set get a bar.
@immutable
class PreferenceBar {
  const PreferenceBar({
    required this.field,
    required this.label,
    required this.percent,
    required this.detail,
    required this.met,
  });

  final PreferenceField field;

  /// "Location", "Skills", "Trust badge", "Rating", "Availability".
  final String label;

  /// 0-100. A met preference is 100, except Skills, which shows the engine's
  /// own skill score for the job.
  final int percent;

  /// The line under the bar: "2.4 km · within 5 km", "Skill verified".
  final String detail;

  /// Whether the technician meets the preference as the client set it.
  final bool met;
}

/// The bars for [preferences], from what the card knows about a technician.
///
/// How each percentage is worked out, so nothing is invented:
///
/// * **Location** - 100 within the limit; beyond it, the limit as a share of
///   the distance (5 km wanted, 12 km away: 42%).
/// * **Skills** - the matcher's Stage 1 skill score for this job
///   ([skillPercent]: its specialisation and skill-tag factors), or 100 when
///   that is not on the row. Any technician shown has the specialisation:
///   the pre-filter removed the rest.
/// * **Rating** - 100 at or above the minimum; below it, the share of it.
/// * **Trust badge** - 100 at or above the wanted rung; below it, the rung
///   held as a share of the rung wanted; 0 with no badge.
/// * **Availability** - 100 free, 40 on another job, 0 on leave.
List<PreferenceBar> preferenceBars(
  TechnicianPreferences preferences, {
  double? distanceKm,
  double? rating,
  TrustBadge? trustForJob,
  int? skillPercent,
  bool away = false,
  bool busy = false,
}) {
  int share(double have, double want) =>
      want <= 0 ? 100 : (have / want * 100).clamp(0, 100).round();

  return <PreferenceBar>[
    for (final PreferenceField field in preferences.active)
      switch (field) {
        PreferenceField.maxDistance => () {
          final int limit = preferences.maxDistance!.km;
          if (distanceKm == null) {
            return PreferenceBar(
              field: field,
              label: 'Location',
              percent: 0,
              detail: 'Distance unknown · limit $limit km',
              met: false,
            );
          }
          final bool within = distanceKm <= limit;
          return PreferenceBar(
            field: field,
            label: 'Location',
            percent: within ? 100 : share(limit.toDouble(), distanceKm),
            detail:
                '${distanceKm.toStringAsFixed(1)} km · '
                '${within ? 'within' : 'beyond'} $limit km',
            met: within,
          );
        }(),
        PreferenceField.specialization => PreferenceBar(
          field: field,
          label: 'Skills',
          percent: (skillPercent ?? 100).clamp(0, 100),
          detail: preferences.labelFor(field),
          met: true,
        ),
        PreferenceField.minRating => () {
          final double want = preferences.minRating!.value;
          final double have = rating ?? 0;
          final bool met = have >= want;
          return PreferenceBar(
            field: field,
            label: 'Rating',
            percent: met ? 100 : share(have, want),
            detail: have <= 0
                ? 'No reviews yet · min ${want.toStringAsFixed(1)}'
                : '${have.toStringAsFixed(1)}★ · min ${want.toStringAsFixed(1)}',
            met: met,
          );
        }(),
        PreferenceField.minTrust => () {
          final TrustBadge want = preferences.minTrust!;
          final TrustBadge? have = trustForJob;
          final bool met = have?.atLeast(want) ?? false;
          return PreferenceBar(
            field: field,
            label: 'Trust badge',
            percent: met
                ? 100
                : have == null
                ? 0
                : share(have.rung.toDouble(), want.rung.toDouble()),
            detail: have == null
                ? 'No badge yet · wants ${want.label}'
                : met
                ? have.label
                : '${have.label} · wants ${want.label}',
            met: met,
          );
        }(),
        PreferenceField.availability =>
          preferences.availability == AvailabilityPreference.now
              ? PreferenceBar(
                  field: field,
                  label: 'Availability',
                  percent: away
                      ? 0
                      : busy
                      ? 40
                      : 100,
                  detail: away
                      ? 'On leave'
                      : busy
                      ? 'On a job now'
                      : 'Free now',
                  met: !away && !busy,
                )
              : PreferenceBar(
                  field: field,
                  label: 'Availability',
                  percent: 100,
                  detail: preferences.labelFor(field),
                  met: true,
                ),
      },
  ];
}
