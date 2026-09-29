import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../theme/app_text_styles.dart';

/// Opens a modal bottom sheet in the SUGO style.
///
/// Every new sheet goes through this, so four things are always true of them:
///
/// 1. **A drag handle**, the single most-missed affordance on a sheet: without
///    it, people do not know a swipe dismisses it and hunt for a close button.
/// 2. **A title row** with an explicit close button, for the people who do not
///    swipe - and for screen readers, which cannot.
/// 3. **Keyboard-aware padding.** A sheet with a text field lifts above the
///    keyboard instead of hiding its own input and submit button, which was
///    the most common layout bug across the old sheets.
/// 4. **A height cap** at 92% of the screen, so a tall sheet scrolls rather
///    than covering the status bar.
Future<T?> showSugoBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  String? subtitle,
  bool isDismissible = true,
  bool scrollable = true,
  EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(
    AppSizes.screenPadding,
    0,
    AppSizes.screenPadding,
    AppSizes.lg,
  ),
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: isDismissible,
    useSafeArea: true,
    builder: (BuildContext sheetContext) {
      final double keyboard = MediaQuery.viewInsetsOf(sheetContext).bottom;
      final double maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.92;

      final Widget body = Padding(padding: padding, child: builder(sheetContext));

      return Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const SugoSheetHandle(),
                if (title != null)
                  SugoSheetHeader(
                    title: title,
                    subtitle: subtitle,
                    onClose: isDismissible
                        ? () => Navigator.of(sheetContext).maybePop()
                        : null,
                  ),
                Flexible(
                  child: scrollable
                      ? SingleChildScrollView(child: body)
                      : body,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// The grabber at the top of a sheet.
class SugoSheetHandle extends StatelessWidget {
  const SugoSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: AppSizes.md, bottom: AppSizes.sm),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        ),
      ),
    );
  }
}

/// Title, optional subtitle and a close button, for the top of a sheet.
class SugoSheetHeader extends StatelessWidget {
  const SugoSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onClose,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPadding,
        AppSizes.xs,
        AppSizes.sm,
        AppSizes.lg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: AppTextStyles.title),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(subtitle!, style: AppTextStyles.caption),
                ],
              ],
            ),
          ),
          if (onClose != null)
            IconButton(
              tooltip: 'Close',
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded, size: 22),
              color: AppColors.textSecondary,
            ),
        ],
      ),
    );
  }
}

/// One tappable option in an action sheet: icon tile, label, optional hint.
///
/// Used for choosers like "Take photo / Choose from gallery", so every such
/// list in the app has the same rhythm and the same large targets.
class SugoSheetOption extends StatelessWidget {
  const SugoSheetOption({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.hint,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final String? hint;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final Color tint = destructive ? AppColors.errorSoft : AppColors.primarySoft;
    final Color ink = destructive ? AppColors.error : AppColors.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppSizes.md,
            horizontal: AppSizes.xs,
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: AppSizes.iconTile,
                height: AppSizes.iconTile,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(AppSizes.md),
                ),
                child: Icon(icon, size: 21, color: ink),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: AppTextStyles.titleSmall.copyWith(
                        color: destructive ? AppColors.error : null,
                      ),
                    ),
                    if (hint != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(hint!, style: AppTextStyles.micro),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.hint,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
