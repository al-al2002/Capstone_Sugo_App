import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';

/// The Diagnose / Repair / Done row under the tagline.
///
/// Each chip is a rounded white tile carrying a circular primary-blue icon
/// badge above its label.
class ServiceChips extends StatelessWidget {
  const ServiceChips({super.key});

  static const List<(IconData, String)> _services = <(IconData, String)>[
    (Icons.location_on_rounded, AppStrings.chipDiagnose),
    (Icons.calendar_today_rounded, AppStrings.chipRepair),
    (Icons.check_rounded, AppStrings.chipDone),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (final (IconData icon, String label) in _services)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm),
            child: _Chip(icon: icon, label: label),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          height: 44,
          width: 44,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSizes.md),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.navy.withValues(alpha: 0.10),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Center(
            child: Container(
              height: 26,
              width: 26,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 15, color: AppColors.surface),
            ),
          ),
        ),
        const SizedBox(height: AppSizes.xs),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.navy,
          ),
        ),
      ],
    );
  }
}
