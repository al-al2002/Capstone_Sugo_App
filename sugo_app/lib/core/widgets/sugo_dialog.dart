import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../theme/app_text_styles.dart';
import 'sugo_button.dart';

/// Asks the user to confirm something, and returns whether they did.
///
/// ## The shape of a good confirmation
///
/// * **An icon on a tint** that says what kind of moment this is before a
///   word is read - a red bin for delete, an amber clock for "cancel your
///   request". The tint is chosen by [destructive].
/// * **The title is the question**, not "Are you sure?": "Delete this task?"
///   tells the reader what they are agreeing to; "Are you sure?" makes them
///   go back and look.
/// * **Buttons name the outcome.** "Delete" and "Keep it", never "OK" and
///   "Cancel", because "Cancel" is ambiguous on a dialog that is *about*
///   cancelling something - which several in this app are.
/// * **The safe choice is the easy one.** It sits on the left in a quieter
///   style, and a tap outside dismisses as "no".
Future<bool> showSugoConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Not now',
  bool destructive = false,
  IconData? icon,

  /// Overrides the icon's colour and the disc behind it. Deleting a request
  /// uses a black bin on grey (2026-09-28, at the client's request) - the red
  /// Delete button already says "destructive", and two reds said it twice.
  Color? iconColor,
  Color? iconTint,
}) async {
  final bool? result = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      final Color tint =
          iconTint ??
          (destructive ? AppColors.errorSoft : AppColors.primarySoft);
      final Color ink =
          iconColor ?? (destructive ? AppColors.error : AppColors.primary);

      return Dialog(
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSizes.xl,
          vertical: AppSizes.xl,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSizes.xl,
            AppSizes.xl,
            AppSizes.xl,
            AppSizes.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                child: Icon(
                  icon ??
                      (destructive
                          ? Icons.warning_amber_rounded
                          : Icons.help_outline_rounded),
                  size: 27,
                  color: ink,
                ),
              ),
              const SizedBox(height: AppSizes.lg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTextStyles.title,
              ),
              const SizedBox(height: AppSizes.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTextStyles.subtitle,
              ),
              const SizedBox(height: AppSizes.xl),
              Row(
                children: <Widget>[
                  Expanded(
                    child: SugoButton(
                      label: cancelLabel,
                      variant: SugoButtonVariant.outlined,
                      size: SugoButtonSize.medium,
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                    ),
                  ),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: SugoButton(
                      label: confirmLabel,
                      variant: destructive
                          ? SugoButtonVariant.danger
                          : SugoButtonVariant.primary,
                      size: SugoButtonSize.medium,
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  return result ?? false;
}
