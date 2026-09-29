/// Dart view of the `job_matches.score_breakdown` jsonb column.
///
/// This file and `supabase/functions/match-technician/scoring/types.ts` are two
/// halves of one contract. If you add a factor on the Deno side, add it here
/// too; nothing else in the app reads the raw map.
///
/// Shape written by the edge function:
///
/// ```json
/// {
///   "version": 2,
///   "stage1": { "score": 0.82, "factors": [ ... ] },
///   "stage2": { "score": 0.71, "factors": [ ... ] },
///   "recommendation": {
///     "score": 0.79, "factors": [ ... ],
///     "signals": ["urgent", "rain", "on_site", "technology"],
///     "rules": [{ "id": "urgent_visit_in_rain", "label": "...", ... }],
///     "reasons": [{ "code": "near", "text": "2.1 km from your location",
///                   "kind": "positive" }]
///   },
///   "final_score": 0.79,
///   "context": { "distance_km": 2.1, "similar_repairs": 5, ... },
///   "explainability": ["5 similar repairs", "2.1 km away", "Available today"]
/// }
/// ```
///
/// Version 1 rows - written before 2026-09-27, or by a matcher that has not
/// been redeployed - have no `recommendation`. Everything below reads them
/// anyway: [ScoreBreakdown.recommendation] is null and [ScoreBreakdown.reasons]
/// falls back to the version 1 phrases.
library;

import 'json_utils.dart';

/// One weighted input to a score, carrying enough detail to explain itself.
class ScoreFactor {
  const ScoreFactor({
    required this.key,
    required this.label,
    required this.value,
    required this.weight,
    required this.contribution,
    this.note,
    this.baseWeight,
  });

  factory ScoreFactor.fromJson(Map<String, dynamic> json) {
    return ScoreFactor(
      key: json['key'] as String? ?? 'unknown',
      label: json['label'] as String? ?? 'Factor',
      value: asDouble(json['value']),
      weight: asDouble(json['weight']),
      contribution: asDouble(json['contribution']),
      note: json['note'] as String?,
      baseWeight: asNullableDouble(json['base_weight']),
    );
  }

  /// Stable identifier, e.g. `skill_tag`, `traffic`, `workload`.
  final String key;

  /// Display name, e.g. "Skill match".
  final String label;

  /// Normalised 0..1 result for this factor alone.
  final double value;

  /// Weight this factor carries in its stage, from the scoring constants.
  final double weight;

  /// `value * weight`, i.e. what it actually added to the stage score.
  final double contribution;

  /// Short human sentence, e.g. "Handles cracked screens on phones".
  final String? note;

  /// The weight before a matching rule changed it. Null when no rule touched
  /// this factor - [weight] is then the base weight.
  final double? baseWeight;

  /// True when a matching rule moved this factor's weight up or down.
  bool get reweighted =>
      baseWeight != null && (baseWeight! - weight).abs() > 0.0005;

  /// 0-100 for progress bars.
  int get percent => (value.clamp(0, 1) * 100).round();
}

/// One of the two scoring stages.
class ScoreStage {
  const ScoreStage({required this.score, required this.factors});

  factory ScoreStage.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const ScoreStage(score: 0, factors: <ScoreFactor>[]);
    }
    final List<dynamic> raw =
        json['factors'] as List<dynamic>? ?? const <dynamic>[];
    return ScoreStage(
      score: asDouble(json['score']),
      factors: raw
          .whereType<Map<String, dynamic>>()
          .map(ScoreFactor.fromJson)
          .toList(growable: false),
    );
  }

  final double score;
  final List<ScoreFactor> factors;

  int get percent => (score.clamp(0, 1) * 100).round();
}

/// A reason a client reads under "Why this technician?".
///
/// Written by the engine from a recorded number - see `scoring/reasons.ts` -
/// never composed on the phone. A caveat is something the client should know
/// before booking: a vacation, a rate above their budget.
class RecommendationReason {
  const RecommendationReason({
    required this.code,
    required this.text,
    this.isCaveat = false,
  });

  factory RecommendationReason.fromJson(Map<String, dynamic> json) {
    return RecommendationReason(
      code: json['code'] as String? ?? 'reason',
      text: json['text'] as String? ?? '',
      isCaveat: json['kind'] == 'caveat',
    );
  }

  final String code;
  final String text;
  final bool isCaveat;
}

/// One change a matching rule made to one factor's weight.
class RuleEffect {
  const RuleEffect({
    required this.stage,
    required this.factor,
    required this.multiplier,
  });

  factory RuleEffect.fromJson(Map<String, dynamic> json) {
    return RuleEffect(
      stage: json['stage'] as String? ?? '',
      factor: json['factor'] as String? ?? '',
      multiplier: asDouble(json['multiplier']),
    );
  }

  /// `suitability`, `acceptance` or `recommendation`.
  final String stage;
  final String factor;
  final double multiplier;
}

