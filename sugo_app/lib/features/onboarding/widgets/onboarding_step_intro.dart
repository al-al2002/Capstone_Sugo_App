import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_motion.dart';

/// The opening of every registration step (2026-11-17): what the step is
/// for, said once, with its icon on a gradient tile.
///
/// Every step used to open with a bare headline and a subtitle. One widget
/// now gives all of them the same entrance - the tile rises first, the words
/// a beat after - so a step that slides in ([OnboardingScaffold]) also
/// arrives the same way, whichever role or step it is.
class OnboardingStepIntro extends StatelessWidget {
  const OnboardingStepIntro({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SugoRiseIn(
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSizes.radius + 4),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[AppColors.primary, AppColors.secondary],
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: AppColors.secondary.withValues(alpha: 0.28),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, size: 26, color: Colors.white),
          ),
        ),
        const SizedBox(width: AppSizes.md),
        Expanded(
          child: SugoRiseIn(
            delay: AppMotion.staggerStep,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: AppTextStyles.headline),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: AppSizes.xs),
                  Text(subtitle!, style: AppTextStyles.subtitle),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
