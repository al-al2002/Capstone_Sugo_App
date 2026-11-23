import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_button.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_pill.dart';
import '../models/match_result.dart';
import '../models/preference_match.dart';
import '../models/score_breakdown.dart';
import '../models/technician.dart';
import '../models/technician_preferences.dart';
import 'trust_badge_pill.dart';
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
    this.preferences,
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

  /// The client's must-haves from posting. When any are set, the card shows
  /// each one with this technician's own value - the pre-filter already
  /// removed anyone who failed one, so this says WHY they qualify.
  final TechnicianPreferences? preferences;

  @override
  Widget build(BuildContext context) {
    final Technician? technician = match.technician;
    final bool declined = match.isDeclined;
    final bool away = technician?.isAway ?? false;
    final bool top = match.isTopPick && !declined;

    final Widget card = SugoCard(
      margin: top ? null : const EdgeInsets.only(bottom: AppSizes.md),
      onTap: declined ? null : onTap,
      // The top pick (2026-11-23): a faint cyan wash fading to white, inside
      // a glowing blue-to-cyan frame (below) - it reads as the
      // recommendation before a word is read.
      gradient: top
          ? const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[AppColors.cyanSoft, AppColors.surface],
              stops: <double>[0, 0.45],
            )
          : null,
      elevation: top ? SugoElevation.flat : null,
      borderColor: top
          ? null
          : highlighted
          // The text orange as a 1.5px edge: the bright one is 2.1:1
          // against white, too faint to mark anything.
          ? AppColors.accentDark
          : null,
      borderWidth: highlighted ? 1.5 : 1,
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
                )
              // Still bookable - the client can wait for them - but they
              // should know before they choose (2026-09-29).
              else if (technician?.isBusy ?? false)
                SugoPill.badge(
                  label: 'On a job now',
                  icon: Icons.handyman_rounded,
                  tint: AppColors.warningSoft,
                  foreground: AppColors.warning,
                ),
            ],
          ),
          const SizedBox(height: AppSizes.md),

          _Identity(technician: technician),
          const SizedBox(height: AppSizes.md),

          // The client's preferences as bars (2026-11-17), in the same
          // form as Match and Acceptance below: one row per preference
          // they set, filled by how well this technician fits it.
          if (preferences?.hasAny ?? false) ...<Widget>[
            _PreferenceBars(
              bars: preferenceBars(
                preferences!,
                distanceKm:
                    match.breakdown.context.distanceKm ??
                    technician?.distanceKm,
                rating: technician?.rating,
                trustForJob: technician?.trustBadgeForJob,
                skillPercent: match.breakdown.skillPercent,
                away: technician?.isAway ?? false,
                busy: technician?.isBusy ?? false,
              ),
              muted: declined,
            ),
            const SizedBox(height: AppSizes.md),
          ],

          _TechnicianFacts(
            technician: technician,
            distanceLabel: match.breakdown.context.distanceLabel,
          ),
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
    );

    return Opacity(
      opacity: declined ? 0.55 : 1,
      child: top
          ? Container(
              margin: const EdgeInsets.only(bottom: AppSizes.md),
              padding: const EdgeInsets.all(1.8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppSizes.radius + 1.8),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[AppColors.secondary, AppColors.cyan],
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.cyan.withValues(alpha: 0.30),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: card,
            )
          : card,
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
        // The recommendation score as a ring that fills on arrival, with the
        // rank inside it (2026-11-17). It replaced an 8px dot: the number the
        // whole card is ranked by deserved more than a full stop.
        _ScoreRing(
          percent: match.recommendationPercent,
          rank: match.rank,
          top: top,
          muted: declined,
        ),
        const SizedBox(width: AppSizes.sm),
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

/// A small ring showing the recommendation score, with the rank in the
/// middle. Fills once when the card appears; still under reduced motion.
class _ScoreRing extends StatelessWidget {
  const _ScoreRing({
    required this.percent,
    required this.rank,
    required this.top,
    required this.muted,
  });

  final int percent;
  final int rank;
  final bool top;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final Color colour = muted
        ? AppColors.hint
        : top
        ? AppColors.cyanDark
        : AppColors.secondaryDark;

    return ExcludeSemantics(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: (percent / 100).clamp(0, 1)),
        duration: AppMotion.reduced(context)
            ? Duration.zero
            : const Duration(milliseconds: 700),
        curve: AppMotion.standard,
        builder: (BuildContext context, double value, Widget? child) =>
            SizedBox(
              width: 34,
              height: 34,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: CircularProgressIndicator(
                      value: value,
                      strokeWidth: 3.5,
                      strokeCap: StrokeCap.round,
                      backgroundColor: AppColors.divider,
                      color: colour,
                    ),
                  ),
                  child!,
                ],
              ),
            ),
        child: Text(
          '$rank',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: colour,
          ),
        ),
      ),
    );
  }
}

