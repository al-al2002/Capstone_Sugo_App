import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../theme/app_motion.dart';
import '../theme/app_text_styles.dart';

/// What a button *means*, which decides how it looks.
///
/// Named by intent rather than colour on purpose. A screen asks for "the
/// primary action" or "a destructive one", and the palette decides what that
/// looks like - so a later palette change never has to hunt down every
/// `backgroundColor: Colors.red`.
enum SugoButtonVariant {
  /// The one main action on a screen. Navy fill.
  primary,

  /// A supporting action beside a primary one. Navy text on a soft wash, so it
  /// is clearly a button without competing with the filled one.
  tonal,

  /// A secondary action that needs a boundary: outlined, navy text.
  outlined,

  /// Highlights a time-sensitive action ("Track technician"). Orange fill
  /// with ink text. Used sparingly - if two buttons on a screen are accent,
  /// neither is.
  accent,

  /// Irreversible or destructive: delete, cancel a request, sign out.
  danger,

  /// Text only. For tertiary actions like "Skip" or "View all".
  ghost,
}

/// Three heights, matched to where the button sits.
enum SugoButtonSize {
  /// 54px - a screen's main call to action, usually full width.
  large,

  /// 48px - secondary actions and sheet actions.
  medium,

  /// 40px visible, 48px to the finger - actions inside a card ("Message",
  /// "View details").
  small,
}

/// The app's button.
///
/// ## Why one widget rather than the stock buttons
///
/// Flutter's `ElevatedButton`, `FilledButton`, `OutlinedButton` and
/// `TextButton` are four widgets with four APIs, and in practice each screen
/// restyled them locally - which is how SUGO ended up with orange chat pills,
/// blue outline buttons and white-on-navy filled ones on the same card. This
/// wraps them behind one API: a [variant] for meaning, a [size] for context,
/// and the rest is decided here.
///
/// ## What it adds
///
/// * **A loading state that keeps its width.** The label is replaced by a
///   spinner of the same colour, and the button does not shrink - a button
///   that collapses to a spinner makes the whole row jump.
/// * **A press response.** A 97% dip while held, like [SugoCard], so the tap is
///   acknowledged before the next screen arrives.
/// * **Semantics.** The label is announced even while loading, with a busy
///   hint, so a screen-reader user knows the tap landed.
class SugoButton extends StatefulWidget {
  const SugoButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = SugoButtonVariant.primary,
    this.size = SugoButtonSize.large,
    this.icon,
    this.trailingIcon,
    this.isLoading = false,
    this.expand = true,
    this.tooltip,
  });

  /// Tonal convenience constructor.
  const SugoButton.tonal({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = SugoButtonSize.medium,
    this.icon,
    this.trailingIcon,
    this.isLoading = false,
    this.expand = true,
    this.tooltip,
  }) : variant = SugoButtonVariant.tonal;

  final String label;
  final VoidCallback? onPressed;
  final SugoButtonVariant variant;
  final SugoButtonSize size;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool isLoading;

  /// Full width when true (the default for a screen CTA). Set false inside a
  /// row, where the button should size to its label.
  final bool expand;

  final String? tooltip;

  @override
  State<SugoButton> createState() => _SugoButtonState();
}

class _SugoButtonState extends State<SugoButton> {
  bool _held = false;

  bool get _enabled => widget.onPressed != null && !widget.isLoading;

  double get _height => switch (widget.size) {
    SugoButtonSize.large => AppSizes.buttonHeight,
    SugoButtonSize.medium => AppSizes.socialButtonHeight,
    SugoButtonSize.small => AppSizes.compactButtonHeight,
  };

  double get _fontSize => switch (widget.size) {
    SugoButtonSize.large || SugoButtonSize.medium => 15,
    SugoButtonSize.small => 13,
  };

  double get _iconSize => widget.size == SugoButtonSize.small ? 17 : 19;

  /// Side padding. Only the large, full-width call to action gets the
  /// generous 24; a medium button usually shares a row, where 24 a side cut
  /// "Message" down to "Mes…" on a 390dp phone.
  EdgeInsets get _padding => EdgeInsets.symmetric(
    horizontal: switch (widget.size) {
      SugoButtonSize.large => AppSizes.xl,
      SugoButtonSize.medium => AppSizes.lg,
      SugoButtonSize.small => AppSizes.md,
    },
  );