/// A matching rule that fired for this job (Step 3 of the brief).
class AppliedRule {
  const AppliedRule({
    required this.id,
    required this.label,
    required this.rationale,
    this.when = const <String>[],
    this.effects = const <RuleEffect>[],
  });

  factory AppliedRule.fromJson(Map<String, dynamic> json) {
    final List<dynamic> effects =
        json['effects'] as List<dynamic>? ?? const <dynamic>[];
    return AppliedRule(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? 'Rule',
      rationale: json['rationale'] as String? ?? '',
      when: asStringList(json['when']),
      effects: effects
          .whereType<Map<String, dynamic>>()
          .map(RuleEffect.fromJson)
          .toList(growable: false),
    );
  }

  final String id;
  final String label;
  final String rationale;

  /// The signals that all had to hold, e.g. `urgent`, `rain`, `on_site`.
  final List<String> when;
  final List<RuleEffect> effects;
}

/// Stage 3: the recommendation score, and the situation it was computed in.
class RecommendationStage extends ScoreStage {
  const RecommendationStage({
    required super.score,
    required super.factors,
    this.signals = const <String>[],
    this.rules = const <AppliedRule>[],
    this.reasons = const <RecommendationReason>[],
  });

  factory RecommendationStage.fromJson(Map<String, dynamic> json) {
    final ScoreStage stage = ScoreStage.fromJson(json);
    final List<dynamic> rules =
        json['rules'] as List<dynamic>? ?? const <dynamic>[];
    final List<dynamic> reasons =
        json['reasons'] as List<dynamic>? ?? const <dynamic>[];
    return RecommendationStage(
      score: stage.score,
      factors: stage.factors,
      signals: asStringList(json['signals']),
      rules: rules
          .whereType<Map<String, dynamic>>()
          .map(AppliedRule.fromJson)
          .toList(growable: false),
      reasons: reasons
          .whereType<Map<String, dynamic>>()
          .map(RecommendationReason.fromJson)
          .where((RecommendationReason r) => r.text.isNotEmpty)
          .toList(growable: false),
    );
  }

  /// Conditions that held: `urgent`, `rain`, `heavy_traffic`, `on_site`,
  /// `appliance`, `technology`.
  final List<String> signals;
  final List<AppliedRule> rules;
  final List<RecommendationReason> reasons;
}

/// The live context the engine saw when it scored this technician.
///
/// Everything here is nullable: TomTom or OpenWeatherMap can be down, and a
/// brand-new technician has no history. The UI degrades a line at a time
/// rather than showing a broken card.
class MatchContext {
  const MatchContext({
    this.distanceKm,
    this.etaMinutes,
    this.similarRepairs,
    this.diagnosisAccuracy,
    this.workload,
    this.isColdStart = false,
    this.budgetFit,
    this.trafficLabel,
    this.congestion,
    this.weatherLabel,
    this.weatherSeverity,
    this.tempC,
    this.urgency,
    this.servicePath,
    this.indicativeQuote,
  });

  factory MatchContext.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const MatchContext();

    final Map<String, dynamic> traffic =
        json['traffic'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final Map<String, dynamic> weather =
        json['weather'] as Map<String, dynamic>? ?? const <String, dynamic>{};

    return MatchContext(
      distanceKm: asNullableDouble(json['distance_km']),
      etaMinutes: asNullableDouble(json['eta_minutes']),
      similarRepairs: asNullableInt(json['similar_repairs']),
      diagnosisAccuracy: asNullableDouble(json['diagnosis_accuracy']),
      workload: asNullableInt(json['workload']),
      isColdStart: json['is_cold_start'] as bool? ?? false,
      budgetFit: asNullableDouble(json['budget_fit']),
      trafficLabel: traffic['label'] as String?,
      congestion: asNullableDouble(traffic['congestion']),
      weatherLabel: weather['label'] as String?,
      weatherSeverity: asNullableDouble(weather['severity']),
      tempC: asNullableDouble(weather['temp_c']),
      urgency: json['urgency'] as String?,
      servicePath: json['service_path'] as String?,
      indicativeQuote: asNullableDouble(json['indicative_quote_php']),
    );
  }

  final double? distanceKm;
  final double? etaMinutes;
  final int? similarRepairs;
  final double? diagnosisAccuracy;
  final int? workload;
  final bool isColdStart;
  final double? budgetFit;
  final String? trafficLabel;
  final double? congestion;
  final String? weatherLabel;
  final double? weatherSeverity;
  final double? tempC;

  /// `need_today` or `can_wait`, as the job was scored.
  final String? urgency;

  /// `home_service`, `pickup` or `it_community`.
  final String? servicePath;

  /// The tier rate times a typical job length, in PHP. An estimate the engine
  /// compared with the budget - not a price anyone agreed to.
  final double? indicativeQuote;

  String? get distanceLabel {
    final double? km = distanceKm;
    if (km == null) return null;
    if (km < 1) return '${(km * 1000).round()} m away';
    return '${km.toStringAsFixed(1)} km away';
  }

