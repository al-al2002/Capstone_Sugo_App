import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_button.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_pill.dart';
import '../models/match_result.dart';
import '../models/score_breakdown.dart';
import '../models/technician.dart';
import 'score_indicator.dart';
import 'technician_avatar.dart';

/// One of the Top 3 on the client review screen - a recommendation card.
///
/// ## What a client reads, top to bottom
///
/// 1. **Where it ranks** - "Recommended", "Alternative", "Another match", with
///    the recommendation score. Neutral words on purpose: the ranking knows
///    who fits this request, not who is the best technician.
/// 2. **Who** - photo, name, verified mark, specialisation, rating and jobs.
/// 3. **Now** - distance, and whether they are free.
/// 4. **How well** - Match (Stage 1) and Acceptance likelihood (Stage 2) as
///    bars and one sentence of words, never a formula.
/// 5. **Why** - the engine's two strongest reasons as a checklist, any
///    caveat under them, and a link to the full "Why this technician?" sheet.
/// 6. **Act** - View profile, Book.
///
/// Every state the old card handled is kept: declined (dimmed, no button),
/// requested and waiting (a note instead of a button), on vacation (a notice
/// instead of a button).
///
/// ## The Dispatch card (2026-09-29)
///
/// Flat, with the hairline edge; the top pick's edge is cyan, the colour the
/// palette reserves for "recommended". The rank is a line of text with a dot
/// rather than a bordered pill, and the reasons moved from an italic quote to
/// a checklist - a quote reads as a testimonial, which it is not; a list
/// reads as what it is, the engine's findings. Every size is on the scale.
class MatchScoreCard extends StatelessWidget {
  const MatchScoreCard({
    super.key,
    required this.match,
    this.onTap,
    this.onWhyTap,
    this.onSelect,
    this.selectLabel = 'Book now',
    this.highlighted = false,
  });

  final MatchResult match;

  /// Opens the technician's profile - the card and the View profile button.
  final VoidCallback? onTap;

  /// Opens "Why this technician?".
  final VoidCallback? onWhyTap;
  final VoidCallback? onSelect;
  final String selectLabel;

  /// True for the technician the client arrived with pre-selected.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final Technician? technician = match.technician;
    final bool declined = match.isDeclined;
    final bool away = technician?.isAway ?? false;

    return Opacity(
      opacity: declined ? 0.55 : 1,
      child: SugoCard(
        margin: const EdgeInsets.only(bottom: AppSizes.md),
        onTap: declined ? null : onTap,
        borderColor: match.isTopPick && !declined
            ? AppColors.cyan
            : highlighted
            // The text orange as a 1.5px edge: the bright one is 2.1:1
            // against white, too faint to mark anything.
            ? AppColors.accentDark
            : null,
        borderWidth: match.isTopPick || highlighted ? 1.5 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // A Wrap, not a Row with a Spacer: on a 320dp phone at large text
            // the rank and the vacation label do not fit on one line.
            Wrap(
              spacing: AppSizes.sm,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                _RankLine(match: match, declined: declined),
                // A label, not a reason to hide them: the matcher still ranks
                // a technician on vacation, and the client should see who
                // they cannot have and why.
                if (away)
                  SugoPill.badge(
                    label: 'On vacation',
                    icon: Icons.beach_access_rounded,
                    tint: AppColors.accentSofter,
                    foreground: AppColors.accentDark,
                  ),
              ],
            ),
            const SizedBox(height: AppSizes.md),

            _Identity(technician: technician),
            const SizedBox(height: AppSizes.md),

            _NowRow(match: match, technician: technician),
            const SizedBox(height: AppSizes.md),

            ScoreIndicator(
              label: 'Match',
              percent: match.suitabilityPercent,
              qualifier: suitabilityQualifier(match.suitabilityPercent),
              muted: declined,
            ),
            const SizedBox(height: AppSizes.sm),
            ScoreIndicator(
              label: 'Acceptance',
              percent: match.acceptancePercent,
              qualifier: acceptanceQualifier(match.acceptancePercent),
              muted: declined,
            ),
            const SizedBox(height: 6),
            Text(
              '${suitabilityQualifier(match.suitabilityPercent)} · '
              '${acceptanceQualifier(match.acceptancePercent).toLowerCase()} '
              'of accepting',
              style: AppTextStyles.micro.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.cyanDark,
              ),
            ),

