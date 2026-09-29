import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../theme/app_elevation.dart';
import '../theme/app_motion.dart';
import '../theme/app_text_styles.dart';

/// How a [SugoIconButton] sits on the surface behind it.
enum SugoIconButtonStyle {
  /// White disc with a hairline border - header actions on the page ground.
  surface,

  /// Soft brand wash - an action inside a white card.
  tonal,

  /// Navy fill - a primary round action (send, call).
  filled,

  /// Translucent white - over a map or a dark hero.
  glass,

  /// A faint white ring and a white icon, sitting *in* a navy header rather
  /// than floating on it - the home screen's bell and inbox.
  onDark,
}

/// A round icon action with an optional unread badge.
///
/// ## Count or dot
///
/// [badgeCount] draws a number, capped at "9+"; [showDot] draws a bare dot.
/// The distinction is deliberate: a count belongs on something the user
/// cannot see from here (the notification bell, the inbox), while a dot is
/// enough on something one tap away. The number of unread notifications is
/// worth knowing; the exact number past nine is not.
///
/// The target is always at least 48dp even when the visible disc is smaller,
/// so a compact header icon never becomes a missed tap.
class SugoIconButton extends StatelessWidget {
  const SugoIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.style = SugoIconButtonStyle.surface,
    this.size = 42,
    this.badgeCount = 0,
    this.showDot = false,
    this.iconColor,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  /// Required: an icon with no words needs a spoken label, and the tooltip is
  /// what screen readers announce.
  final String tooltip;

  final SugoIconButtonStyle style;
  final double size;
  final int badgeCount;
  final bool showDot;
  final Color? iconColor;

  (Color, Color, Color?) get _colors => switch (style) {
    SugoIconButtonStyle.surface => (
      AppColors.surface,
      AppColors.textPrimary,
      AppColors.border,
    ),
    SugoIconButtonStyle.tonal => (
      AppColors.primarySoft,
      AppColors.primary,
      null,
    ),
    SugoIconButtonStyle.filled => (AppColors.primary, Colors.white, null),
    SugoIconButtonStyle.glass => (
      Colors.white.withValues(alpha: 0.94),
      AppColors.textPrimary,
      null,
    ),
    SugoIconButtonStyle.onDark => (
      Colors.white.withValues(alpha: 0.10),
      Colors.white,
      Colors.white.withValues(alpha: 0.18),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final (Color background, Color foreground, Color? border) = _colors;

    final Widget disc = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border: border == null ? null : Border.all(color: border),
        // Only the glass disc floats (over a map or a photo); a surface disc
        // on the page is flat with a hairline, like every other card.
        boxShadow: style == SugoIconButtonStyle.glass ? AppElevation.sm : null,
      ),
      child: Icon(icon, size: size * 0.46, color: iconColor ?? foreground),
    );

    final Widget withBadge = Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        disc,
        if (badgeCount > 0)
          Positioned(
            top: -3,
            right: -3,
            child: SugoCountBadge(count: badgeCount),
          )
        else if (showDot)
          Positioned(
            top: 1,
            right: 1,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 2),
              ),
            ),
          ),
      ],
    );

    final String semantic = badgeCount > 0
        ? '$tooltip, $badgeCount unread'
        : showDot
        ? '$tooltip, new activity'
        : tooltip;

    return Semantics(
      button: true,
      label: semantic,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: AppSizes.touchTarget,
            minHeight: AppSizes.touchTarget,
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onPressed,
              customBorder: const CircleBorder(),
              child: Center(widthFactor: 1, heightFactor: 1, child: withBadge),
            ),
          ),
        ),
      ),
    );
  }
}

/// The small orange count pill used on icons and list rows.
///
/// The numeral is ink, not white: white on the brief's orange is 2.1:1, and a
/// count nobody can read is decoration.
class SugoCountBadge extends StatelessWidget {
  const SugoCountBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      // Pops in once when a count first appears - the one moment a badge
      // should draw the eye - and never again while it merely updates.
      tween: Tween<double>(begin: 0.6, end: 1),
      duration: AppMotion.base,
      curve: AppMotion.playful,
      builder: (BuildContext context, double scale, Widget? child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        constraints: const BoxConstraints(minWidth: 20),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(AppSizes.pillRadius),
          border: Border.all(color: AppColors.surface, width: 1.8),
        ),
        child: Text(
          count > 9 ? '9+' : '$count',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppColors.onAccent,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}
