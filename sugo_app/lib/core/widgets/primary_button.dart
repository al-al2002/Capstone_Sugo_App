import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';

/// Full-width call-to-action that swaps its label for a spinner while busy.
///
/// Built on `ElevatedButton`, whose look comes entirely from `AppTheme` - navy
/// fill, 54px, 12px radius - so this widget only adds what the theme cannot:
/// the loading state and an optional leading icon.
///
/// Since the Dispatch redesign it is flat like [SugoButton]: the glow it used
/// to cast in its own colour is gone, so the two buttons now look identical
/// and which one a screen uses makes no visible difference.
///
/// New screens should prefer [SugoButton], which covers every variant. This
/// stays because existing screens use it and their tests find it as an
/// `ElevatedButton`.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
  }) : background = null;

  const PrimaryButton.accent({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
  }) : background = AppColors.accent;

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;

  /// Null means "use the ElevatedButton style from the theme".
  final Color? background;

  @override
  Widget build(BuildContext context) {
    // Ink on the orange fill - white on it fails contrast.
    final Color foreground = background == AppColors.accent
        ? AppColors.onAccent
        : Colors.white;

    final Widget child = isLoading
        ? SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(foreground),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 19),
                const SizedBox(width: AppSizes.sm),
              ],
              Flexible(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          );

    return ElevatedButton(
      style: background == null && !isLoading
          ? null
          : ElevatedButton.styleFrom(
              backgroundColor: background ?? AppColors.primary,
              foregroundColor: foreground,
              // While loading the button keeps its colour - a spinner on a
              // greyed button reads as "broken", not "working".
              disabledBackgroundColor: isLoading
                  ? background ?? AppColors.primary
                  : AppColors.divider,
            ),
      onPressed: isLoading ? null : onPressed,
      child: child,
    );
  }
}
