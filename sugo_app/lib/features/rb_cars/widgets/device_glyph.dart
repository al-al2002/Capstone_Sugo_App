import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/device_category.dart';
import '../../../core/constants/app_colors.dart';

/// The line/duotone icon on a device card.
///
/// Drawn rather than taken from `Icons`, for two reasons. The Material set has
/// no CCTV glyph at all - the nearest is a generic videocam, which reads as
/// "record a video" - and mixing a router, a fridge and a laptop from that set
/// gives five icons at three different optical weights. These five are laid
/// out on one 24-unit grid with one stroke width, so the row of cards scans as
/// a set instead of as five borrowed pictures.
///
/// Duotone, not flat: a soft wash fills the body of each object and the outline
/// sits on top of it. Both come from the same brand colour - [AppColors.primary]
/// once the card is selected, [AppColors.textSecondary] before - so the icon
/// warms up with the card and the screen never introduces a colour of its own.
class DeviceGlyph extends StatelessWidget {
  const DeviceGlyph({
    super.key,
    required this.category,
    required this.selected,
    this.size = 30,
  });

  final DeviceCategory category;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Animated so the tint slides across with the card's own 150ms border and
    // background transition rather than snapping a frame ahead of it.
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 150),
      tween: Tween<double>(begin: 0, end: selected ? 1 : 0),
      builder: (BuildContext context, double t, _) {
        final Color ink = Color.lerp(
          AppColors.textSecondary,
          AppColors.primary,
          t,
        )!;
        return CustomPaint(
          size: Size.square(size),
          painter: _DeviceGlyphPainter(category: category, ink: ink),
        );
      },
    );
  }
}

class _DeviceGlyphPainter extends CustomPainter {
  const _DeviceGlyphPainter({required this.category, required this.ink});

  final DeviceCategory category;

  /// The single colour the whole glyph is derived from: full strength for the
  /// outline, a 14% wash for the duotone fill.
  final Color ink;

