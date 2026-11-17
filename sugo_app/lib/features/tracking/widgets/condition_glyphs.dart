import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../models/trip_conditions.dart';

/// Small animated pictures of the conditions on a trip (2026-11-17), shared
/// by the trip card and the delay pop-up.
///
/// ## The motion means something
///
/// Each animation encodes the reading rather than decorating it:
///
/// * [WeatherGlyph] - the sun's rays turn slowly in good weather, a cloud
///   drifts in fair weather, and rain falls from a dark cloud in bad.
/// * [TrafficFlow] - the cars' SPEED is the traffic. They zip along on clear
///   roads, crawl with red brake lights in heavy traffic, and stand still at
///   a barrier for a road closure.
///
/// Under reduced motion both freeze on one representative frame, which still
/// reads correctly: rain is still drawn, the cars are still bunched up.
///
/// Both are a single `CustomPainter` driven by one repeating controller, in a
/// `RepaintBoundary`, so a looping glyph repaints itself and nothing else.

/// The weather, as a looping picture.
class WeatherGlyph extends StatefulWidget {
  const WeatherGlyph({
    super.key,
    required this.level,
    this.size = 40,
    this.cycles,
  });

  final WeatherLevel level;
  final double size;

  /// Play this many cycles, then rest; null loops for as long as it is on
  /// screen. The delay pop-up plays a few and stops - see [GlyphLoop].
  final int? cycles;

  @override
  State<WeatherGlyph> createState() => _WeatherGlyphState();
}

class _WeatherGlyphState extends State<WeatherGlyph>
    with SingleTickerProviderStateMixin, GlyphLoop<WeatherGlyph> {
  @override
  int? get cycles => widget.cycles;

  /// One full cycle per level: a slow sun, a gentle drift, quick rain.
  static Duration _period(WeatherLevel level) => switch (level) {
    WeatherLevel.good => const Duration(seconds: 14),
    WeatherLevel.fair => const Duration(milliseconds: 4200),
    WeatherLevel.bad => const Duration(milliseconds: 950),
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(WeatherGlyph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.level != widget.level) _sync();
  }

  void _sync() => play(
    period: _period(widget.level),
    still: AppMotion.reduced(context),
    rest: 0.35,
  );

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _WeatherPainter(widget.level, loop),
      ),
    );
  }
}

class _WeatherPainter extends CustomPainter {
  _WeatherPainter(this.level, this.t) : super(repaint: t);

