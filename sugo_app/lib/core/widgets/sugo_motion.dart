import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../theme/app_motion.dart';
import '../theme/app_text_styles.dart';

/// The motion kit for the "Dispatch, levelled up" renovation (2026-11-17).
///
/// Three rules, so the screens built from it move one way:
///
/// 1. **Once, never on a loop.** Everything here plays when it appears and
///    then holds still. Motion on a screen that is being read is noise, and
///    a looping animation keeps a test's `pumpAndSettle` from ever settling.
/// 2. **No timers.** A delayed entrance folds its delay into its own curve
///    (an [Interval]) instead of waiting on a `Future.delayed`, so nothing
///    is left pending when a widget goes away mid-entrance.
/// 3. **Reduce motion means still.** With the system setting on, each piece
///    renders its final frame at once ([AppMotion.reduced]).

/// Fades and rises its child into place once, after [delay].
///
/// For list rows, pass [AppMotion.staggerDelay] of the row's index, so a list
/// deals in top to bottom - and capped, so row twenty is not late.
class SugoRiseIn extends StatefulWidget {
  const SugoRiseIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = AppMotion.slow,
    this.offset = 14,
    this.enabled = true,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  /// How far below its place it starts, in logical pixels.
  final double offset;

  /// False renders the child in place with no entrance - for rows that
  /// scroll into view long after the list first appeared.
  final bool enabled;

  @override
  State<SugoRiseIn> createState() => _SugoRiseInState();
}

class _SugoRiseInState extends State<SugoRiseIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.delay + widget.duration,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Interval(
      _c.duration!.inMicroseconds == 0
          ? 0
          : widget.delay.inMicroseconds / _c.duration!.inMicroseconds,
      1,
      curve: AppMotion.emphasized,
    ),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!widget.enabled || AppMotion.reduced(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (BuildContext context, Widget? child) => Opacity(
        opacity: _t.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - _t.value) * widget.offset),
          child: child,
        ),
      ),
    );
  }
}

/// Swings its child back and forth a few times and settles - a bell
/// ringing, a hand waving. Damped, so it eases out rather than stopping dead.
class SugoWiggle extends StatefulWidget {
  const SugoWiggle({
    super.key,
    required this.child,
    this.swings = 3,
    this.angle = 0.32,
    this.delay = const Duration(milliseconds: 260),
    this.duration = const Duration(milliseconds: 1100),
    this.alignment = Alignment.topCenter,
  });

  final Widget child;

  /// Full back-and-forth swings.
  final int swings;

  /// Largest swing, in radians.
  final double angle;

  final Duration delay;
  final Duration duration;

  /// The pivot: the top of a bell, the wrist of a hand.
  final Alignment alignment;

  @override
  State<SugoWiggle> createState() => _SugoWiggleState();
}

class _SugoWiggleState extends State<SugoWiggle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.delay + widget.duration,
  );
  bool _started = false;

  double get _start =>
      widget.delay.inMicroseconds / _c.duration!.inMicroseconds;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AppMotion.reduced(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        final double raw = _c.value <= _start
            ? 0
            : (_c.value - _start) / (1 - _start);
        final double swing =
            math.sin(raw * widget.swings * 2 * math.pi) *
            widget.angle *
            (1 - raw);
        return Transform.rotate(
          angle: swing,
          alignment: widget.alignment,
          child: child,
        );
      },
    );
  }
}

/// The summary band at the top of a renovated screen: the same navy-to-blue
/// gradient as the trip card, with two soft rings drawn in the corner.
///
/// It summarises ("3 unread conversations"); it is not a second title - the
/// app bar already names the screen.
class SugoHeroBand extends StatelessWidget {
  const SugoHeroBand({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSizes.lg),
    this.colors = brand,
    this.borderRadius,
  });

  final Widget child;
  final EdgeInsets padding;

  /// The gradient, top-left to bottom-right. [brand] unless the band carries
  /// a state of its own - a finished job in green, a cancelled one in grey.
  final List<Color> colors;

  /// Defaults to all corners round; a band that heads a card rounds only its
  /// top.
  final BorderRadius? borderRadius;

  static const List<Color> brand = <Color>[
    AppColors.primary,
    AppColors.secondary,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius:
            borderRadius ?? BorderRadius.circular(AppSizes.cardRadius + 4),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: const _RingsPainter(),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  const _RingsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..color = Colors.white.withValues(alpha: 0.06);
    final Offset corner = Offset(size.width * 0.96, size.height * 0.08);
    canvas.drawCircle(corner, size.height * 0.62, ring);
    canvas.drawCircle(corner, size.height * 1.05, ring..strokeWidth = 10);
    canvas.drawCircle(
      Offset(size.width * 0.06, size.height * 1.05),
      size.height * 0.38,
      Paint()..color = AppColors.cyan.withValues(alpha: 0.12),
    );
  }

  @override
  bool shouldRepaint(_RingsPainter oldDelegate) => false;
}

/// One choice in a [SugoSegmentedFilter].
class SugoSegment<T> {
  const SugoSegment({required this.value, required this.label, this.count});

  final T value;
  final String label;

  /// Shown as a small number beside the label when above zero.
  final int? count;
}

/// A segmented filter with a highlight that slides to the chosen segment.
///
/// Labels shrink to fit rather than wrap, so three segments survive a 320 dp
/// phone at large text.
class SugoSegmentedFilter<T> extends StatelessWidget {
  const SugoSegmentedFilter({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<SugoSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final int index = segments
        .indexWhere((SugoSegment<T> s) => s.value == selected)
        .clamp(0, segments.length - 1);
    final Duration move = AppMotion.reduced(context)
        ? Duration.zero
        : AppMotion.base;

    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final double width = box.maxWidth / segments.length;
          return Stack(
            children: <Widget>[
              AnimatedPositioned(
                duration: move,
                curve: AppMotion.emphasized,
                left: width * index,
                top: 0,
                bottom: 0,
                width: width,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                  ),
                ),
              ),
              Row(
                children: <Widget>[
                  for (int i = 0; i < segments.length; i++)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: i == index,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(
                            AppSizes.pillRadius,
                          ),
                          onTap: () => onChanged(segments[i].value),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: _SegmentLabel(
                                  segment: segments[i],
                                  selected: i == index,
                                  duration: move,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SegmentLabel<T> extends StatelessWidget {
  const _SegmentLabel({
    required this.segment,
    required this.selected,
    required this.duration,
  });

  final SugoSegment<T> segment;
  final bool selected;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final int count = segment.count ?? 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AnimatedDefaultTextStyle(
          duration: duration,
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
          child: Text(segment.label),
        ),
        if (count > 0) ...<Widget>[
          const SizedBox(width: 5),
          AnimatedContainer(
            duration: duration,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white.withValues(alpha: 0.22)
                  : AppColors.primarySoft,
              borderRadius: BorderRadius.circular(AppSizes.pillRadius),
            ),
            child: Text(
              count > 99 ? '99+' : '$count',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : AppColors.primary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A number that counts up to [value] once when it appears, and rolls to a
/// new value when it changes.
class SugoCountUp extends StatelessWidget {
  const SugoCountUp({super.key, required this.value, required this.style});

  final int value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    // `begin` is used only for the first build (count up from zero); after
    // that, a new value animates from wherever the number currently is.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: AppMotion.reduced(context)
          ? Duration.zero
          : const Duration(milliseconds: 700),
      curve: AppMotion.emphasized,
      builder: (BuildContext context, double v, Widget? _) => Text(
        '${v.round()}',
        style: style.copyWith(
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
