import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Soft blue gradient with a faded city skyline, used behind the auth header.
class SkylineBackdrop extends StatelessWidget {
  const SkylineBackdrop({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[AppColors.skyTop, AppColors.skyBottom],
        ),
      ),
      child: CustomPaint(painter: _SkylinePainter(), child: child),
    );
  }
}

class _SkylinePainter extends CustomPainter {
  /// Building footprints as fractions of the canvas: left, width, height.
  static const List<List<double>> _buildings = <List<double>>[
    <double>[-0.02, 0.14, 0.30],
    <double>[0.10, 0.10, 0.46],
    <double>[0.19, 0.13, 0.24],
    <double>[0.30, 0.09, 0.38],
    <double>[0.38, 0.15, 0.52],
    <double>[0.52, 0.11, 0.28],
    <double>[0.61, 0.13, 0.44],
    <double>[0.73, 0.10, 0.22],
    <double>[0.81, 0.14, 0.40],
    <double>[0.93, 0.12, 0.30],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    _paintClouds(canvas, size);

    final Paint building = Paint()
      ..color = Colors.white.withValues(alpha: 0.55);
    final Paint window = Paint()
      ..color = AppColors.primaryLight.withValues(alpha: 0.18);

    for (final List<double> spec in _buildings) {
      final double width = size.width * spec[1];
      final double height = size.height * spec[2];
      final Rect rect = Rect.fromLTWH(
        size.width * spec[0],
        size.height - height,
        width,
        height,
      );
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: const Radius.circular(6),
          topRight: const Radius.circular(6),
        ),
        building,
      );
      _paintWindows(canvas, rect, window);
    }
  }

  void _paintWindows(Canvas canvas, Rect building, Paint paint) {
    const double cell = 14;
    const double dot = 5;
    for (double y = building.top + cell; y < building.bottom - dot; y += cell) {
      for (
        double x = building.left + cell * 0.6;
        x < building.right - dot;
        x += cell
      ) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, dot, dot),
            const Radius.circular(1.5),
          ),
          paint,
        );
      }
    }
  }

  void _paintClouds(Canvas canvas, Size size) {
    final Paint cloud = Paint()..color = Colors.white.withValues(alpha: 0.45);
    void blob(double cx, double cy, double r) {
      canvas.drawCircle(Offset(size.width * cx, size.height * cy), r, cloud);
    }

    blob(0.16, 0.16, 18);
    blob(0.22, 0.15, 24);
    blob(0.28, 0.17, 15);
    blob(0.74, 0.10, 14);
    blob(0.80, 0.09, 20);
    blob(0.86, 0.11, 12);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