            _Reasons(reasons: match.breakdown.reasons),

            if (onWhyTap != null && !declined) _WhyLink(onTap: onWhyTap!),

            ..._footer(technician),
          ],
        ),
      ),
    );
  }

  List<Widget> _footer(Technician? technician) {
    if (match.isDeclined) {
      return const <Widget>[
        SizedBox(height: AppSizes.md),
        _Note(
          icon: Icons.do_not_disturb_on_outlined,
          text: 'Unavailable for this job',
          tint: AppColors.divider,
          foreground: AppColors.textSecondary,
        ),
      ];
    }

    if (match.isAwaitingTechnician) {
      // No button: the server refuses a second selection of the same match.
      // The other cards keep theirs - `select` retires an outstanding offer
      // before promoting a new one, so switching is genuinely allowed.
      return <Widget>[
        const SizedBox(height: AppSizes.md),
        const _Note(
          icon: Icons.hourglass_top_rounded,
          text: 'Request sent — waiting for them to accept',
          tint: AppColors.primarySoft,
          foreground: AppColors.primaryDark,
        ),
        if (onTap != null) ...<Widget>[
          const SizedBox(height: AppSizes.sm),
          SugoButton(
            label: 'View profile',
            variant: SugoButtonVariant.outlined,
            size: SugoButtonSize.medium,
            onPressed: onTap,
          ),
        ],
      ];
    }

    if (technician != null && technician.isAway) {
      // No Book button. `job-response` would refuse it; saying so here, with
      // the date, lets the client choose someone else instead.
      return <Widget>[
        const SizedBox(height: AppSizes.md),
        _Note(
          icon: Icons.beach_access_rounded,
          text:
              '${technician.awayLabel} - cannot be booked. '
              'Choose another technician.',
          tint: AppColors.accentSofter,
          foreground: AppColors.textPrimary,
          iconColor: AppColors.accentDark,
        ),
      ];
    }

    if (onSelect == null && onTap == null) return const <Widget>[];

    return <Widget>[
      const SizedBox(height: AppSizes.md),
      Row(
        children: <Widget>[
          if (onTap != null)
            Expanded(
              child: SugoButton(
                label: 'View profile',
                variant: SugoButtonVariant.outlined,
                size: SugoButtonSize.medium,
                onPressed: onTap,
              ),
            ),
          if (onTap != null && onSelect != null)
            const SizedBox(width: AppSizes.sm),
          if (onSelect != null)
            Expanded(
              child: SugoButton(
                label: selectLabel,
                size: SugoButtonSize.medium,
                onPressed: onSelect,
              ),
            ),
        ],
      ),
    ];
  }
}

/// "● Recommended for you · 92%", "Alternative · 88%", "Another match · 84%".
///
/// A line of text rather than a bordered pill: the card's cyan edge already
/// marks the top pick, and a pill inside an edged card was a box in a box.
class _RankLine extends StatelessWidget {
  const _RankLine({required this.match, required this.declined});

  final MatchResult match;
  final bool declined;

