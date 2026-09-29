import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/technician.dart';
import 'technician_avatar.dart';

/// The technician card, shared by both listings.
///
/// ## One widget, two arrangements
///
/// Recommended technicians and task matching show the SAME facts - avatar, a
/// "New" badge when applicable, name, the specific registered specialisation,
/// completed job count and distance - so they share one widget rather than two
/// that drift apart.
///
/// They do not share a shape, because the surfaces are not the same shape: the
/// dashboard scrolls horizontally and gives a card ~176 logical pixels, while
/// task matching is a full-width vertical list that also has to show a rank.
/// Hence two constructors over one set of content builders:
///
/// * [TechnicianCard.compact] - the dashboard's narrow portrait card.
/// * [TechnicianCard.row] - the full-width match row, with the Top 3 ribbon.
///
/// ## What the card deliberately does not show
///
/// No match score, no workload, no phone number. A score belongs to the RB-CARS
/// explainability sheet where it can be justified; the other two are private.
///
/// ## Dispatch pass (2026-09-29)
///
/// Every size is on the type scale now - the name 15, everything else 12.
/// The card used 9.5 to 13.5 across seven hand-typed sizes. The orange words
/// ("New", the vacation line) use the text orange: the bright one is about 2:1
/// on white.
class TechnicianCard extends StatelessWidget {
  const TechnicianCard.compact({
    super.key,
    required this.technician,
    this.onTap,
  }) : _wide = false;

  const TechnicianCard.row({super.key, required this.technician, this.onTap})
    : _wide = true;

  final Technician technician;
  final VoidCallback? onTap;

  final bool _wide;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(AppSizes.tileRadius);

    // The Top 3 get a brand-tinted border instead of a heavier shadow or a
    // coloured fill: it marks them at a glance without making the technicians
    // below look disabled, which is the failure mode of a "highlighted" row.
    final bool highlight = technician.isTopMatch;

    return Material(
      color: AppColors.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          width: _wide ? null : AppSizes.technicianCardWidth,
          padding: const EdgeInsets.all(AppSizes.md),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: highlight ? AppColors.primary : AppColors.border,
              width: highlight ? 1.4 : 1,
            ),
          ),
          child: _wide ? _buildRow(context) : _buildCompact(context),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- compact

  Widget _buildCompact(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // The pill takes what the avatar leaves and shortens inside it; with
        // a Spacer it pushed past the card's edge at large text.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TechnicianAvatar(technician: technician, size: 44),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: Align(
                alignment: Alignment.topRight,
                child: _RatingPill(technician: technician),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSizes.sm),
        _NameLine(technician: technician),
        const SizedBox(height: 2),
        _SpecializationLine(technician: technician),
        const SizedBox(height: AppSizes.sm),
        _Fact(
          icon: Icons.build_rounded,
          text: _jobsLabel,
        ),
        // The dashboard row has a fixed height with room for two fact lines.
        // A vacation takes the distance line's place rather than adding a
        // third: "cannot be booked" matters more than how far away they are.
        if (technician.isAway) ...<Widget>[
          const SizedBox(height: 3),
          _VacationFact(label: technician.awayLabel!),
        ] else if (technician.distanceAwayLabel != null) ...<Widget>[
          const SizedBox(height: 3),
          _Fact(
            icon: Icons.place_rounded,
            text: technician.distanceAwayLabel!,
          ),
        ],
      ],
    );
  }

  // ------------------------------------------------------------------- row

  Widget _buildRow(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (technician.isTopMatch) ...<Widget>[
          _TopMatchRibbon(rank: technician.matchRank),
          const SizedBox(height: AppSizes.sm),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TechnicianAvatar(technician: technician, size: 52),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _NameLine(technician: technician),
                  const SizedBox(height: 2),
                  _SpecializationLine(technician: technician),
                  const SizedBox(height: AppSizes.sm),
                  // Wrap, not Row: at 400px with a long distance string and a
                  // four-digit job count these would otherwise overflow.
                  Wrap(
                    spacing: AppSizes.md,
                    runSpacing: 4,
                    children: <Widget>[
                      _Fact(icon: Icons.build_rounded, text: _jobsLabel),
                      if (technician.distanceAwayLabel != null)
                        _Fact(
                          icon: Icons.place_rounded,
                          text: technician.distanceAwayLabel!,
                        ),
                      if (technician.isAway)
                        _VacationFact(label: technician.awayLabel!),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            _RatingPill(technician: technician),
          ],
        ),
      ],
    );
  }

  /// "12 jobs" / "1 job" / "No jobs yet".
  ///
  /// Zero reads as "No jobs yet" rather than "0 jobs": the card already carries
  /// a "New" badge, and two negative-sounding statements about the same fact
  /// makes a qualified newcomer look worse than they are.
  String get _jobsLabel {
    final int jobs = technician.totalJobs;
    if (jobs == 0) return 'No jobs yet';
    return '$jobs job${jobs == 1 ? '' : 's'} done';
  }
}

