import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../theme/app_text_styles.dart';
import 'sugo_card.dart';

/// A settings-style row: icon tile, title, optional subtitle, trailing slot.
///
/// Profile, Settings, Help and Saved addresses are all lists of these, which
/// is the point - four screens built from one row read as one product. The
/// old profile built its own row, the settings would have built another, and
/// the two would have drifted by a pixel here and a weight there.
class SugoListTile extends StatelessWidget {
  const SugoListTile({
    super.key,
    required this.title,
    this.icon,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconTint = AppColors.primarySoft,
    this.iconColor = AppColors.primary,
    this.destructive = false,
    this.showChevron,
  });

  final String title;
  final IconData? icon;
  final String? subtitle;

  /// Replaces the chevron: a switch, a badge, a value.
  final Widget? trailing;

  final VoidCallback? onTap;
  final Color iconTint;
  final Color iconColor;

  /// Sign out, delete account: red title and icon.
  final bool destructive;

  /// Defaults to "tappable and no custom trailing".
  final bool? showChevron;

  @override
  Widget build(BuildContext context) {
    final bool chevron = showChevron ?? (onTap != null && trailing == null);
    final Color tint = destructive ? AppColors.errorSoft : iconTint;
    final Color ink = destructive ? AppColors.error : iconColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.lg,
              vertical: AppSizes.md,
            ),
            child: Row(
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: tint,
                      borderRadius: BorderRadius.circular(AppSizes.radius),
                    ),
                    child: Icon(icon, size: 19, color: ink),
                  ),
                  const SizedBox(width: AppSizes.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        title,
                        style: AppTextStyles.titleSmall.copyWith(
                          fontWeight: FontWeight.w600,
                          color: destructive ? AppColors.error : null,
                        ),
                      ),
                      if (subtitle != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.micro,
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...<Widget>[
                  const SizedBox(width: AppSizes.sm),
                  trailing!,
                ],
                if (chevron) ...<Widget>[
                  const SizedBox(width: AppSizes.xs),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 22,
                    color: AppColors.hint,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A titled card of [SugoListTile]s separated by inset dividers.
class SugoListGroup extends StatelessWidget {
  const SugoListGroup({super.key, required this.children, this.title});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          const Padding(
            padding: EdgeInsets.only(left: 66),
            child: Divider(height: 1),
          ),
        );
      }
      rows.add(children[i]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(
              left: AppSizes.xs,
              bottom: AppSizes.sm,
            ),
            // Sentence case since the Dispatch redesign - see
            // AppTextStyles.overline.
            child: Text(title!, style: AppTextStyles.overline),
          ),
        SugoCard(
          padding: EdgeInsets.zero,
          elevation: SugoElevation.sm,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSizes.panelRadius),
            child: Column(children: rows),
          ),
        ),
      ],
    );
  }
}
