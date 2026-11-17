import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

/// "Don't have an account? Register" style footer - how the screen moves
/// between logging in and registering.
class AuthFooterPrompt extends StatelessWidget {
  const AuthFooterPrompt({
    super.key,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = constraints.maxWidth < 300;

        if (compact) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(message, style: AppTextStyles.caption),
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.secondaryDark,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 44),
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
                child: Text(actionLabel, style: AppTextStyles.link),
              ),
            ],
          );
        }

        return Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(message, style: AppTextStyles.caption),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.secondaryDark,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(0, 44),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              child: Text(actionLabel, style: AppTextStyles.link),
            ),
          ],
        );
      },
    );
  }
}