  String? get etaLabel {
    final double? minutes = etaMinutes;
    if (minutes == null) return null;
    return '~${minutes.round()} min travel';
  }
}

/// The whole `score_breakdown` document.
class ScoreBreakdown {
  const ScoreBreakdown({
    required this.stage1,
    required this.stage2,
    required this.context,
    required this.explainability,
    this.version = 1,
    this.recommendation,
  });

  factory ScoreBreakdown.fromJson(Map<String, dynamic>? json) {
    if (json == null) return ScoreBreakdown.empty();

    final List<dynamic> lines =
        json['explainability'] as List<dynamic>? ?? const <dynamic>[];
    final Map<String, dynamic>? recommendation =
        json['recommendation'] as Map<String, dynamic>?;

    return ScoreBreakdown(
      version: json['version'] as int? ?? 1,
      stage1: ScoreStage.fromJson(json['stage1'] as Map<String, dynamic>?),
      stage2: ScoreStage.fromJson(json['stage2'] as Map<String, dynamic>?),
      context: MatchContext.fromJson(json['context'] as Map<String, dynamic>?),
      explainability: lines.whereType<String>().toList(growable: false),
      recommendation: recommendation == null
          ? null
          : RecommendationStage.fromJson(recommendation),
    );
  }

  factory ScoreBreakdown.empty() {
    return const ScoreBreakdown(
      stage1: ScoreStage(score: 0, factors: <ScoreFactor>[]),
      stage2: ScoreStage(score: 0, factors: <ScoreFactor>[]),
      context: MatchContext(),
      explainability: <String>[],
    );
  }

  final int version;
  final ScoreStage stage1;
  final ScoreStage stage2;
  final MatchContext context;

  /// Short phrases the edge function pre-built, e.g. "5 similar repairs".
  final List<String> explainability;

  /// Stage 3. Null on version 1 rows.
  final RecommendationStage? recommendation;

  /// What the "Why this technician?" sheet lists.
  ///
  /// The engine's own reasons when it sent them. On a version 1 row, the old
  /// phrases stand in - capitalised, all positive - so an older match still
  /// explains itself rather than showing an empty sheet.
  List<RecommendationReason> get reasons {
    final List<RecommendationReason>? sent = recommendation?.reasons;
    if (sent != null && sent.isNotEmpty) return sent;

    final List<String> parts = explainability.isNotEmpty
        ? explainability
        : _fallbackParts();
    return <RecommendationReason>[
      for (final String part in parts)
        if (part.isNotEmpty)
          RecommendationReason(
            code: 'legacy',
            text: '${part[0].toUpperCase()}${part.substring(1)}',
          ),
    ];
  }

  /// One line for the card, from the two strongest positive reasons, e.g.
  /// "Passed SUGO's assessment on laptops · 2.1 km from your location".
  String? get summary {
    final List<String> positives = reasons
        .where((RecommendationReason r) => !r.isCaveat)
        .map((RecommendationReason r) => r.text)
        .take(2)
        .toList();
    if (positives.isEmpty) return null;
    return positives.join(' · ');
  }

  /// Every factor from both stages, strongest contribution first. Used by the
  /// "why this match" sheet on the client review screen.
  List<ScoreFactor> get allFactors {
    final List<ScoreFactor> combined = <ScoreFactor>[
      ...stage1.factors,
      ...stage2.factors,
    ];
    combined.sort(
      (ScoreFactor a, ScoreFactor b) =>
          b.contribution.compareTo(a.contribution),
    );
    return combined;
  }

  /// The one-line "Matched because: ..." shown on each result card.
  ///
  /// Prefers the phrases the engine sent. If the jsonb is old or empty we
  /// rebuild an equivalent line from [context] on the client, so a card is
  /// never left with a bare score and no reason.
  String explainabilityLine({int maxParts = 3}) {
    final List<String> parts = explainability.isNotEmpty
        ? explainability
        : _fallbackParts();

    if (parts.isEmpty) return 'Matched on overall fit for this job.';
    return 'Matched because: ${parts.take(maxParts).join(', ')}';
  }

  List<String> _fallbackParts() {
    final List<String> parts = <String>[];

    final int? repairs = context.similarRepairs;
    if (repairs != null && repairs > 0) {
      parts.add('$repairs similar repair${repairs == 1 ? '' : 's'}');
    } else if (context.isColdStart) {
      parts.add('newly verified technician');
    }

    final String? distance = context.distanceLabel;
    if (distance != null) parts.add(distance);

    final int? workload = context.workload;
    if (workload != null && workload == 0) {
      parts.add('available today');
    } else if (workload != null && workload <= 2) {
      parts.add('light schedule today');
    }

    final String? traffic = context.trafficLabel;
    if (traffic != null && parts.length < 4) parts.add(traffic);

    return parts;
  }
}
