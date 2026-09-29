import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../models/score_breakdown.dart';

/// The "Matched because: ..." line under a technician's name.
///
/// This is the explainability requirement made visible. Every phrase comes from
/// a real number the engine recorded in `score_breakdown` - similar repairs,
/// distance, workload, live traffic - never from generic marketing copy. If the
/// engine sent no phrases, [ScoreBreakdown.explainabilityLine] rebuilds an
/// equivalent line from the raw context, so a card is never left with a bare
/// score and no reason.
class ExplainabilityLine extends StatelessWidget {
  const ExplainabilityLine({
    super.key,
    required this.breakdown,
    this.maxParts = 3,
    this.onTap,
  });

  final ScoreBreakdown breakdown;
  final int maxParts;

  /// Opens the full factor breakdown. Worth wiring up: it is the difference
  /// between "trust the score" and "here is the score".
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget content = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.primarySofter,
        borderRadius: BorderRadius.circular(AppSizes.md),
        border: Border.all(color: AppColors.primarySoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 14,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              breakdown.explainabilityLine(maxParts: maxParts),
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: AppColors.primaryDark,
              ),
            ),
          ),
          if (onTap != null) ...<Widget>[
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: AppColors.primary,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return content;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.md),
      child: content,
    );
  }
}

/// One factor rendered as a labelled bar, used inside the breakdown sheet.
class ScoreFactorBar extends StatelessWidget {
  const ScoreFactorBar({super.key, required this.factor});

  final ScoreFactor factor;

  Color get _barColor {
    if (factor.value >= 0.7) return AppColors.success;
    if (factor.value >= 0.4) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  factor.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                '${factor.percent}%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _barColor,
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              // The weight is shown because a high score on a 10% factor
              // matters far less than a mediocre score on a 35% one. Hiding it
              // would make the bars misleading.
              //
              // When a matching rule moved the weight, both are printed -
              // "x18%→27%" - so the effect of the situation is visible on the
              // factor it changed, not only described somewhere else.
              Text(
                factor.reweighted
                    ? 'x${(factor.baseWeight! * 100).round()}%→'
                          '${(factor.weight * 100).round()}%'
                    : 'x${(factor.weight * 100).round()}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: factor.reweighted
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: factor.reweighted
                      ? AppColors.cyanDark
                      : AppColors.hint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSizes.pillRadius),
            child: LinearProgressIndicator(
              value: factor.value.clamp(0, 1).toDouble(),
              minHeight: 6,
              backgroundColor: AppColors.divider,
              valueColor: AlwaysStoppedAnimation<Color>(_barColor),
            ),
          ),
          if (factor.note != null) ...<Widget>[
            const SizedBox(height: 5),
            Text(
              factor.note!,
              style: const TextStyle(
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
