import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';

/// One of the three figures under a technician's name: experience, rating,
/// completed jobs.
///
/// Icon on a tinted square, big value, small caption. Three of these sit in a
/// row and must stay the same height whatever the value length, so the value is
/// a single line with ellipsis rather than wrapping.
class StatChip extends StatelessWidget {
  const StatChip({
    super.key,
    required this.icon,
    required this.value,
    required this.caption,
    required this.tint,
    required this.iconColor,
  });

  /// Years on the platform.
  const StatChip.experience({super.key, required this.value})
    : icon = Icons.workspace_premium_rounded,
      caption = 'Experience',
      tint = AppColors.accentSoft,
      iconColor = AppColors.accent;

  /// Average client rating.
  const StatChip.rating({super.key, required this.value})
    : icon = Icons.star_rounded,
      caption = 'Rating',
      tint = AppColors.primarySoft,
      iconColor = AppColors.primary;

  /// Completed jobs, which doubles as the review count.
  const StatChip.jobs({super.key, required this.value})
    : icon = Icons.handyman_rounded,
      caption = 'Jobs done',
      tint = AppColors.successSoft,
      iconColor = AppColors.success;

  final IconData icon;
  final String value;
  final String caption;
  final Color tint;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: iconColor),
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