  @override
  Widget build(BuildContext context) {
    final bool top = match.isTopPick && !declined;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: top ? AppColors.cyan : AppColors.border,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            top
                ? '${match.rankLabel} for you · ${match.recommendationPercent}%'
                : '${match.rankLabel} · ${match.recommendationPercent}%',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.micro.copyWith(
              fontWeight: FontWeight.w700,
              color: top ? AppColors.cyanDark : AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Photo, name with verified mark, specialisation, rating and jobs.
class _Identity extends StatelessWidget {
  const _Identity({required this.technician});

  final Technician? technician;

  @override
  Widget build(BuildContext context) {
    final Technician? t = technician;
    final double rating = t?.rating ?? 0;
    final int jobs = t?.totalJobs ?? 0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (t != null) ...<Widget>[
          TechnicianAvatar(technician: t, size: AppSizes.avatarMd),
          const SizedBox(width: AppSizes.md),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      t?.displayName ?? 'SUGO technician',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.sectionTitle,
                    ),
                  ),
                  if (t?.isVerified ?? false) ...<Widget>[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.verified_rounded,
                      size: 17,
                      color: AppColors.secondary,
                      semanticLabel: 'ID verified',
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                t?.headline ?? 'Repair technician',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption,
              ),
              const SizedBox(height: AppSizes.xs),
              Row(
                children: <Widget>[
                  if (rating > 0) ...<Widget>[
                    const Icon(
                      Icons.star_rounded,
                      size: 16,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      rating.toStringAsFixed(1),
                      style: AppTextStyles.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const _Dot(),
                  ],
                  Flexible(
                    child: Text(
                      jobs > 0
                          ? '$jobs job${jobs == 1 ? '' : 's'} done'
                          : 'New on SUGO',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Distance, and whether they are free - the two things that change hourly.
class _NowRow extends StatelessWidget {
  const _NowRow({required this.match, required this.technician});

  final MatchResult match;
  final Technician? technician;

  @override
  Widget build(BuildContext context) {
    final String? distance = match.breakdown.context.distanceLabel;
    final int? workload = match.breakdown.context.workload;
    final bool away = technician?.isAway ?? false;

    // Honest wording. There is no live "online" signal any more - the switch
    // was retired - so "free" means no job in progress and no time off.
    final (String, Color)? availability = away
        ? null
        : workload == null
        ? null
        : workload == 0
        ? ('Available today', AppColors.success)
        : ('$workload job${workload == 1 ? '' : 's'} in progress',
              AppColors.warning);

    return Wrap(
      spacing: AppSizes.lg,
      runSpacing: 6,
      children: <Widget>[
        if (distance != null)
          _Meta(
            icon: Icons.place_rounded,
            iconColor: AppColors.secondary,
            label: distance,
          ),
        if (availability != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: availability.$2,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                availability.$1,
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: availability.$2,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// The engine's two strongest reasons as ticks, and its first caveat under
/// them. The same two reasons the card used to quote, now as a list.
class _Reasons extends StatelessWidget {
  const _Reasons({required this.reasons});

  final List<RecommendationReason> reasons;

  @override
  Widget build(BuildContext context) {
    final List<RecommendationReason> positives = reasons
        .where((RecommendationReason r) => !r.isCaveat && r.text.isNotEmpty)
        .take(2)
        .toList();
    final RecommendationReason? caveat = reasons
        .where((RecommendationReason r) => r.isCaveat && r.text.isNotEmpty)
        .firstOrNull;

    if (positives.isEmpty && caveat == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSizes.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final RecommendationReason reason in positives)
            _ReasonRow(
              icon: Icons.check_rounded,
              iconColor: AppColors.success,
              text: reason.text,
            ),
          if (caveat != null)
            _ReasonRow(
              icon: Icons.info_outline_rounded,
              iconColor: AppColors.accentDark,
              text: caveat.text,
            ),
        ],
      ),
    );
  }
}

class _ReasonRow extends StatelessWidget {
  const _ReasonRow({
    required this.icon,
    required this.iconColor,
    required this.text,
  });

  final IconData icon;
  final Color iconColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label, this.iconColor});

  final IconData icon;
  final String label;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 16, color: iconColor ?? AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        '·',
        style: AppTextStyles.caption.copyWith(color: AppColors.hint),
      ),
    );
  }
}

class _WhyLink extends StatelessWidget {
  const _WhyLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
        icon: const Icon(Icons.help_outline_rounded, size: 16),
        label: const Text('Why this technician?'),
      ),
    );
  }
}

/// Stands where the buttons would be, when there is nothing to press.
class _Note extends StatelessWidget {
  const _Note({
    required this.icon,
    required this.text,
    required this.tint,
    required this.foreground,
    this.iconColor,
  });

  final IconData icon;
  final String text;
  final Color tint;
  final Color foreground;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.sm + 2,
      ),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(AppSizes.radius),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: iconColor ?? foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: foreground,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