  final WeatherLevel level;
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    switch (level) {
      case WeatherLevel.good:
        _sun(canvas, Offset(w * 0.5, w * 0.5), w * 0.2, t.value, rays: true);
      case WeatherLevel.fair:
        _sun(canvas, Offset(w * 0.64, w * 0.36), w * 0.15, 0, rays: false);
        final double drift = math.sin(t.value * 2 * math.pi) * w * 0.045;
        _cloud(
          canvas,
          size,
          Offset(drift, w * 0.06),
          AppColors.secondarySoft,
          AppColors.secondary.withValues(alpha: 0.55),
        );
      case WeatherLevel.bad:
        _rain(canvas, size, t.value);
        _cloud(
          canvas,
          size,
          Offset(0, -w * 0.08),
          AppColors.primary.withValues(alpha: 0.78),
          null,
        );
    }
  }

  void _sun(
    Canvas canvas,
    Offset c,
    double r,
    double turn, {
    required bool rays,
  }) {
    final Paint fill = Paint()..color = AppColors.accent;
    if (rays) {
      final Paint ray = Paint()
        ..color = AppColors.accent.withValues(alpha: 0.75)
        ..strokeWidth = r * 0.28
        ..strokeCap = StrokeCap.round;
      for (int i = 0; i < 8; i++) {
        final double a = turn * 2 * math.pi + i * math.pi / 4;
        final Offset dir = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(c + dir * (r * 1.45), c + dir * (r * 2.0), ray);
      }
    }
    canvas.drawCircle(c, r, fill);
  }

  void _cloud(Canvas canvas, Size size, Offset shift, Color fill, Color? edge) {
    final double w = size.width;
    final Path cloud = Path()
      ..addOval(
        Rect.fromCircle(center: Offset(w * 0.36, w * 0.56), radius: w * 0.15),
      )
      ..addOval(
        Rect.fromCircle(center: Offset(w * 0.52, w * 0.46), radius: w * 0.19),
      )
      ..addOval(
        Rect.fromCircle(center: Offset(w * 0.68, w * 0.57), radius: w * 0.13),
      )
      ..addRRect(
        RRect.fromLTRBR(
          w * 0.22,
          w * 0.55,
          w * 0.82,
          w * 0.71,
          Radius.circular(w * 0.08),
        ),
      );
    final Path moved = cloud.shift(shift);
    canvas.drawPath(moved, Paint()..color = fill);
    if (edge != null) {
      canvas.drawPath(
        moved,
        Paint()
          ..color = edge
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.035,
      );
    }
  }

  /// Four drops, each a quarter-cycle behind the last, falling from under
  /// the cloud and fading near the ground.
  void _rain(Canvas canvas, Size size, double phase) {
    final double w = size.width;
    final Paint drop = Paint()
      ..strokeWidth = w * 0.055
      ..strokeCap = StrokeCap.round;
    const List<double> columns = <double>[0.3, 0.46, 0.62, 0.76];
    for (int i = 0; i < columns.length; i++) {
      final double p = (phase + i * 0.27) % 1.0;
      final double y = lerpDouble(w * 0.6, w * 0.98, p)!;
      drop.color = AppColors.secondary.withValues(alpha: 1 - p * 0.7);
      final double x = w * columns[i] - p * w * 0.04; // a little wind
      canvas.drawLine(Offset(x, y - w * 0.1), Offset(x - w * 0.025, y), drop);
    }
  }

  @override
  bool shouldRepaint(_WeatherPainter old) => old.level != level;
}

/// The traffic, as a short road with cars on it.
class TrafficFlow extends StatefulWidget {
  const TrafficFlow({
    super.key,
    required this.level,
    this.height = 26,
    this.cycles,
  });

  final TrafficLevel level;
  final double height;

  /// As [WeatherGlyph.cycles].
  final int? cycles;

  @override
  State<TrafficFlow> createState() => _TrafficFlowState();
}

class _TrafficFlowState extends State<TrafficFlow>
    with SingleTickerProviderStateMixin, GlyphLoop<TrafficFlow> {
  @override
  int? get cycles => widget.cycles;

  /// Time for the traffic to move one car-gap: short when it flows, long
  /// when it crawls.
  static Duration _period(TrafficLevel level) =>
      Duration(milliseconds: lerpDouble(700, 5200, level.slowness)!.round());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(TrafficFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.level != widget.level) _sync();
  }

  // A closed road does not move, motion or not.
  void _sync() => play(
    period: _period(widget.level),
    still: AppMotion.reduced(context) || widget.level == TrafficLevel.closed,
    rest: 0.4,
  );

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(double.infinity, widget.height),
        painter: _TrafficPainter(widget.level, loop),
      ),
    );
  }
}

class _TrafficPainter extends CustomPainter {
  _TrafficPainter(this.level, this.t) : super(repaint: t);

  final TrafficLevel level;
  final Animation<double> t;

