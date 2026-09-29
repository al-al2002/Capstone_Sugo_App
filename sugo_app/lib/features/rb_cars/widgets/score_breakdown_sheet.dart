import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/match_result.dart';
import '../models/score_breakdown.dart';
import 'explainability_chip.dart';

/// The full "why this match" sheet.
///
/// Opens from "See how the score was worked out" at the foot of the "Why this
/// technician?" sheet, and shows every stage factor by factor, with each
/// factor's own score and the weight it carries - and, on a version 2 row, the
/// matching rules that re-weighted them and the Stage 3 recommendation. This
/// is the screen that answers a defence panel's "how did it decide?" - it is
/// the `score_breakdown` jsonb, rendered.
class ScoreBreakdownSheet extends StatelessWidget {
  const ScoreBreakdownSheet({super.key, required this.match});

  final MatchResult match;

  static Future<void> show(BuildContext context, MatchResult match) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => ScoreBreakdownSheet(match: match),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ScoreBreakdown breakdown = match.breakdown;
    final MatchContext context0 = breakdown.context;
    final RecommendationStage? recommendation = breakdown.recommendation;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (BuildContext context, ScrollController controller) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppSizes.cardRadius),
            ),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(
              AppSizes.screenPadding,
              AppSizes.md,
              AppSizes.screenPadding,
              AppSizes.xxl,
            ),
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                  ),
                ),
              ),
              const SizedBox(height: AppSizes.lg),
              Text(
                'Why ${match.technician?.displayName ?? 'this technician'}?',
                style: AppTextStyles.headline,
              ),
              const SizedBox(height: AppSizes.xs),
              Text(
                recommendation == null
                    ? 'RB-CARS scored every available technician on two '
                          'stages. Here is the whole calculation for this one.'
                    : 'RB-CARS checked the conditions, chose its matching '
                          'rules, then scored every available technician in '
                          'three stages. Here is the whole calculation for '
                          'this one.',
                style: AppTextStyles.subtitle,
              ),
              const SizedBox(height: AppSizes.xl),

              _ScoreSummary(match: match),
              const SizedBox(height: AppSizes.xl),

              if (recommendation != null &&
                  recommendation.rules.isNotEmpty) ...<Widget>[
                _RulesBlock(rules: recommendation.rules),
                const SizedBox(height: AppSizes.lg),
              ],

              _StageBlock(
                title: 'Stage 1 - Suitability',
                blurb:
                    'Can they fix this device, for this symptom? Skills, '
                    'specialisation and their track record on the same repair.',
                weightLabel: _shareLabel(recommendation, 'suitability', 60),
                stage: breakdown.stage1,
              ),
              const SizedBox(height: AppSizes.lg),

              _StageBlock(
                title: 'Stage 2 - Acceptance',
                blurb:
                    'Will they take it and turn up? Budget, current workload, '
                    'urgency, plus live traffic and weather at your location.',
                weightLabel: _shareLabel(recommendation, 'acceptance', 40),
                stage: breakdown.stage2,
              ),
              const SizedBox(height: AppSizes.lg),

              if (recommendation != null) ...<Widget>[
                _StageBlock(
                  title: 'Stage 3 - Recommendation',
                  blurb:
                      'Of the qualified, who fits this client and this moment? '
                      'Both stages above, plus fit to current conditions, your '
                      'own history with them, and their track record.',
                  weightLabel: 'This is the score the list is ranked by',
                  stage: recommendation,
                ),
                const SizedBox(height: AppSizes.xl),
              ] else
                const SizedBox(height: AppSizes.sm),

              _ContextBlock(context: context0),
            ],
          ),
        );
      },
    );
  }
}

/// "45% of the recommendation score" - read from the stored weights, so it
/// is always the weight actually applied, rules included. A version 1 row
/// falls back to the old fixed split it was scored with.
String _shareLabel(
  RecommendationStage? recommendation,
  String key,
  int legacyPercent,
) {
  if (recommendation == null) return '$legacyPercent% of the final score';
  for (final ScoreFactor f in recommendation.factors) {
    if (f.key == key) {
      return '${(f.weight * 100).round()}% of the recommendation score';
    }
  }
  return 'Part of the recommendation score';
}

/// The matching rules that fired, and what each one changed.
class _RulesBlock extends StatelessWidget {
  const _RulesBlock({required this.rules});

  final List<AppliedRule> rules;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: AppColors.cyanSoft,
        borderRadius: BorderRadius.circular(AppSizes.panelRadius),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Matching rules applied',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.cyanDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'The conditions changed how much some factors count. Weights '
            'marked with an arrow below were moved by these rules.',
            style: AppTextStyles.caption,
          ),
          for (final AppliedRule rule in rules) ...<Widget>[
            const SizedBox(height: AppSizes.md),
            Text(
              rule.label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              rule.effects
                  .map(
                    (RuleEffect e) =>
                        '${factorDisplayName(e.factor)} '
                        '×${_multiplier(e.multiplier)}',
                  )
                  .join(' · '),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.cyanDark,
              ),
            ),
            const SizedBox(height: 2),
            Text(rule.rationale, style: AppTextStyles.caption),
          ],
        ],
      ),
    );
  }
}

