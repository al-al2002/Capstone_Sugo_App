import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../theme/app_text_styles.dart';

/// Thin wrapper around SnackBars so success and error messaging look the same
/// everywhere.
///
/// ## The redesign's two additions
///
/// **Every message is a navy card with a coloured icon**, rather than a
/// full-bleed red or green bar. A solid red slab is alarming out of proportion
/// to "Could not load technicians", and a green one for "Saved" shouts about
/// something the user already expected. The icon carries the tone; the card
/// stays calm.
///
/// **An optional action.** "Photo upload failed" is only half a message
/// without "Retry" beside it - the brief's rule for errors is to say what
/// happened *and* what the user can do, and the action is the second half.
class UiFeedback {
  const UiFeedback._();

  static void showError(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _show(
      context,
      message,
      Icons.error_rounded,
      const Color(0xFFFF8A8A),
      actionLabel: actionLabel,
      onAction: onAction,
      duration: const Duration(seconds: 6),
    );
  }

  static void showSuccess(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _show(
      context,
      message,
      Icons.check_circle_rounded,
      const Color(0xFF6EE7A0),
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void showInfo(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _show(
      context,
      message,
      Icons.info_rounded,
      const Color(0xFF9CC0FF),
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void showWarning(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _show(
      context,
      message,
      Icons.warning_rounded,
      const Color(0xFFFFC56B),
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void _show(
    BuildContext context,
    String message,
    IconData icon,
    Color iconColor, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 4),
  }) {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: AppColors.navy,
        duration: duration,
        margin: const EdgeInsets.fromLTRB(
          AppSizes.lg,
          0,
          AppSizes.lg,
          AppSizes.lg,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.lg,
          vertical: AppSizes.md,
        ),
        action: actionLabel == null || onAction == null
            ? null
            : SnackBarAction(
                label: actionLabel,
                textColor: const Color(0xFF9CC0FF),
                onPressed: onAction,
              ),
        content: Row(
          children: <Widget>[
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
