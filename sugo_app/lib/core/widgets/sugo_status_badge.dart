import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../theme/app_text_styles.dart';

/// The meaning behind a status colour.
enum SugoTone {
  neutral,
  brand,
  info,
  success,
  warning,
  danger,
  accent;

  /// (soft background, strong foreground).
  (Color, Color) get colors => switch (this) {
    SugoTone.neutral => (AppColors.divider, AppColors.textSecondary),
    SugoTone.brand => (AppColors.primarySoft, AppColors.primary),
    SugoTone.info => (AppColors.secondarySoft, AppColors.secondaryDark),
    SugoTone.success => (AppColors.successSoft, AppColors.success),
    SugoTone.warning => (AppColors.warningSoft, AppColors.warning),
    SugoTone.danger => (AppColors.errorSoft, AppColors.error),
    SugoTone.accent => (AppColors.accentSoft, AppColors.accentDark),
  };
}

/// A status pill: an icon, a word, and a tone.
///
/// ## Never colour alone
///
/// The brief asks that no status be communicated only through colour, and
/// this is the widget that enforces it: [icon] and [label] are both required.
/// Roughly one man in twelve cannot tell the app's green "Confirmed" from its
/// amber "Pending" by hue, and on a sunlit phone screen nobody can - the icon
/// and the word are what actually carry the meaning. The tint is a second,
/// faster channel for everyone else.
///
/// ## The live pulse
///
/// [pulsing] replaces the icon with a softly breathing dot, reserved for
/// states that are changing *right now* - a technician on the way, a repair in
/// progress. It is the one moving thing in a list, so it is the first thing
/// the eye finds.
class SugoStatusBadge extends StatelessWidget {
  const SugoStatusBadge({
    super.key,
    required this.label,
    required this.icon,
    this.tone = SugoTone.brand,
    this.pulsing = false,
    this.dense = false,
  });

  final String label;
  final IconData icon;
  final SugoTone tone;
  final bool pulsing;

  /// Smaller padding and type, for a pill inside a compact row.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final (Color background, Color foreground) = tone.colors;

    return Semantics(
      label: 'Status: $label',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? AppSizes.sm : 10,
          vertical: dense ? 3 : 5,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (pulsing)
              _PulseDot(color: foreground, size: dense ? 6 : 7)
            else
              Icon(icon, size: dense ? 12 : 13.5, color: foreground),
            SizedBox(width: dense ? 4 : 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: dense ? 12 : 13,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  // Assigned in initState, never lazily - see the note on `_GlyphState` in
  // `sugo_empty_state.dart` for the unmount crash a lazy controller causes.
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A breathing dot is decoration; under "reduce motion" it holds still.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double halo = widget.size * 2.2;
    return SizedBox(
      width: halo,
      height: halo,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          final double t = Curves.easeInOut.transform(_controller.value);
          return Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Container(
                width: widget.size + (halo - widget.size) * t,
                height: widget.size + (halo - widget.size) * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.28 * (1 - t)),
                ),
              ),
              child!,
            ],
          );
        },
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