/// Name, with the "New" badge beside it when they have no completed jobs.
class _NameLine extends StatelessWidget {
  const _NameLine({required this.technician});

  final Technician technician;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Flexible(
          child: Text(
            technician.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.titleSmall,
          ),
        ),
        if (technician.isNew) ...<Widget>[
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(AppSizes.pillRadius),
            ),
            child: Text(
              'New',
              style: AppTextStyles.micro.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.accentDark,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The specific registered specialisation, e.g. "Laptop Repair".
///
/// In the brand blue so it reads as a qualification rather than as body text.
class _SpecializationLine extends StatelessWidget {
  const _SpecializationLine({required this.technician});

  final Technician technician;

  @override
  Widget build(BuildContext context) {
    return Text(
      technician.specializationLabel,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyles.micro.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.primary,
      ),
    );
  }
}

/// Average rating, or "New" when there is nothing to average.
///
/// Showing 0.0 for an unrated technician would be read as a bad score rather
/// than as an absent one.
class _RatingPill extends StatelessWidget {
  const _RatingPill({required this.technician});

  final Technician technician;

  @override
  Widget build(BuildContext context) {
    final bool rated = technician.rating > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: rated ? AppColors.warningSoft : AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            rated ? Icons.star_rounded : Icons.auto_awesome_rounded,
            size: 12,
            color: rated ? AppColors.accent : AppColors.primary,
          ),
          const SizedBox(width: 3),
          Text(
            rated ? technician.rating.toStringAsFixed(1) : 'New',
            style: AppTextStyles.micro.copyWith(
              fontWeight: FontWeight.w700,
              color: rated ? AppColors.textPrimary : AppColors.primary,
            ),
          ),
          if (rated && technician.reviewCount > 0) ...<Widget>[
            const SizedBox(width: 3),
            // The count gives way first: the rating is the fact that matters.
            Flexible(
              child: Text(
                '(${technician.reviewCount})',
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: AppTextStyles.micro.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Top match #1" strip above the Top 3 rows.
class _TopMatchRibbon extends StatelessWidget {
  const _TopMatchRibbon({required this.rank});

  final int? rank;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.workspace_premium_rounded,
            size: 12,
            color: AppColors.primary,
          ),
          const SizedBox(width: 4),
          Text(
            rank == null ? 'Top match' : 'Top match #$rank',
            style: AppTextStyles.micro.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// "On vacation until Sep 27", in the accent colour so it reads as a status
/// rather than one more fact. The card stays tappable: the profile explains
/// and shows the dates, and booking is refused there and on the server.
class _VacationFact extends StatelessWidget {
  const _VacationFact({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(
          Icons.beach_access_rounded,
          size: 13,
          color: AppColors.accentDark,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.micro.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.accentDark,
            ),
          ),
        ),
      ],
    );
  }
}

/// One small icon and the fact beside it.
class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 13, color: AppColors.hint),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.micro.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
