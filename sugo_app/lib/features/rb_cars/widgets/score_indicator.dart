import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';

/// One score as a client should read it: a word first, then a bar, then the
/// number.
///
/// "Strong match" is what a client needs; 92% is there for anyone who wants
/// it. The factor-by-factor working lives in `ScoreBreakdownSheet`, one tap
/// further away, so a normal card never shows a formula.
///
/// The bar fills from 0 on first build. It is a single implicit animation
/// scoped to this widget, so a score that changes rebuilds only the bar, not
/// the card around it.
class ScoreIndicator extends StatelessWidget {
  const ScoreIndicator({
    super.key,
    required this.label,
    required this.percent,
    required this.qualifier,
    this.muted = false,
  });

  /// "Match", "Acceptance".
  final String label;

  /// 0-100.
  final int percent;

  /// "Strong match", "High likelihood".
  final String qualifier;

  /// Greyed out - for a declined or unbookable card.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final double target = (percent.clamp(0, 100)) / 100;

    return Semantics(
      label: '$label: $qualifier, $percent percent',
      excludeSemantics: true,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 84,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.micro.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSizes.pillRadius),
              child: SizedBox(
                height: 7,
                child: Stack(
                  children: <Widget>[
                    const Positioned.fill(
                      child: ColoredBox(color: AppColors.divider),
                    ),
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: target),
                      // The fill is decoration; under "remove animations"
                      // the bar is drawn full at once.
                      duration: AppMotion.reduced(context)
                          ? Duration.zero
                          : AppMotion.page,
                      curve: AppMotion.emphasized,
                      builder: (BuildContext _, double value, Widget? _) =>
                          FractionallySizedBox(
                            widthFactor: value,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: muted
                                    ? null
                                    : const LinearGradient(
                                        colors: <Color>[
                                          AppColors.secondary,
                                          AppColors.cyan,
                                        ],
                                      ),
                                color: muted ? AppColors.hint : null,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSizes.sm + 2),
          Text(
            '$percent%',
            style: AppTextStyles.caption.copyWith(
              fontWeight: FontWeight.w800,
              color: muted ? AppColors.hint : AppColors.textPrimary,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// The word for a Stage 1 score. Thresholds sit on the ladder's own steps:
/// 0.80 is roughly "assessed on this device, good record".
String suitabilityQualifier(int percent) {
  if (percent >= 80) return 'Strong match';
  if (percent >= 65) return 'Good match';
  return 'Fair match';
}

/// The word for a Stage 2 score.
///
/// "Likelihood", never a promise. The engine estimates who is likely to
/// accept; it does not know, and the card must not say "will accept".
String acceptanceQualifier(int percent) {
  if (percent >= 75) return 'High likelihood';
  if (percent >= 50) return 'Moderate likelihood';
  return 'Lower likelihood';
}
