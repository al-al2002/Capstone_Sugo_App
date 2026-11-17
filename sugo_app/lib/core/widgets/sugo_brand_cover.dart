import 'dart:math' as math;
import 'dart:ui' show PathMetric, Tangent;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../theme/app_motion.dart';

/// Whose cover it is. The scene is the same city; the light changes.
enum SugoCoverStyle {
  /// Daylight over Davao, the route ending at a home - someone who books.
  client,

  /// The city at dusk with its windows lit, the route ending at the service
  /// van - someone who travels to the job.
  technician,
}

/// The illustrated cover behind every profile (2026-11-16).
///
/// ## Why it was redrawn
///
/// The previous cover was a gradient with one dashed line and a van icon. On a
/// phone it read as an empty blue box with a stray truck - the user's word
/// was "awful". This draws the scene the rest of SUGO's artwork already
/// uses (the login header, the splash, the home banner): Davao's skyline
/// under a blue sky, Mount Apo behind it, clouds, and the dashed route with
/// map pins that every booking follows. So a profile now looks like it
/// belongs to the same app as the screen that signed you in.
///
/// ## Why it is drawn and not a photo
///
/// The same reasons as before still hold: a drawing is sharp at any width,
/// costs no download, is the same for everyone, and can keep the area where
/// the avatar sits quiet. It is laid out from fixed proportions, never at
/// random, so it is identical on every phone and in the goldens.
///
/// ## Motion
///
/// The route draws itself in once, left to right, and the pins pop as the line
/// reaches them - the trip a booking makes, played once. It does not loop: a
/// cover that keeps moving pulls the eye away from the name. Under the
/// system's reduce-motion setting it appears finished.
///
/// [topInset] keeps the route below whatever sits over the top of the cover
/// (a status bar and an app bar, say). [bottomScrim] darkens the foot of the
/// cover for white text laid over it. [quiet] is for a header that carries
/// text across the whole cover - the home screens: the skyline stays low and
/// the route, pins and sun are left out, so nothing runs through the words.
class SugoBrandCover extends StatefulWidget {
  const SugoBrandCover({
    super.key,
    this.topInset = 0,
    this.motifHeight = 128,
    this.style = SugoCoverStyle.technician,
    this.bottomScrim = false,
    this.quiet = false,
  });

  final double topInset;

  /// The band, under [topInset], that the route and pins are drawn in.
  final double motifHeight;

  final SugoCoverStyle style;

  /// Darkens the bottom of the cover so white text on it stays readable.
  final bool bottomScrim;

  /// A low skyline and no route, for text laid across the cover.
  final bool quiet;

  @override
  State<SugoBrandCover> createState() => _SugoBrandCoverState();
}

