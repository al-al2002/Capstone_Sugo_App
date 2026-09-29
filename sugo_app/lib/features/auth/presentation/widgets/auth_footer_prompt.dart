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
    // A Wrap rather than a Row: on narrow phones (or at large text scales) the
    // prompt and its action move onto separate lines instead of overflowing.
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(message, style: AppTextStyles.caption),
        // A TextButton, not a bare GestureDetector on the word: a 48dp target
        // the word alone does not give, and a pressed state. Blue text shade,
        // as in the reference - orange on white fails contrast.
        TextButton(
          onPressed: onAction,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.secondaryDark,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: const Size(0, 44),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          child: Text(
            actionLabel,
            style: AppTextStyles.link,
          ),
        ),
      ],
    );
  }
}