/// "Meets your must-haves" - each preference the client set while posting,
/// ticked, with this technician's own value beside it (2026-11-17).
class _PreferenceBars extends StatelessWidget {
  const _PreferenceBars({required this.bars, this.muted = false});

  final List<PreferenceBar> bars;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final int met = bars.where((PreferenceBar b) => b.met).length;
    final bool all = met == bars.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSizes.md,
        AppSizes.sm + 2,
        AppSizes.md,
        AppSizes.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.tune_rounded,
                size: 15,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Your preferences',
                  style: AppTextStyles.micro.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              SugoPill.badge(
                label: all ? 'Meets all' : '$met of ${bars.length} met',
                icon: all ? Icons.verified_rounded : Icons.info_outline_rounded,
                tint: all ? AppColors.successSoft : AppColors.warningSoft,
                foreground: all ? AppColors.success : AppColors.warning,
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm + 2),
          for (int i = 0; i < bars.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: AppSizes.sm + 2),
            ScoreIndicator(
              label: bars[i].label,
              percent: bars[i].percent,
              qualifier: bars[i].detail,
              muted: muted,
            ),
            const SizedBox(height: 3),
            Padding(
              // Under the bar, lined up with where the bar starts.
              padding: const EdgeInsets.only(left: 84),
              child: Row(
                children: <Widget>[
                  Icon(
                    bars[i].met
                        ? Icons.check_circle_rounded
                        : Icons.error_outline_rounded,
                    size: 12,
                    color: bars[i].met ? AppColors.success : AppColors.warning,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    // Two lines: "Skill verified · wants Community Trusted"
                    // was cut off at one.
                    child: Text(
                      bars[i].detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.micro.copyWith(fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
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
              // The trust badge as it applies to THIS job (20261115000002).
              // From Skill verified up only: ID verified already has the blue
              // check beside the name.
              if (t?.trustBadgeForJob case final TrustBadge badge
                  when badge.atLeast(TrustBadge.skillVerified)) ...<Widget>[
                const SizedBox(height: AppSizes.xs),
                TrustBadgePill(badge: badge, compact: true),
              ],
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

class _TechnicianFacts extends StatelessWidget {
  const _TechnicianFacts({
    required this.technician,
    required this.distanceLabel,
  });

  final Technician? technician;
  final String? distanceLabel;

  @override
  Widget build(BuildContext context) {
    final Technician? t = technician;
    final String skills = t == null || t.skillTags.isEmpty
        ? t?.specializationLabel ?? 'Not available'
        : t.skillTags.map(Technician.labelForSkill).take(3).join(', ');
    final String locationName = t?.barangay?.trim() ?? '';
    final String location = <String>[
      if (locationName.isNotEmpty) locationName,
      distanceLabel ?? t?.distanceAwayLabel ?? 'Distance unavailable',
    ].join(' · ');

    return Column(
      children: <Widget>[
        _FactRow(icon: Icons.handyman_outlined, label: 'Skills', value: skills),
        const SizedBox(height: AppSizes.xs),
        _FactRow(
          icon: Icons.location_on_outlined,
          label: 'Location:',
          value: location,
        ),
      ],
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 15, color: AppColors.secondary),
        const SizedBox(width: 6),
        // Wide enough for "Location:" on one line - at 58 the colon wrapped
        // under the word.
        SizedBox(
          width: 72,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: AppTextStyles.caption,
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
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
        : (
            '$workload job${workload == 1 ? '' : 's'} in progress',
            AppColors.warning,
          );

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
