import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../rb_cars/models/technician_preferences.dart';
import '../../rb_cars/models/trust_badge.dart';
import '../../rb_cars/widgets/trust_badge_pill.dart';

/// The technician's own Progressive Trust Badge, and the path to the next
/// rung.
///
/// The brief asks for the path to be transparent, so every number here is
/// the one `my_trust_badge()` returned - the same measurement the evaluator
/// used to set the badge, never a client-side estimate. A requirement that is
/// met shows a tick; one that is not shows how far there is to go.
///
/// What the card asks for depends on the rung:
///   no badge          finish identity: ID approval, confirmed email
///   ID verified       prove one specialization
///   Skill verified    the five Community Trusted thresholds
///   Community Trusted the same five, framed as what keeps it
class TrustBadgeProgressCard extends StatelessWidget {
  const TrustBadgeProgressCard({super.key, required this.progress});

  final TrustBadgeProgress progress;

  @override
  Widget build(BuildContext context) {
    final TrustBadge? level = progress.level;
    final TrustBadge? next = level == null ? TrustBadge.idVerified : level.next;

    return SugoCard(
      padding: const EdgeInsets.all(AppSizes.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // A Wrap, not a Row: on a small phone at large text the pill and
          // "Next: Community Trusted" do not fit side by side, and the next
          // rung drops to its own line instead of overflowing.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSizes.sm,
            runSpacing: AppSizes.xs,
            children: <Widget>[
              if (level != null)
                TrustBadgePill(badge: level)
              else
                Text('No badge yet', style: AppTextStyles.label),
              if (next != null)
                Text('Next: ${next.label}', style: AppTextStyles.caption),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            level == null ? TrustBadge.idVerified.blurb : level.blurb,
            style: AppTextStyles.caption,
          ),
          if (progress.skillVerified.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSizes.md),
            _SkillChips(skills: progress.skillVerified),
          ],
          const SizedBox(height: AppSizes.md),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: AppSizes.md),
          ..._requirements(level),
        ],
      ),
    );
  }

  List<Widget> _requirements(TrustBadge? level) {
    if (level == null) {
      return <Widget>[
        _Requirement(
          label: 'ID and selfie approved',
          value: progress.identityApproved ? 'Approved' : 'Waiting for review',
          met: progress.identityApproved,
        ),
        _Requirement(
          label: 'Email confirmed',
          value: progress.emailConfirmed ? 'Confirmed' : 'Not confirmed yet',
          met: progress.emailConfirmed,
        ),
      ];
    }

    if (level == TrustBadge.idVerified) {
      return const <Widget>[
        _Requirement(
          label: 'Prove one specialization',
          value: 'Pass its assessment, or upload a certificate for review',
          met: false,
        ),
      ];
    }

    final TrustThresholds t = progress.thresholds;
    final bool trusted = level == TrustBadge.communityTrusted;
    final double? rate = progress.responseRate;

    return <Widget>[
      Text(
        trusted
            ? 'Keep all five to stay Community Trusted. Falling below any '
                  'one returns you to Skill verified.'
            : progress.summary,
        style: AppTextStyles.caption.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      const SizedBox(height: AppSizes.md),
      _Requirement(
        label: 'Completed jobs',
        value: '${progress.completedJobs} / ${t.completedJobs}',
        met: progress.jobsMet,
        fraction: progress.completedJobs / t.completedJobs,
      ),
      _Requirement(
        label: 'Average rating',
        value:
            '${progress.avgRating == null ? 'No ratings yet' : progress.avgRating!.toStringAsFixed(1)}'
            ' · needs ${t.avgRating.toStringAsFixed(1)}+',
        met: progress.ratingMet,
      ),
      _Requirement(
        label: 'Response rate',
        value: rate == null
            ? 'No offers yet · needs ${(t.responseRate * 100).round()}%'
            : '${(rate * 100).round()}% · needs ${(t.responseRate * 100).round()}%',
        met: progress.responseMet,
        hint: 'Answering an offer within ${t.responseWindowHours} hours',
      ),
      _Requirement(
        label: 'Disputes',
        value: progress.disputes == 0
            ? 'None open or upheld'
            : '${progress.disputes} open or upheld',
        met: progress.disputesMet,
      ),
      _Requirement(
        label: 'Cancellations',
        value:
            '${(progress.cancellationRate * 100).round()}% · under '
            '${(t.maxCancellationRate * 100).round()}%',
        met: progress.cancellationsMet,
      ),
    ];
  }
}

class _SkillChips extends StatelessWidget {
  const _SkillChips({required this.skills});

  final List<PreferredSpecialization> skills;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSizes.xs,
      runSpacing: AppSizes.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(
          'Skill verified for',
          style: AppTextStyles.micro.copyWith(fontWeight: FontWeight.w700),
        ),
        for (final PreferredSpecialization skill in skills)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.successSoft,
              borderRadius: BorderRadius.circular(AppSizes.pillRadius),
            ),
            child: Text(
              skill.label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.success,
              ),
            ),
          ),
      ],
    );
  }
}

/// One threshold: a tick or an open circle, the label, and the number.
class _Requirement extends StatelessWidget {
  const _Requirement({
    required this.label,
    required this.value,
    required this.met,
    this.fraction,
    this.hint,
  });

  final String label;
  final String value;
  final bool met;

  /// 0..1 for a count, drawn as a bar while it is not yet met.
  final double? fraction;

  /// Small print under the row, e.g. what counts as a response.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value. ${met ? 'Met' : 'Not met yet'}.',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSizes.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              met
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 18,
              color: met ? AppColors.success : AppColors.hint,
            ),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(value, style: AppTextStyles.caption),
                  if (fraction != null && !met) ...<Widget>[
                    const SizedBox(height: AppSizes.xs),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                      child: LinearProgressIndicator(
                        value: fraction!.clamp(0, 1).toDouble(),
                        minHeight: 6,
                        backgroundColor: AppColors.divider,
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                  if (hint != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(hint!, style: AppTextStyles.micro),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