  /// Every path below is written against a 24x24 grid, the same one Material
  /// icons use, so the five glyphs share a baseline and an optical size.
  static const double _grid = 24;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _grid, size.height / _grid);

    // 1.8 on the 24-grid. Held constant across all five glyphs - the stroke
    // weight is the thing that makes them look like one family.
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = ink;

    final Paint fill = Paint()
      ..style = PaintingStyle.fill
      ..color = ink.withValues(alpha: 0.14);

    switch (category) {
      case DeviceCategory.laptop:
        _paintLaptop(canvas, stroke, fill);
      case DeviceCategory.phone:
        _paintPhone(canvas, stroke, fill);
      case DeviceCategory.appliance:
        _paintAppliance(canvas, stroke, fill);
      case DeviceCategory.network:
        _paintNetwork(canvas, stroke, fill);
      case DeviceCategory.cctv:
        _paintCctv(canvas, stroke, fill);
    }

    canvas.restore();
  }

  /// Corner radius shared by every rounded body, so a phone and a router are
  /// rounded by the same amount.
  static RRect _body(
    double l,
    double t,
    double r,
    double b, [
    double radius = 2.2,
  ]) {
    return RRect.fromRectAndRadius(
      Rect.fromLTRB(l, t, r, b),
      Radius.circular(radius),
    );
  }

  void _paintLaptop(Canvas canvas, Paint stroke, Paint fill) {
    final RRect screen = _body(3.6, 4.2, 20.4, 15.6, 2.4);
    canvas.drawRRect(screen, fill);
    canvas.drawRRect(screen, stroke);

    // The deck, drawn wider than the lid so the machine reads as open.
    final RRect deck = _body(1.6, 17.0, 22.4, 19.6, 1.3);
    canvas.drawRRect(deck, fill);
    canvas.drawRRect(deck, stroke);
  }

  void _paintPhone(Canvas canvas, Paint stroke, Paint fill) {
    // Two slabs, because the card covers both and one alone reads as "phone"
    // only. The proportions carry the distinction: the tablet behind is the
    // wider, squarer one, the phone in front the narrow one.
    final RRect tablet = _body(8.2, 2.4, 21.2, 17.4, 2.0);
    canvas.drawRRect(tablet, fill);
    canvas.drawRRect(tablet, stroke);

    final RRect phone = _body(3.0, 8.2, 10.8, 21.6, 2.4);
    // Filled opaquely first so the tablet's outline does not show through the
    // phone sitting in front of it.
    canvas.drawRRect(phone, Paint()..color = AppColors.surface);
    canvas.drawRRect(phone, fill);
    canvas.drawRRect(phone, stroke);

    // Earpiece and home indicator.
    canvas.drawLine(const Offset(5.2, 11.0), const Offset(8.6, 11.0), stroke);
    canvas.drawLine(const Offset(5.0, 19.4), const Offset(8.8, 19.4), stroke);
  }

  void _paintAppliance(Canvas canvas, Paint stroke, Paint fill) {
    final RRect cabinet = _body(4.4, 2.6, 19.6, 21.4, 2.6);
    canvas.drawRRect(cabinet, fill);
    canvas.drawRRect(cabinet, stroke);

    // Control panel, then the drum. A washer front is the one appliance
    // silhouette that is not mistaken for a plain box.
    canvas.drawLine(const Offset(4.4, 8.0), const Offset(19.6, 8.0), stroke);
    canvas.drawCircle(const Offset(16.6, 5.3), 0.95, Paint()..color = ink);

    canvas.drawCircle(const Offset(12.0, 14.8), 4.4, stroke);
    canvas.drawCircle(const Offset(12.0, 14.8), 1.7, stroke);
  }

  void _paintNetwork(Canvas canvas, Paint stroke, Paint fill) {
    final RRect router = _body(3.0, 15.0, 21.0, 20.8, 2.0);
    canvas.drawRRect(router, fill);
    canvas.drawRRect(router, stroke);

    canvas.drawCircle(const Offset(7.0, 17.9), 0.95, Paint()..color = ink);
    canvas.drawCircle(const Offset(10.4, 17.9), 0.95, Paint()..color = ink);

    // Two broadcast arcs, struck from the centre of the router's top edge.
    const Offset origin = Offset(12.0, 15.0);
    const double start = -math.pi * 0.80;
    const double sweep = math.pi * 0.60;
    for (final double radius in <double>[4.2, 7.6]) {
      canvas.drawArc(
        Rect.fromCircle(center: origin, radius: radius),
        start,
        sweep,
        false,
        stroke,
      );
    }
  }

  void _paintCctv(Canvas canvas, Paint stroke, Paint fill) {
    // A ceiling dome, not a bullet camera on a bracket: the dome silhouette
    // survives being drawn at 30px, where a bracket turns into a smudge.
    //
    // Deliberately no field-of-view rays. They were tried, and at this size
    // two diagonals under a dome stop reading as a sight line and start
    // reading as legs - the glyph turned into a side table.
    const Offset rim = Offset(12.0, 8.2);
    const double radius = 7.4;

    final Path dome = Path()
      ..moveTo(rim.dx - radius, rim.dy)
      ..arcToPoint(
        Offset(rim.dx + radius, rim.dy),
        radius: const Radius.circular(radius),
        clockwise: false,
      )
      ..close();
    canvas.drawPath(dome, fill);
    canvas.drawPath(dome, stroke);

    // Stem and ceiling plate, which are what say "mounted" rather than
    // "sitting on a shelf".
    canvas.drawRRect(_body(10.2, 5.4, 13.8, 8.2, 0.8), stroke);
    canvas.drawRRect(_body(4.4, 2.8, 19.6, 5.4, 1.2), stroke);

    // Lens, sitting in the face of the dome.
    canvas.drawCircle(const Offset(12.0, 11.6), 2.7, stroke);
    canvas.drawCircle(const Offset(12.0, 11.6), 1.1, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(_DeviceGlyphPainter old) =>
      old.category != category || old.ink != ink;
}
