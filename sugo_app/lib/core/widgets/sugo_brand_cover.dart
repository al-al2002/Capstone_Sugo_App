import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// The drawn cover behind every profile: the brand gradient, two soft rings,
/// and the dashed route ending in a van - the route line the app draws for
/// every booking (2026-09-29).
///
/// It replaced photographs. The app icon's emblem, stretched wide, fought with
/// the avatar placed on it; a technician's own photo, stretched to the full
/// width of a phone, came out soft and cropped - and most accounts have no
/// photo at all, which left faint giant initials. A drawn cover is sharp at
/// any size, the same for everyone, and quiet in the middle where the avatar
/// goes.
///
/// [topInset] keeps the route and the van below whatever sits over the top of
/// the cover - a status bar and an app bar with a back button, say. The route
/// is drawn in the [motifHeight] band under it; the gradient and the rings
/// fill the whole area.
class SugoBrandCover extends StatelessWidget {
  const SugoBrandCover({super.key, this.topInset = 0, this.motifHeight = 128});

  final double topInset;
  final double motifHeight;

  static const double _vanRight = 22;
  static const double _vanTop = 20;
  static const double _vanSize = 26;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          CustomPaint(
            painter: _CoverPainter(
              topInset: topInset,
              motifHeight: motifHeight,
            ),
          ),
          Positioned(
            right: _vanRight,
            top: topInset + _vanTop,
            child: const Icon(
              Icons.local_shipping_rounded,
              size: _vanSize,
              color: Color(0xE6FFFFFF),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverPainter extends CustomPainter {
  const _CoverPainter({required this.topInset, required this.motifHeight});

  final double topInset;
  final double motifHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect all = Offset.zero & size;

    // The brand gradient, navy to SUGO blue, corner to corner.
    canvas.drawRect(
      all,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: <Color>[AppColors.navy, AppColors.primary, AppColors.secondary],
          stops: <double>[0, 0.55, 1],
        ).createShader(all),
    );

    // Two soft rings for depth, kept to the corners.
    final double band = math.min(motifHeight, size.height - topInset);
    canvas.drawCircle(
      Offset(size.width * 0.92, topInset - band * 0.15),
      band * 0.95,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..color = Colors.white.withValues(alpha: 0.06),
    );
    canvas.drawCircle(
      Offset(size.width * 0.02, size.height + band * 0.05),
      band * 0.62,
      Paint()..color = Colors.white.withValues(alpha: 0.05),
    );

    // The route: from a start dot low on the left of the band, curving up to
    // the van at its top right.
    final Offset start = Offset(size.width * 0.07, topInset + band * 0.72);
    final Offset end = Offset(
      size.width - SugoBrandCover._vanRight - SugoBrandCover._vanSize - 6,
      topInset + SugoBrandCover._vanTop + SugoBrandCover._vanSize * 0.62,
    );
    final Path route = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        size.width * 0.28,
        topInset + band * 0.18,
        size.width * 0.58,
        topInset + band * 0.62,
        end.dx,
        end.dy,
      );

    final Paint dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.45);
    for (final metric in route.computeMetrics()) {
      const double on = 7;
      const double off = 6;
      for (double d = 0; d < metric.length; d += on + off) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + on, metric.length)),
          dash,
        );
      }
    }

    // The stop where the trip began.
    canvas.drawCircle(start, 6, Paint()..color = Colors.white);
    canvas.drawCircle(start, 3, Paint()..color = AppColors.secondary);
  }

  @override
  bool shouldRepaint(covariant _CoverPainter oldDelegate) =>
      oldDelegate.topInset != topInset ||
      oldDelegate.motifHeight != motifHeight;
}