String _multiplier(double m) =>
    m == m.roundToDouble() ? m.toStringAsFixed(0) : m.toStringAsFixed(1);

/// A factor key as a person would say it. Shared with the ranking walkthrough.
String factorDisplayName(String key) => switch (key) {
  'proximity' => 'Distance',
  'availability' => 'Availability',
  'weather' => 'Weather',
  'traffic' => 'Traffic',
  'workload' => 'Workload',
  'urgency_path' => 'Urgency fit',
  'budget_fit' => 'Budget fit',
  'client_trust' => 'Client reliability',
  'specialization' => 'Brand and device match',
  'skill_tag' => 'Skill match',
  'tier' => 'Tier',
  'verification_tier' => 'Verification tier',
  'diagnosis_accuracy' => 'Diagnosis accuracy',
  'rating' => 'Client rating',
  'context_fit' => 'Fit to conditions',
  'client_preference' => 'Your history with them',
  'technician_performance' => 'Track record',
  'acceptance' => 'Acceptance',
  'suitability' => 'Suitability',
  _ => key.replaceAll('_', ' '),
};

class _ScoreSummary extends StatelessWidget {
  const _ScoreSummary({required this.match});

  final MatchResult match;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.panelRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          _ScoreCell(
            label: 'Suitability',
            value: match.breakdown.stage1.percent,
            color: AppColors.primary,
          ),
          const _Times(),
          _ScoreCell(
            label: 'Acceptance',
            value: match.breakdown.stage2.percent,
            // The text orange: this is a number to read, and the bright
            // orange is 2.1:1 on white.
            color: AppColors.accentDark,
          ),
          // An arrow rather than "=": on a version 2 row the recommendation
          // also weighs conditions, history and track record, so it is not
          // the sum of the two cells beside it.
          const _Times(symbol: '→'),
          _ScoreCell(
            label: match.breakdown.recommendation == null
                ? 'Final'
                : 'Recommendation',
            value: match.scorePercent,
            color: AppColors.cyanDark,
            emphasised: true,
          ),
        ],
      ),
    );
  }
}

class _Times extends StatelessWidget {
  const _Times({this.symbol = '+'});

  final String symbol;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm),
      child: Text(
        symbol,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.hint,
        ),
      ),
    );
  }
}

class _ScoreCell extends StatelessWidget {
  const _ScoreCell({
    required this.label,
    required this.value,
    required this.color,
    this.emphasised = false,
  });

  final String label;
  final int value;
  final Color color;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            '$value%',
            style: TextStyle(
              fontSize: emphasised ? 20 : 16,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StageBlock extends StatelessWidget {
  const _StageBlock({
    required this.title,
    required this.blurb,
    required this.weightLabel,
    required this.stage,
  });

  final String title;
  final String blurb;
  final String weightLabel;
  final ScoreStage stage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.panelRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                '${stage.percent}%',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            weightLabel,
            style: AppTextStyles.caption.copyWith(fontSize: 12),
          ),
          const SizedBox(height: AppSizes.sm),
          Text(blurb, style: AppTextStyles.caption),
          const SizedBox(height: AppSizes.lg),
          if (stage.factors.isEmpty)
            Text(
              'No factors were recorded for this stage.',
              style: AppTextStyles.caption,
            )
          else
            ...stage.factors.map(
              (ScoreFactor factor) => ScoreFactorBar(factor: factor),
            ),
        ],
      ),
    );
  }
}

/// The live conditions the engine saw, shown so a low score has a visible
/// cause rather than looking arbitrary.
class _ContextBlock extends StatelessWidget {
  const _ContextBlock({required this.context});

  final MatchContext context;

  @override
  Widget build(BuildContext buildContext) {
    final List<(String, String)> rows = <(String, String)>[
      if (context.distanceLabel != null) ('Distance', context.distanceLabel!),
      if (context.etaLabel != null) ('Estimated travel', context.etaLabel!),
      if (context.trafficLabel != null) ('Traffic now', context.trafficLabel!),
      if (context.weatherLabel != null) ('Weather now', context.weatherLabel!),
      if (context.workload != null)
        ('Active jobs', '${context.workload} in progress'),
      if (context.similarRepairs != null)
        ('Similar repairs', '${context.similarRepairs} completed'),
      if (context.diagnosisAccuracy != null)
        (
          'Diagnosis accuracy',
          '${(context.diagnosisAccuracy! * 100).round()}%',
        ),
    ];

    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: AppColors.primarySofter,
        borderRadius: BorderRadius.circular(AppSizes.panelRadius),
        border: Border.all(color: AppColors.primarySoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Conditions when this was scored',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: AppSizes.md),
          ...rows.map(
            ((String, String) row) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    row.$1,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    row.$2,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (context.isColdStart) ...<Widget>[
            const SizedBox(height: AppSizes.sm),
            const Text(
              'This technician is newly verified with no completed jobs yet, '
              'so their accuracy was scored at the neutral prior rather than '
              'at zero.',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
