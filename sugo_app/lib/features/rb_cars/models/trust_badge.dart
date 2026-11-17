import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import 'json_utils.dart';
import 'technician_preferences.dart';

/// The Progressive Trust Badge (2026-11-15), an ordered ladder.
///
/// Written to `technicians.badge` by `evaluate_technician_badge()` whenever
/// an event could change it (a completion, a review, a dispute decision, an
/// answered or missed offer, an assessment, a certificate), and nightly as a
/// fallback. The app only ever reads it.
///
/// One ladder for everything: the profile shows it, the client's "minimum
/// trust badge" preference is checked against it, and RB-CARS' trust factor
/// scores it. Compare rungs with [atLeast], never with `==`.
enum TrustBadge {
  idVerified(
    'id_verified',
    'ID verified',
    'Identity and email checked by SUGO.',
    Icons.verified_user_rounded,
  ),
  skillVerified(
    'skill_verified',
    'Skill verified',
    'Proven in a specialization: a passed assessment or an approved '
        'certificate.',
    Icons.workspace_premium_rounded,
  ),
  communityTrusted(
    'community_trusted',
    'Community Trusted',
    'Skill verified, with 50+ jobs, a 4.5+ rating, quick answers and a clean '
        'record.',
    Icons.handshake_rounded,
  );

  const TrustBadge(this.wire, this.label, this.blurb, this.icon);

  final String wire;
  final String label;
  final String blurb;
  final IconData icon;

  /// 1, 2 or 3. Below the baseline there is no badge at all (null).
  int get rung => index + 1;

  bool atLeast(TrustBadge other) => rung >= other.rung;

  TrustBadge? get next => this == communityTrusted ? null : values[index + 1];

  /// Wash and ink for the pill. Existing tokens only; each ink passes AA on
  /// its wash.
  (Color, Color) get colors => switch (this) {
    idVerified => (AppColors.primarySoft, AppColors.primaryDark),
    skillVerified => (AppColors.successSoft, AppColors.success),
    communityTrusted => (AppColors.accentSoft, AppColors.accentDark),
  };

  static TrustBadge? fromWire(String? value) {
    for (final TrustBadge badge in TrustBadge.values) {
      if (badge.wire == value) return badge;
    }
    return null;
  }
}

/// What `my_trust_badge()` returns: the technician's level, every number the
/// evaluator used, and the thresholds - so the progress card shows exactly
/// what decided the badge, never an approximation of it.
@immutable
class TrustBadgeProgress {
  const TrustBadgeProgress({
    required this.level,
    required this.identityApproved,
    required this.emailConfirmed,
    required this.skillVerified,
    required this.completedJobs,
    required this.avgRating,
    required this.responseRate,
    required this.offersCounted,
    required this.disputes,
    required this.cancellationRate,
    required this.thresholds,
  });

  factory TrustBadgeProgress.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> t =
        json['thresholds'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final Object? skills = json['skill_verified_specializations'];

    return TrustBadgeProgress(
      level: TrustBadge.fromWire(json['level'] as String?),
      identityApproved: json['identity_approved'] as bool? ?? false,
      emailConfirmed: json['email_confirmed'] as bool? ?? false,
      skillVerified: skills is List
          ? skills
                .map(
                  (Object? s) => PreferredSpecialization.fromWire(s as String?),
                )
                .whereType<PreferredSpecialization>()
                .toList(growable: false)
          : const <PreferredSpecialization>[],
      completedJobs: asInt(json['completed_jobs']),
      avgRating: asNullableDouble(json['avg_rating']),
      responseRate: asNullableDouble(json['response_rate']),
      offersCounted: asInt(json['offers_counted']),
      disputes: asInt(json['disputes_open_or_lost']),
      cancellationRate: asDouble(json['cancellation_rate']),
      thresholds: TrustThresholds(
        completedJobs: asNullableInt(t['completed_jobs']) ?? 50,
        avgRating: asNullableDouble(t['avg_rating']) ?? 4.5,
        responseRate: asNullableDouble(t['response_rate']) ?? 0.9,
        maxDisputes: asNullableInt(t['max_disputes']) ?? 0,
        maxCancellationRate:
            asNullableDouble(t['max_cancellation_rate']) ?? 0.1,
        responseWindowHours:
            asNullableDouble(t['response_window_hours'])?.round() ?? 24,
      ),
    );
  }

  /// Null below the baseline.
  final TrustBadge? level;
  final bool identityApproved;
  final bool emailConfirmed;
  final List<PreferredSpecialization> skillVerified;
  final int completedJobs;

  /// Null with no rated jobs yet.
  final double? avgRating;

  /// 0..1, or null when no offer has been counted yet.
  final double? responseRate;
  final int offersCounted;
  final int disputes;
  final double cancellationRate;
  final TrustThresholds thresholds;

  bool get jobsMet => completedJobs >= thresholds.completedJobs;
  bool get ratingMet => (avgRating ?? 0) >= thresholds.avgRating;
  bool get responseMet => (responseRate ?? 0) >= thresholds.responseRate;
  bool get disputesMet => disputes <= thresholds.maxDisputes;
  bool get cancellationsMet =>
      cancellationRate < thresholds.maxCancellationRate;

  /// The brief's one-line progress, e.g. "38 / 50 jobs, rating 4.6,
  /// response 92%".
  String get summary => <String>[
    '$completedJobs / ${thresholds.completedJobs} jobs',
    'rating ${avgRating == null ? '—' : avgRating!.toStringAsFixed(1)}',
    'response ${responseRate == null ? '—' : '${(responseRate! * 100).round()}%'}',
  ].join(', ');
}

/// The Community Trusted thresholds, as `trust_badge_rules()` defines them.
@immutable
class TrustThresholds {
  const TrustThresholds({
    required this.completedJobs,
    required this.avgRating,
    required this.responseRate,
    required this.maxDisputes,
    required this.maxCancellationRate,
    required this.responseWindowHours,
  });

  final int completedJobs;
  final double avgRating;
  final double responseRate;
  final int maxDisputes;
  final double maxCancellationRate;
  final int responseWindowHours;
}
