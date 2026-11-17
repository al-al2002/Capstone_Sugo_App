import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../config/basic_problems.dart';

/// "This looks like a basic problem. Try the Technician Community first..."
/// (2026-11-16; in English since 2026-11-17)
///
/// Shown on the problem step when the rule base suggests the community for a
/// basic issue (`ClassificationResult.isBasic`), so the card and the
/// "Suggested" badge always agree, and on the details step when the client's
/// own words sound basic. A
/// suggestion, never a redirect: the three options stay below it, and the
/// client picks. When they have already picked the community the button
/// gives way to a quiet confirmation, so the card never nags.
///
/// The words live in `config/basic_problems.dart` with the keyword list.
class BasicProblemCard extends StatelessWidget {
  const BasicProblemCard({
    super.key,
    required this.communitySelected,
    required this.onTryCommunity,
  });

  final bool communitySelected;
  final VoidCallback onTryCommunity;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$basicProblemTitle $basicProblemMessage',
      child: Container(
        padding: const EdgeInsets.all(AppSizes.md),
        decoration: BoxDecoration(
          color: AppColors.cyanSoft,
          borderRadius: BorderRadius.circular(AppSizes.tileRadius),
          border: Border.all(color: AppColors.cyan.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(
              Icons.lightbulb_outline_rounded,
              size: 20,
              color: AppColors.cyanDark,
            ),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    basicProblemTitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    basicProblemMessage,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSizes.sm),
                  AnimatedSwitcher(
                    duration: AppMotion.base,
                    child: communitySelected
                        ? const Row(
                            key: ValueKey<String>('chosen'),
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                Icons.check_circle_rounded,
                                size: 16,
                                color: AppColors.success,
                              ),
                              SizedBox(width: 4),
                              // Flexible, so it wraps on a narrow phone or at
                              // large text instead of overflowing.
                              Flexible(
                                child: Text(
                                  'Technician Community selected - free',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.success,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ConstrainedBox(
                            key: const ValueKey<String>('offer'),
                            constraints: const BoxConstraints(
                              minHeight: AppSizes.touchTarget,
                            ),
                            child: OutlinedButton.icon(
                              onPressed: onTryCommunity,
                              icon: const Icon(Icons.groups_rounded, size: 18),
                              label: const Text('Try the community (free)'),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
