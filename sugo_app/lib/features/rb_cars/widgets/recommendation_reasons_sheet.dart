import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_sheet.dart';
import '../models/match_result.dart';
import '../models/score_breakdown.dart';
import 'score_breakdown_sheet.dart';
import 'score_indicator.dart';

/// "Why this technician?" - the answer in plain sentences.
///
/// ## Two sheets, on purpose
///
/// This one is for every client: a list of ticks, each a sentence the engine
/// wrote from a real number, then anything worth knowing before booking. No
/// weights, no formulas.
///
/// `ScoreBreakdownSheet` is the other one: every factor of every stage with
/// its weight, the matching rules that fired, the live conditions. It is one
/// tap away at the bottom ("See how the score was worked out") for anyone who
/// wants it - and it is what a defence panel is shown - but a client choosing
/// a technician should not have to read it to understand the choice.
class RecommendationReasonsSheet extends StatelessWidget {
  const RecommendationReasonsSheet({super.key, required this.match});

  final MatchResult match;

  static Future<void> show(BuildContext context, MatchResult match) {
    final String name =
        match.technician?.displayName.split(' ').first ?? 'this technician';
    return showSugoBottomSheet<void>(
      context: context,
      title: 'Why we recommended $name',
      subtitle: 'Based on your request and conditions when you posted it',
      builder: (_) => RecommendationReasonsSheet(match: match),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<RecommendationReason> reasons = match.breakdown.reasons;
    final List<RecommendationReason> positives = reasons
        .where((RecommendationReason r) => !r.isCaveat)
        .toList();
    final List<RecommendationReason> caveats = reasons
        .where((RecommendationReason r) => r.isCaveat)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(AppSizes.lg),
          decoration: BoxDecoration(
            color: AppColors.cyanSoft,
            borderRadius: BorderRadius.circular(AppSizes.tileRadius),
          ),
          child: Column(
            children: <Widget>[
              ScoreIndicator(
                label: 'Match',
                percent: match.suitabilityPercent,
                qualifier: suitabilityQualifier(match.suitabilityPercent),
              ),
              const SizedBox(height: AppSizes.sm),
              ScoreIndicator(
                label: 'Acceptance',
                percent: match.acceptancePercent,
                qualifier: acceptanceQualifier(match.acceptancePercent),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSizes.lg),

        if (positives.isEmpty)
          Text(
            'They were ranked on overall fit for this repair. Nothing about '
            'them stood out enough to call out on its own.',
            style: AppTextStyles.subtitle,
          )
        else
          ...positives.map(
            (RecommendationReason r) => _ReasonRow(reason: r),
          ),

        if (caveats.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSizes.md),
          Text(
            'Good to know',
            style: AppTextStyles.titleSmall.copyWith(
              color: AppColors.accentDark,
            ),
          ),
          const SizedBox(height: AppSizes.sm),
          ...caveats.map((RecommendationReason r) => _ReasonRow(reason: r)),
        ],

        const SizedBox(height: AppSizes.md),
        Text(
          '“Acceptance” is a likelihood from their workload, distance and '
          'history - not a promise. They still choose whether to take the job.',
          style: AppTextStyles.caption,
        ),
        const SizedBox(height: AppSizes.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              // The navigator outlives this sheet; this sheet's own context
              // does not, once it is popped.
              final NavigatorState navigator = Navigator.of(context);
              navigator.pop();
              ScoreBreakdownSheet.show(navigator.context, match);
            },
            icon: const Icon(Icons.analytics_outlined, size: 17),
            label: const Text('See how the score was worked out'),
          ),
        ),
      ],
    );
  }
}

class _ReasonRow extends StatelessWidget {
  const _ReasonRow({required this.reason});

  final RecommendationReason reason;

  @override
  Widget build(BuildContext context) {
    final bool caveat = reason.isCaveat;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: caveat ? AppColors.accentSoft : AppColors.successSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              caveat ? Icons.priority_high_rounded : Icons.check_rounded,
              size: 14,
              color: caveat ? AppColors.accentDark : AppColors.success,
            ),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                reason.text,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
