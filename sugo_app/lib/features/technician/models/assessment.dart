import 'package:flutter/material.dart';

/// A specialization a technician can qualify in.
///
/// Only `applianceRepair` has a seeded question bank so far, which is why the
/// others are marked unavailable rather than hidden - showing them greyed out
/// tells the technician the platform is broader than what they can sit today.
enum Specialization {
  applianceRepair(
    'appliance_repair',
    'Appliance repair',
    'Aircon, refrigerators, washing machines, small kitchen appliances.',
    Icons.kitchen_rounded,
    available: true,
  ),
  laptopRepair(
    'laptop_repair',
    'Laptop and PC repair',
    'Screens, boards, storage, operating systems.',
    Icons.laptop_mac_rounded,
  ),
  phoneRepair(
    'phone_repair',
    'Phone and tablet repair',
    'Screens, batteries, charging ports, water damage.',
    Icons.smartphone_rounded,
  ),
  networkSetup(
    'network_setup',
    'Network and CCTV',
    'Wi-Fi coverage, routers, cabling, camera systems.',
    Icons.router_rounded,
  );

  const Specialization(
    this.wire,
    this.label,
    this.blurb,
    this.icon, {
    this.available = false,
  });

  /// Stored in `technicians.specialization` and used to select the question
  /// bank in `assessment_questions.specialization`.
  final String wire;

  final String label;
  final String blurb;
  final IconData icon;

  /// False when no question bank has been seeded for it yet.
  final bool available;

  static Specialization? fromWire(String? value) {
    for (final Specialization s in Specialization.values) {
      if (s.wire == value) return s;
    }
    return null;
  }
}

/// One quiz question, as the client is allowed to see it.
///
/// Deliberately has no `correctChoiceIndex`. Migration 20260906000002 revokes
/// that column from `anon` and `authenticated`, so the field genuinely cannot
/// be fetched - the quiz screen has no way to mark its own paper. Scoring
/// happens in the `submit-assessment` edge function.
class AssessmentQuestion {
  const AssessmentQuestion({
    required this.id,
    required this.specialization,
    required this.question,
    required this.choices,
  });

  factory AssessmentQuestion.fromJson(Map<String, dynamic> json) {
    final List<dynamic> raw =
        json['choices'] as List<dynamic>? ?? const <dynamic>[];

    return AssessmentQuestion(
      id: json['id'] as String,
      specialization: json['specialization'] as String? ?? '',
      question: json['question'] as String? ?? '',
      choices: raw.map((Object? c) => c.toString()).toList(growable: false),
    );
  }

  final String id;
  final String specialization;
  final String question;
  final List<String> choices;
}

/// What `submit-assessment` returns after marking an attempt.
class AssessmentResult {
  const AssessmentResult({
    required this.score,
    required this.correctCount,
    required this.totalQuestions,
    required this.passed,
    required this.passThreshold,
    required this.isVerified,
    this.suggestedTier,
    this.specialization,
    this.attemptId,
  });

  factory AssessmentResult.fromJson(Map<String, dynamic> json) {
    return AssessmentResult(
      score: (json['score'] as num?)?.toDouble() ?? 0,
      correctCount: json['correct_count'] as int? ?? 0,
      totalQuestions: json['total_questions'] as int? ?? 0,
      passed: json['passed'] as bool? ?? false,
      passThreshold: (json['pass_threshold'] as num?)?.toDouble() ?? 60,
      isVerified: json['is_verified'] as bool? ?? false,
      suggestedTier: json['suggested_tier'] as String?,
      specialization: json['specialization'] as String?,
      attemptId: json['attempt_id'] as String?,
    );
  }

  /// Percentage, 0-100.
  final double score;

  final int correctCount;
  final int totalQuestions;
  final bool passed;
  final double passThreshold;

  /// Whether the account was activated. True only when [passed] is true.
  final bool isVerified;

  /// standard / pro / elite, or null on a fail.
  final String? suggestedTier;

  final String? specialization;
  final String? attemptId;

  String get scoreLabel => '${score.round()}%';

  String get tierLabel {
    final String? tier = suggestedTier;
    if (tier == null) return 'Not awarded';
    return tier[0].toUpperCase() + tier.substring(1);
  }

  /// How far short a failed attempt fell, for the retry screen.
  int get pointsShort =>
      passed ? 0 : (passThreshold - score).ceil().clamp(0, 100);
}