class _SugoBrandCoverState extends State<SugoBrandCover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reveal.isDismissed) {
      AppMotion.reduced(context) ? _reveal.value = 1 : _reveal.forward();
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _CityCoverPainter(
            topInset: widget.topInset,
            motifHeight: widget.motifHeight,
            style: widget.style,
            bottomScrim: widget.bottomScrim,
            quiet: widget.quiet,
            reveal: CurveTween(curve: AppMotion.emphasized).animate(_reveal),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// One building: its share of the width and of the band's height.
typedef _Tower = ({double w, double h, bool spire});

class _CityCoverPainter extends CustomPainter {
  _CityCoverPainter({
    required this.topInset,
    required this.motifHeight,
    required this.style,
    required this.bottomScrim,
    required this.quiet,
    required this.reveal,
  }) : super(repaint: reveal);

  final double topInset;
  final double motifHeight;
  final SugoCoverStyle style;
  final bool bottomScrim;
  final bool quiet;
  final Animation<double> reveal;

  bool get _day => style == SugoCoverStyle.client;

  // Fixed proportions, cycled across the width. Tall, thin towers among low
  // blocks, like the Davao skyline in the app's other artwork.
  static const List<_Tower> _far = <_Tower>[
    (w: 0.055, h: 0.30, spire: false),
    (w: 0.040, h: 0.44, spire: true),
    (w: 0.070, h: 0.26, spire: false),
    (w: 0.045, h: 0.52, spire: false),
    (w: 0.035, h: 0.36, spire: false),
    (w: 0.075, h: 0.30, spire: false),
    (w: 0.050, h: 0.58, spire: true),
    (w: 0.060, h: 0.34, spire: false),
    (w: 0.040, h: 0.46, spire: false),
    (w: 0.070, h: 0.28, spire: false),
    (w: 0.045, h: 0.50, spire: true),
    (w: 0.065, h: 0.32, spire: false),
  ];

  static const List<_Tower> _near = <_Tower>[
    (w: 0.090, h: 0.20, spire: false),
    (w: 0.060, h: 0.32, spire: false),
    (w: 0.110, h: 0.16, spire: false),
    (w: 0.055, h: 0.38, spire: true),
    (w: 0.080, h: 0.22, spire: false),
    (w: 0.100, h: 0.14, spire: false),
    (w: 0.065, h: 0.30, spire: false),
    (w: 0.085, h: 0.18, spire: false),
    (w: 0.050, h: 0.34, spire: false),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final Rect all = Offset.zero & size;
    final double band = math.max(
      48,
      math.min(motifHeight, size.height - topInset),
    );
    // The skyline stands on the bottom edge and rises through the lower part
    // of the cover, whatever its height.
    final double city = quiet
        ? math.min(size.height * 0.30, band * 0.55)
        : math.min(size.height * 0.62, band * 0.95);

    _sky(canvas, all);
    _glow(canvas, size, band);
    _clouds(canvas, size, band);
    _mountain(canvas, size, city);
    _skyline(
      canvas,
      size,
      towers: _far,
      height: city,
      color: _day
          ? Colors.white.withValues(alpha: 0.22)
          : const Color(0xFF5B95DD).withValues(alpha: 0.30),
      offset: 0.013,
      windows: false,
    );
    _skyline(
      canvas,
      size,
      towers: _near,
      height: city,
      color: _day ? const Color(0xFF0B4A98) : const Color(0xFF041833),
      offset: 0.0,
      windows: true,
    );
    if (bottomScrim) _scrim(canvas, all);
    if (!quiet) _route(canvas, size, band);
  }

  // ------------------------------------------------------------------- sky

  void _sky(Canvas canvas, Rect all) {
    canvas.drawRect(
      all,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _day
              ? const <Color>[
                  AppColors.navyLift,
                  Color(0xFF1F7AE0),
                  Color(0xFF6CB8F6),
                ]
              : const <Color>[
                  AppColors.navy,
                  AppColors.navyLift,
                  Color(0xFF2A6FC9),
                ],
          stops: const <double>[0, 0.55, 1],
        ).createShader(all),
    );
  }

  /// The sun for a client, a soft moonlit haze for a technician.
  void _glow(Canvas canvas, Size size, double band) {
    final Offset at = Offset(size.width * 0.80, topInset + band * 0.30);
    final double r = band * 0.55;
    canvas.drawCircle(
      at,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            (_day ? const Color(0xFFFFD27A) : Colors.white).withValues(
              alpha: _day ? 0.45 : 0.14,
            ),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: at, radius: r)),
    );
    if (_day && !quiet) {
      canvas.drawCircle(
        at,
        band * 0.085,
        Paint()..color = const Color(0xFFFFE6A8),
      );
    }
  }

  void _clouds(Canvas canvas, Size size, double band) {
    final Paint paint = Paint()
      ..color = Colors.white.withValues(alpha: _day ? 0.22 : 0.08);
    void cloud(double cx, double cy, double s) {
      final Path p = Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(cx, cy + 4 * s),
              width: 58 * s,
              height: 14 * s,
            ),
            Radius.circular(7 * s),
          ),
        )
        ..addOval(
          Rect.fromCircle(center: Offset(cx - 12 * s, cy), radius: 10 * s),
        )
        ..addOval(
          Rect.fromCircle(
            center: Offset(cx + 6 * s, cy - 4 * s),
            radius: 13 * s,
          ),
        );
      canvas.drawPath(p, paint);
    }

    final double s = (band / 128).clamp(0.6, 1.4);
    cloud(size.width * 0.20, topInset + band * 0.24, s);
    cloud(size.width * 0.58, topInset + band * 0.12, s * 0.75);
  }

  /// Mount Apo, faint behind the city.
  void _mountain(Canvas canvas, Size size, double city) {
    final double base = size.height;
    final Path p = Path()
      ..moveTo(-size.width * 0.05, base)
      ..lineTo(size.width * 0.12, base - city * 0.70)
      ..quadraticBezierTo(
        size.width * 0.27,
        base - city * 1.12,
        size.width * 0.34,
        base - city * 1.02,
      )
      ..lineTo(size.width * 0.42, base - city * 0.86)
      ..quadraticBezierTo(
        size.width * 0.50,
        base - city * 0.92,
        size.width * 0.62,
        base - city * 0.58,
      )
      ..lineTo(size.width * 0.80, base)
      ..close();
    canvas.drawPath(
      p,
      Paint()..color = Colors.white.withValues(alpha: _day ? 0.14 : 0.07),
    );
  }

  void _skyline(
    Canvas canvas,
    Size size, {
    required List<_Tower> towers,
    required double height,
    required Color color,
    required double offset,
    required bool windows,
  }) {
    final Paint body = Paint()..color = color;
    final double base = size.height;
    double x = -size.width * offset;
    int i = 0;
    while (x < size.width) {
      final _Tower t = towers[i % towers.length];
      final double w = t.w * size.width;
      final double h = t.h * height * 1.6;
      final Rect r = Rect.fromLTWH(x, base - h, w - 2, h);
      canvas.drawRect(r, body);
      if (t.spire) {
        canvas.drawRect(
          Rect.fromLTWH(r.center.dx - 1, r.top - h * 0.16, 2, h * 0.16),
          body,
        );
      }
      if (windows) _windows(canvas, r, i);
      x += w;
      i++;
    }
  }

  /// A few lit windows: warm at dusk, a pale glint by day. Which ones are lit
  /// follows the building's position, so it is the same on every phone.
  void _windows(Canvas canvas, Rect r, int building) {
    if (r.width < 12 || r.height < 18) return;
    final Paint lit = Paint()
      ..color = _day
          ? Colors.white.withValues(alpha: 0.28)
          : AppColors.accent.withValues(alpha: 0.75);
    const double cell = 6;
    int row = 0;
    for (double y = r.top + 5; y < r.bottom - 6; y += cell) {
      int col = 0;
      for (double x = r.left + 4; x < r.right - 5; x += cell) {
        if ((building * 7 + row * 3 + col * 5) % 6 == 0) {
          canvas.drawRect(Rect.fromLTWH(x, y, 2.4, 2.4), lit);
        }
        col++;
      }
      row++;
    }
  }

  void _scrim(Canvas canvas, Rect all) {
    canvas.drawRect(
      all,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Colors.transparent, Color(0xB3031F44)],
          stops: <double>[0.35, 1],
        ).createShader(all),
    );
  }

  // ----------------------------------------------------------------- route

  void _route(Canvas canvas, Size size, double band) {
    final double t = reveal.value;
    final Offset start = Offset(size.width * 0.07, topInset + band * 0.58);
    final Offset end = Offset(size.width * 0.88, topInset + band * 0.30);
    final Path route = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        size.width * 0.30,
        topInset + band * 0.10,
        size.width * 0.55,
        topInset + band * 0.70,
        end.dx,
        end.dy,
      );

    final Paint dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.6);

    for (final PathMetric metric in route.computeMetrics()) {
      final double drawn = metric.length * t;
      const double on = 7;
      const double off = 6;
      for (double d = 0; d < drawn; d += on + off) {
        canvas.drawPath(metric.extractPath(d, math.min(d + on, drawn)), dash);
      }

      // Where the trip began.
      canvas.drawCircle(start, 5.5, Paint()..color = Colors.white);
      canvas.drawCircle(start, 2.6, Paint()..color = AppColors.secondary);

      // A stop on the way, and the destination.
      final Tangent? mid = metric.getTangentForOffset(metric.length * 0.48);
      if (mid != null) _pin(canvas, mid.position, _pop(t, 0.48), band);
      _destination(canvas, end, _pop(t, 0.98), band);
    }
  }

  /// 0 until the line reaches [at], then a quick overshooting pop to 1.
  double _pop(double t, double at) {
    final double local = ((t - at) / 0.12).clamp(0.0, 1.0);
    return local == 0 ? 0 : Curves.easeOutBack.transform(local);
  }

  void _pin(Canvas canvas, Offset tip, double scale, double band) {
    if (scale <= 0) return;
    final double r = 7 * scale * (band / 128).clamp(0.8, 1.3);
    final Offset c = tip.translate(0, -r * 1.7);
    final Path p = Path()
      ..addOval(Rect.fromCircle(center: c, radius: r))
      ..moveTo(c.dx - r * 0.72, c.dy + r * 0.62)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(c.dx + r * 0.72, c.dy + r * 0.62)
      ..close();
    canvas.drawPath(p, Paint()..color = Colors.white);
    canvas.drawCircle(c, r * 0.42, Paint()..color = AppColors.secondary);
  }

  /// The van for a technician, a home for a client, on a white disc.
  void _destination(Canvas canvas, Offset at, double scale, double band) {
    if (scale <= 0) return;
    final double r = 15 * scale * (band / 128).clamp(0.8, 1.3);
    canvas.drawCircle(
      at,
      r + 3,
      Paint()..color = Colors.white.withValues(alpha: 0.25),
    );
    canvas.drawCircle(at, r, Paint()..color = Colors.white);

    final IconData icon = _day
        ? Icons.home_rounded
        : Icons.local_shipping_rounded;
    final TextPainter glyph = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: r * 1.15,
          color: AppColors.primary,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    glyph
      ..paint(canvas, at - Offset(glyph.width / 2, glyph.height / 2))
      ..dispose();
  }

  @override
  bool shouldRepaint(covariant _CityCoverPainter old) =>
      old.topInset != topInset ||
      old.motifHeight != motifHeight ||
      old.style != style ||
      old.bottomScrim != bottomScrim ||
      old.quiet != quiet ||
      old.reveal != reveal;
}
