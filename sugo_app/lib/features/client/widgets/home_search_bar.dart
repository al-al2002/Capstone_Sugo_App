import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';

/// "What service do you need?" search field with a filter button.
///
/// Non-committal by design: tapping it starts the job posting flow rather than
/// running a text search. SUGO matches on structured answers (device, symptom,
/// damage), not free text, so a real search box would promise something the
/// engine does not do.
class HomeSearchBar extends StatelessWidget {
  const HomeSearchBar({super.key, required this.onTap, this.onFilterTap});

  final VoidCallback onTap;
  final VoidCallback? onFilterTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSizes.pillRadius),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppSizes.pillRadius),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Row(
                  children: <Widget>[
                    Icon(Icons.search_rounded, size: 19, color: AppColors.hint),
                    SizedBox(width: AppSizes.md),
                    Text(
                      'What service do you need?',
                      style: TextStyle(fontSize: 13, color: AppColors.hint),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSizes.md),
        Material(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(AppSizes.md),
          child: InkWell(
            onTap: onFilterTap ?? onTap,
            borderRadius: BorderRadius.circular(AppSizes.md),
            child: const SizedBox(
              width: 48,
              height: 48,
              child: Icon(Icons.tune_rounded, size: 20, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
