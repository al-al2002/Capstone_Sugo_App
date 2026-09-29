import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../theme/app_text_styles.dart';

/// Pill-shaped chip used for filter tabs, badges and explainability lines.
///
/// Three looks, one widget:
///
/// * [SugoPill] - selectable tab. Filled with the primary colour when active,
///   outlined and muted when not.
/// * [SugoPill.badge] - a static label tinted to carry meaning, e.g. an orange
///   "Elite" badge or a green "Available today".
/// * [SugoPill.soft] - a quiet informational chip on a tinted background.
class SugoPill extends StatelessWidget {
  const SugoPill({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
  }) : _tint = null,
       _foreground = null,
       _dense = false;

  /// Meaningful, non-interactive label.
  const SugoPill.badge({
    super.key,
    required this.label,
    this.icon,
    required Color tint,
    required Color foreground,
    this.onTap,
  }) : selected = false,
       _tint = tint,
       _foreground = foreground,
       _dense = true;

  /// Quiet chip on a soft brand tint. The default for explainability lines.
  const SugoPill.soft({super.key, required this.label, this.icon, this.onTap})
    : selected = false,
      _tint = AppColors.primarySoft,
      _foreground = AppColors.primaryDark,
      _dense = true;

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  final Color? _tint;
  final Color? _foreground;
  final bool _dense;

  @override
  Widget build(BuildContext context) {
    final bool isBadge = _tint != null;

    final Color background = isBadge
        ? _tint
        : selected
        ? AppColors.primary
        : AppColors.surface;

    final Color foreground = isBadge
        // Both named constructors set the pair together, so a non-null tint
        // guarantees a non-null foreground.
        ? _foreground ?? AppColors.primaryDark
        : selected
        ? Colors.white
        : AppColors.textSecondary;

    final Widget body = Container(
      padding: EdgeInsets.symmetric(
        horizontal: _dense ? AppSizes.md : AppSizes.lg,
        vertical: _dense ? 6 : 0,
      ),
      height: _dense ? null : AppSizes.filterTabHeight,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        border: isBadge || selected
            ? null
            : Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: _dense ? 13 : 16, color: foreground),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: _dense ? 12 : 13,
                fontWeight: FontWeight.w600,
                color: foreground,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return body;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        child: body,
      ),
    );
  }
}
