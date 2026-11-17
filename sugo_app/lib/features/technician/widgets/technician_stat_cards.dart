import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_elevation.dart';
import '../../rb_cars/models/technician.dart';

/// "This week": four figures in a row, each on a tinted circle.
///
/// Four across in one panel rather than a two-by-two grid of cards: they are
/// read together, as a glance at the week, and one row puts them all above
/// the fold under the availability card.
///
/// Colours come from the app's own palette - brand blue, navy and the accent
/// orange - so the dashboard reads as the same product as every other screen.
///
/// Earnings are an **estimate**, and the caption says so. The RB-CARS schema
/// records no payments at all - `job_outcomes` stores a rating, a diagnosis
/// verdict and a reroute flag - so the figure is completed jobs multiplied by
/// the tier's published rate. Labelling it honestly is better than printing a
/// number that looks like banked cash.
class TechnicianStatCards extends StatelessWidget {
  const TechnicianStatCards({
    super.key,
    required this.technician,
    required this.earningsToday,
    required this.jobsThisWeek,
    this.onCover = false,
  });

  final Technician technician;
  final int earningsToday;
  final int jobsThisWeek;

  /// A glass strip inside the dashboard's navy header (2026-11-16): white
  /// figures divided by hairlines, the week read at a glance beside the
  /// availability it depends on. Off, it is the white panel it always was.
  final bool onCover;

  @override
  Widget build(BuildContext context) {
    final bool rated = technician.rating > 0;

    if (onCover) {
      return _CoverStats(
        cells: <(IconData, String, String, Color)>[
          (
            Icons.payments_rounded,
            '₱${NumberFormat('#,##0').format(earningsToday)}',
            'today · est.',
            const Color(0xFF7DD3FC),
          ),
          (
            Icons.event_available_rounded,
            '$jobsThisWeek',
            jobsThisWeek == 1 ? 'job this week' : 'jobs this week',
            const Color(0xFF34D399),
          ),
          (
            Icons.star_rounded,
            rated ? technician.rating.toStringAsFixed(1) : 'New',
            rated ? 'rating' : 'no ratings yet',
            AppColors.accent,
          ),
          (
            Icons.workspace_premium_rounded,
            technician.tier.label,
            'tier',
            const Color(0xFFC4B5FD),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.sm,
        vertical: AppSizes.lg,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.panelRadius),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppElevation.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Stat(
            icon: Icons.payments_rounded,
            value: '₱${NumberFormat('#,##0').format(earningsToday)}',
            caption: 'today · est.',
            tint: AppColors.primarySoft,
            color: AppColors.primary,
          ),
          _Stat(
            icon: Icons.event_available_rounded,
            value: '$jobsThisWeek',
            caption: jobsThisWeek == 1 ? 'job this week' : 'jobs this week',
            tint: AppColors.navy.withValues(alpha: 0.08),
            color: AppColors.navy,
          ),
          _Stat(
            icon: Icons.star_rounded,
            value: rated ? technician.rating.toStringAsFixed(1) : 'New',
            caption: rated ? 'rating' : 'no ratings yet',
            tint: AppColors.accentSofter,
            color: AppColors.accent,
          ),
          _Stat(
            icon: Icons.workspace_premium_rounded,
            value: technician.tier.label,
            caption: 'tier',
            tint: AppColors.primarySofter,
            color: AppColors.primaryDark,
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.value,
    required this.caption,
    required this.tint,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String caption;
  final Color tint;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            child: Icon(icon, size: 24, color: color),
          ),
          const SizedBox(height: AppSizes.sm),
          // Scaled down rather than wrapped: "₱12,500" or "Standard" must stay
          // on one line in a quarter of a small phone.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            caption,
            maxLines: 2,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              height: 1.25,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The four figures as a glass strip on navy. The icon colours are light
/// tints of the white-card ones, because the card colours are text colours
/// for white and sink into navy.
class _CoverStats extends StatelessWidget {
  const _CoverStats({required this.cells});

  final List<(IconData, String, String, Color)> cells;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Navy-tinted glass, not clear: the skyline's lit windows behind it
      // competed with the captions.
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppSizes.radius + 4),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < cells.length; i++) ...<Widget>[
              if (i > 0)
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  indent: AppSizes.md,
                  endIndent: AppSizes.md,
                  color: Colors.white.withValues(alpha: 0.14),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.xs,
                    vertical: AppSizes.md,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(cells[i].$1, size: 17, color: cells[i].$4),
                      const SizedBox(height: 4),
                      // Scaled down rather than wrapped: "₱12,500" or
                      // "Standard" stays on one line in a quarter of a phone.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          cells[i].$2,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        cells[i].$3,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.25,
                          color: Colors.white.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
