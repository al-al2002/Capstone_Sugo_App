import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../theme/app_elevation.dart';
import '../theme/app_motion.dart';
import '../theme/app_text_styles.dart';

/// How a [SugoCard] separates from what is behind it.
///
/// Since the 2026-09-29 "Dispatch" redesign, resting cards are separated by a
/// hairline edge, not a shadow. Only the two floating levels cast one.
enum SugoElevation {
  /// Nested inside another card: no edge, no shadow. A second edge inside a
  /// card reads as a box in a box.
  flat,

  /// Resting on the page: a hairline edge. Kept as its own name so existing
  /// call sites still compile; it now looks the same as [md].
  sm,

  /// The default content card: white with a hairline edge.
  md,

  /// Lifted over other content - a card over a map, the one selected option.
  /// Hairline plus a soft shadow.
  lg,

  /// Floating: sheets, dialogs, sticky footers. Shadow, no edge.
  xl;

  List<BoxShadow> get shadows => switch (this) {
    SugoElevation.flat ||
    SugoElevation.sm ||
    SugoElevation.md => AppElevation.flat,
    SugoElevation.lg => AppElevation.lg,
    SugoElevation.xl => AppElevation.xl,
  };

  /// Whether this level draws the hairline edge.
  bool get hasEdge =>
      this == SugoElevation.sm ||
      this == SugoElevation.md ||
      this == SugoElevation.lg;
}

/// The standard content panel: white, 12dp corners, a hairline edge.
///
/// Every card on the home, match and technician screens is built from this so
/// radius, padding and edge stay identical across the app. Screens should not
/// hand-roll a `Container` with a `BoxDecoration` - the redesign audit counted
/// 289 of them, which is why no two cards in the app matched.
///
/// ## The "Dispatch" card (2026-09-29)
///
/// **Flat, with an edge.** The card used to sit on a two-layer shadow. It now
/// sits flat on the Paper ground with a 1px Hairline border
/// (`AppColors.border`). A shadow under *every* card is what made the old UI
/// read as a template: when everything floats, nothing does. Shadows are kept
/// for what genuinely floats - see [SugoElevation].
///
/// **A press response.** A tappable card dips to 98% while held and its edge
/// darkens one step, then both settle back. Without it a tap is confirmed only
/// once the next screen arrives, and on a slow connection that gap is long
/// enough to wonder whether the tap registered at all. The dip is shallow on
/// purpose: felt more than seen.
///
/// **Optional gradient.** For hero surfaces only, composed from palette
/// tokens.
class SugoCard extends StatefulWidget {
  const SugoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSizes.lg),
    this.margin,
    this.onTap,
    this.onLongPress,
    this.background,
    this.gradient,
    this.borderColor,
    this.borderWidth = 1,
    this.radius = AppSizes.radius,
    this.elevated = true,
    this.elevation,
    this.pressable = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? background;

  /// Hero surfaces only. Built from existing palette tokens.
  final Gradient? gradient;

  final Color? borderColor;
  final double borderWidth;
  final double radius;

  /// False for nested cards. Retained from the original API so existing call
  /// sites keep working; [elevation] is the expressive form and wins when set.
  final bool elevated;

  /// Explicit depth. Overrides [elevated] when provided.
  final SugoElevation? elevation;

  /// Set false to suppress the press animation on a tappable card - for rows
  /// already inside something that animates, where two responses to one tap
  /// read as a glitch.
  final bool pressable;

  SugoElevation get _resolved =>
      elevation ?? (elevated ? SugoElevation.md : SugoElevation.flat);

  @override
  State<SugoCard> createState() => _SugoCardState();
}

class _SugoCardState extends State<SugoCard> {
  bool _held = false;

  bool get _interactive => widget.onTap != null || widget.onLongPress != null;
  bool get _animates => _interactive && widget.pressable;

  void _setHeld(bool value) {
    if (!_animates || _held == value) return;
    setState(() => _held = value);
  }

  /// One step down the scale, used while a lifted card is held.
  ///
  /// Shrinking the card without also tightening its shadow reads as the card
  /// moving *away* from the user rather than being pushed into the page.
  static SugoElevation _pressed(SugoElevation depth) => switch (depth) {
    SugoElevation.lg => SugoElevation.md,
    SugoElevation.xl => SugoElevation.lg,
    _ => depth,
  };

  /// The edge colour: the caller's, else the hairline for a resting card on a
  /// plain surface. A gradient or a tinted background is its own edge.
  Color? get _edge {
    if (widget.borderColor != null) return widget.borderColor;
    final bool plain = widget.gradient == null && widget.background == null;
    if (!plain || !widget._resolved.hasEdge) return null;
    return _held ? AppColors.hint : AppColors.border;
  }

  @override
  Widget build(BuildContext context) {
    final BorderRadius corners = BorderRadius.circular(widget.radius);
    final SugoElevation depth = _held
        ? _pressed(widget._resolved)
        : widget._resolved;
    final Color? edge = _edge;

    Widget content = AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.standard,
      decoration: BoxDecoration(
        color: widget.gradient != null
            ? null
            : (widget.background ?? AppColors.surface),
        gradient: widget.gradient,
        borderRadius: corners,
        border: edge == null
            ? null
            : Border.all(color: edge, width: widget.borderWidth),
        boxShadow: depth.shadows,
      ),
      child: Padding(padding: widget.padding, child: widget.child),
    );

    if (_interactive) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onTapDown: (_) => _setHeld(true),
          onTapUp: (_) => _setHeld(false),
          onTapCancel: () => _setHeld(false),
          // Matches the card's own corners so the ripple never squares off
          // the rounded edge.
          borderRadius: corners,
          splashColor: AppColors.primary.withValues(alpha: 0.06),
          highlightColor: Colors.transparent,
          child: content,
        ),
      );

      content = AnimatedScale(
        scale: _held ? 0.98 : 1,
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        child: content,
      );
    }

    return widget.margin == null
        ? content
        : Padding(padding: widget.margin!, child: content);
  }
}

/// Section heading with an optional subtitle and trailing action.
///
/// The renovation gave this a subtitle slot and moved its type onto
/// [AppTextStyles.sectionTitle]. The subtitle matters more than it looks: a
/// bare heading forces every section to explain itself inside its own content,
/// which is what pushed explanatory text down into the cards and made them
/// wordy.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.onActionTap,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onActionTap;

  /// Small leading glyph, in navy, beside the heading.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: AppSizes.sm),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(title, style: AppTextStyles.sectionTitle),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: AppTextStyles.micro,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        if (action != null)
          TextButton(onPressed: onActionTap, child: Text(action!))
        else if (onActionTap != null)
          IconButton(
            onPressed: onActionTap,
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.more_horiz_rounded,
              color: AppColors.textSecondary,
            ),
          ),
      ],
    );
  }
}
