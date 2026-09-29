import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../theme/app_text_styles.dart';

/// The standard top bar for a pushed screen.
///
/// ## Why not a bare `AppBar`
///
/// Screens were passing `AppBar(title: Text(..., style: TextStyle(fontSize:
/// 15.5, fontWeight: w800)))` with a slightly different size and weight each
/// time, and some set a white background while others left the page tint. This
/// fixes the three things a top bar should never vary on - the title style,
/// the back affordance, the background - and leaves the screen to supply only
/// what is actually its own: the words and the actions.
///
/// An optional [subtitle] sits under the title for context ("Booking
/// #SUGO-2487", "Laptop / PC · Confirmed"), which is what stops two screens
/// with the same title being indistinguishable.
///
/// Since the Dispatch redesign the title sits left, beside the back arrow, at
/// the scale's 20px title size - the Android pattern, and where the eye
/// already is after tapping back.
class SugoAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SugoAppBar({
    super.key,
    this.title,
    this.subtitle,
    this.titleWidget,
    this.actions,
    this.onBack,
    this.surface = false,
    this.showDivider = false,
    this.centerTitle = false,
    this.bottom,
    this.automaticallyImplyLeading = true,
  });

  final String? title;
  final String? subtitle;

  /// Replaces [title]/[subtitle] entirely, e.g. an avatar row in a chat.
  final Widget? titleWidget;

  final List<Widget>? actions;

  /// Overrides the default pop, e.g. to confirm before leaving a form.
  final VoidCallback? onBack;

  /// White bar (for screens whose body is mostly white) instead of the page
  /// ground.
  final bool surface;

  /// Hairline under the bar. Useful when content scrolls beneath it.
  final bool showDivider;

  final bool centerTitle;
  final PreferredSizeWidget? bottom;
  final bool automaticallyImplyLeading;

  @override
  Size get preferredSize => Size.fromHeight(
    kToolbarHeight + (subtitle != null ? 6 : 0) +
        (bottom?.preferredSize.height ?? 0),
  );

  @override
  Widget build(BuildContext context) {
    final bool canPop = ModalRoute.of(context)?.canPop ?? false;

    Widget? leading;
    if (automaticallyImplyLeading && (canPop || onBack != null)) {
      leading = IconButton(
        tooltip: 'Back',
        onPressed: onBack ?? () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
      );
    }

    final Widget? heading =
        titleWidget ??
        (title == null
            ? null
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: centerTitle
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.title,
                  ),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: 1),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.micro,
                    ),
                  ],
                ],
              ));

    return AppBar(
      backgroundColor: surface ? AppColors.surface : AppColors.background,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      toolbarHeight: kToolbarHeight + (subtitle != null ? 6 : 0),
      centerTitle: centerTitle,
      automaticallyImplyLeading: false,
      leading: leading,
      titleSpacing: leading == null ? AppSizes.screenPadding : 0,
      title: heading,
      actions: actions == null
          ? null
          : <Widget>[...actions!, const SizedBox(width: AppSizes.sm)],
      shape: showDivider
          ? const Border(bottom: BorderSide(color: AppColors.divider))
          : null,
      bottom: bottom,
    );
  }
}