  /// (background, foreground, border) for the current variant.
  (Color, Color, Color?) get _colors {
    if (!_enabled && !widget.isLoading) {
      return switch (widget.variant) {
        SugoButtonVariant.ghost => (
          Colors.transparent,
          AppColors.hint,
          null,
        ),
        SugoButtonVariant.outlined => (
          AppColors.surface,
          AppColors.hint,
          AppColors.divider,
        ),
        _ => (AppColors.divider, AppColors.hint, null),
      };
    }
    return switch (widget.variant) {
      SugoButtonVariant.primary => (AppColors.primary, Colors.white, null),
      SugoButtonVariant.tonal => (AppColors.primarySoft, AppColors.primary, null),
      SugoButtonVariant.outlined => (
        AppColors.surface,
        AppColors.primary,
        AppColors.border,
      ),
      // Ink on orange, not white: white on the brief's orange is 2.1:1.
      SugoButtonVariant.accent => (AppColors.accent, AppColors.onAccent, null),
      SugoButtonVariant.danger => (AppColors.error, Colors.white, null),
      // The text shade of SUGO blue - the bright one is 4.0:1 on white.
      SugoButtonVariant.ghost => (
        Colors.transparent,
        AppColors.secondaryDark,
        null,
      ),
    };
  }

  void _setHeld(bool value) {
    if (!_enabled || _held == value) return;
    setState(() => _held = value);
  }

  @override
  Widget build(BuildContext context) {
    final (Color background, Color foreground, Color? border) = _colors;
    final BorderRadius radius = BorderRadius.circular(AppSizes.buttonRadius);

    final TextStyle labelStyle = AppTextStyles.button.copyWith(
      fontSize: _fontSize,
      color: foreground,
    );

    final Widget label = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (widget.icon != null) ...<Widget>[
          Icon(widget.icon, size: _iconSize, color: foreground),
          const SizedBox(width: AppSizes.sm),
        ],
        Flexible(
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: labelStyle,
          ),
        ),
        if (widget.trailingIcon != null) ...<Widget>[
          const SizedBox(width: AppSizes.sm),
          Icon(widget.trailingIcon, size: _iconSize, color: foreground),
        ],
      ],
    );

    // Both children are always laid out and the spinner is faded over the
    // label, so the button keeps the label's width while loading.
    final Widget content = Stack(
      alignment: Alignment.center,
      children: <Widget>[
        AnimatedOpacity(
          opacity: widget.isLoading ? 0 : 1,
          duration: AppMotion.fast,
          child: label,
        ),
        if (widget.isLoading)
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(foreground),
            ),
          ),
      ],
    );

    Widget button = AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.standard,
      height: _height,
      width: widget.expand ? double.infinity : null,
      // Flat: no glow under the filled variants since the Dispatch redesign.
      // A lit button on a flat page is the one thing on screen pretending to
      // float, and the fill alone already makes it the primary action.
      decoration: BoxDecoration(
        color: background,
        borderRadius: radius,
        border: border == null ? null : Border.all(color: border),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: _enabled ? widget.onPressed : null,
          onTapDown: (_) => _setHeld(true),
          onTapUp: (_) => _setHeld(false),
          onTapCancel: () => _setHeld(false),
          borderRadius: radius,
          splashColor: foreground.withValues(alpha: 0.12),
          highlightColor: foreground.withValues(alpha: 0.04),
          child: Padding(
            padding: _padding,
            child: Center(widthFactor: 1, child: content),
          ),
        ),
      ),
    );

    button = AnimatedScale(
      scale: _held ? 0.97 : 1,
      duration: AppMotion.fast,
      curve: AppMotion.standard,
      child: button,
    );

    // A small button draws 40 tall but answers taps across the full 48dp
    // floor. The band above and below forwards to the same action; a tap
    // inside the button itself is won by its own InkWell, which sits deeper in
    // the hit test and so enters the gesture arena first.
    if (_height < AppSizes.touchTarget) {
      button = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _enabled ? widget.onPressed : null,
        child: SizedBox(
          height: AppSizes.touchTarget,
          child: Center(heightFactor: 1, child: button),
        ),
      );
    }

    button = Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      hint: widget.isLoading ? 'Working, please wait' : null,
      excludeSemantics: true,
      child: button,
    );

    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}

/// An outlined [SugoButton] - kept as its own name because it is the second
/// most common button in the app and reads better at call sites.
class SugoOutlinedButton extends StatelessWidget {
  const SugoOutlinedButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.size = SugoButtonSize.medium,
    this.isLoading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final SugoButtonSize size;
  final bool isLoading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return SugoButton(
      label: label,
      onPressed: onPressed,
      icon: icon,
      size: size,
      isLoading: isLoading,
      expand: expand,
      variant: SugoButtonVariant.outlined,
    );
  }
}