  static Color carColor(TrafficLevel level) => switch (level) {
    TrafficLevel.clear || TrafficLevel.light => AppColors.cyan,
    TrafficLevel.moderate => AppColors.accent,
    TrafficLevel.heavy || TrafficLevel.closed => AppColors.error,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final RRect road = RRect.fromLTRBR(0, 0, w, h, Radius.circular(h / 2));
    canvas.drawRRect(road, Paint()..color = AppColors.navy);
    canvas.save();
    canvas.clipRRect(road);

    // The centre line, moving with the traffic.
    final double dash = h * 0.7;
    final double period = dash * 2;
    final double lineShift = t.value * period;
    final Paint line = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = math.max(1.2, h * 0.07)
      ..strokeCap = StrokeCap.round;
    for (double x = -period + lineShift; x < w; x += period) {
      canvas.drawLine(Offset(x, h / 2), Offset(x + dash, h / 2), line);
    }

    // Cars: bunched up and slow in traffic, spread out and quick when clear.
    final double carW = h * 0.95;
    final double carH = h * 0.42;
    final double gap = lerpDouble(w / 2.6, carW * 1.55, level.slowness)!;
    final Color body = carColor(level);
    final bool braking = level.isBad || level == TrafficLevel.moderate;
    final double span = w + carW;
    final int count = (span / gap).ceil() + 1;
    for (int i = 0; i < count; i++) {
      final double x = ((i * gap + t.value * gap) % (count * gap)) - carW;
      if (x > w) continue;
      final double y = (i.isEven ? h * 0.27 : h * 0.73) - carH / 2;
      final RRect car = RRect.fromLTRBR(
        x,
        y,
        x + carW,
        y + carH,
        Radius.circular(carH * 0.45),
      );
      canvas.drawRRect(car, Paint()..color = body);
      // Brake lights at the back - glowing when the traffic is slow.
      final Paint tail = Paint()
        ..color = braking
            ? const Color(0xFFFF5A5A)
            : Colors.white.withValues(alpha: 0.5);
      if (braking) {
        tail.maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6);
      }
      canvas.drawCircle(Offset(x + carH * 0.3, y + carH / 2), carH * 0.2, tail);
    }

    if (level == TrafficLevel.closed) _barrier(canvas, size);
    canvas.restore();
  }

  /// Red-and-white stripes across the road ahead.
  void _barrier(Canvas canvas, Size size) {
    final double h = size.height;
    final double left = size.width * 0.74;
    final Rect bar = Rect.fromLTWH(left, h * 0.12, h * 0.42, h * 0.76);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bar, const Radius.circular(3)),
      Paint()..color = Colors.white,
    );
    final Paint stripe = Paint()..color = AppColors.error;
    for (double y = bar.top; y < bar.bottom; y += h * 0.22) {
      canvas.drawRect(Rect.fromLTWH(bar.left, y, bar.width, h * 0.11), stripe);
    }
  }

  @override
  bool shouldRepaint(_TrafficPainter old) => old.level != level;
}

/// The one repeating controller behind each glyph, with an optional cycle
/// limit.
///
/// Looping forever suits the trip card: the cars moving IS the live traffic.
/// It does not suit a pop-up, which is read once - the codebase's rule (the ID
/// scan line "runs 3 passes and stops") is that a one-off message animates a
/// few times and then holds still. Cycles are counted by hand on the status
/// listener, which works on every Flutter version this project supports.
mixin GlyphLoop<T extends StatefulWidget>
    on State<T>, SingleTickerProviderStateMixin<T> {
  late final AnimationController loop = AnimationController(vsync: this)
    ..addStatusListener(_onStatus);

  /// Cycles to play, or null for no limit.
  int? get cycles;

  int _played = 0;
  double _rest = 0;

  /// Starts (or restarts) the loop at [period] a cycle, or holds it on the
  /// [rest] frame when [still] (reduced motion, a closed road).
  void play({
    required Duration period,
    required bool still,
    required double rest,
  }) {
    loop.duration = period;
    _rest = rest;
    if (still) {
      loop
        ..stop()
        ..value = rest;
      return;
    }
    if (loop.isAnimating) return;
    _played = 0;
    loop.forward(from: 0);
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _played++;
    final int? limit = cycles;
    if (limit != null && _played >= limit) {
      loop.value = _rest;
      return;
    }
    loop.forward(from: 0);
  }

  @override
  void dispose() {
    loop.dispose();
    super.dispose();
  }
}
