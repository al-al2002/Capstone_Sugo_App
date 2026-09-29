import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/theme/app_elevation.dart';
import '../../../../core/theme/app_text_styles.dart';

/// The white, top-rounded sheet that holds an auth form.
class AuthCard extends StatelessWidget {
  const AuthCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSizes.cardRadius),
        ),
        // The sheet casts upward onto the hero behind it. Reusing the nav
        // bar's shadow rather than a one-off keeps every upward-casting
        // surface in the app on the same two-layer recipe.
        boxShadow: AppElevation.navBar,
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPadding,
        AppSizes.xl,
        AppSizes.screenPadding,
        AppSizes.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // No drag handle here, deliberately. This sheet does not drag - it
          // is a static panel over the hero - and a grabber on it would
          // promise a gesture that does nothing. It would also cost 20px on
          // the most height-constrained screen in the app, where the register
          // form already has to fit five fields and a button.
          //
          // Promoted from `headline` to `display`: this is the first line on
          // the first screen, and it should read like a greeting rather than a
          // section label.
          Text(title, style: AppTextStyles.headline),
          const SizedBox(height: AppSizes.xs + 2),
          Text(subtitle, style: AppTextStyles.subtitle),
          const SizedBox(height: AppSizes.xl),
          ...children,
        ],
      ),
    );
  }
}
