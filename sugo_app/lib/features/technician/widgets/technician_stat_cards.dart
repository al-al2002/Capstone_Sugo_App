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
  });

  final Technician technician;
  final int earningsToday;
  final int jobsThisWeek;

  @override
  Widget build(BuildContext context) {
    final bool rated = technician.rating > 0;

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
