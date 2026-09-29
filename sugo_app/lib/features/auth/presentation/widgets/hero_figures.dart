import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';

/// Flat-vector pieces that make up the illustrated auth header.
///
/// These are painted rather than shipped as images so the app has no binary
/// asset dependency. For final polish, export the real artwork and hand it to
/// AuthHero.illustrationAsset instead - an image takes precedence over these.
class HeroPalette {
  const HeroPalette._();

  static const Color uniform = AppColors.primary;
  static const Color uniformDark = Color(0xFF1160C4);
  static const Color trousers = AppColors.navy;
  static const Color shoes = Color(0xFF07203F);
  static const Color skin = Color(0xFFF4C9A3);
  static const Color hair = Color(0xFF2B2118);
  static const Color parcel = Color(0xFFF6A623);
  static const Color parcelTape = Color(0xFFFFD08A);
  static const Color blouse = Color(0xFFFF8A5C);
  static const Color blouseDark = Color(0xFFE8663A);
  static const Color device = Color(0xFF123A6B);
}

/// The large blue map pin that anchors the left of the login header.
class MapPinMark extends StatelessWidget {
  const MapPinMark({super.key, this.height = 66});

  final double height;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(height * 0.72, height),
      painter: _MapPinPainter(),
    );
  }
}

class _MapPinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final Offset bulb = Offset(w * 0.5, h * 0.36);
    final double radius = w * 0.5;

    // Soft contact shadow so the pin reads as floating over the skyline.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 1.02),
        width: w * 0.5,
        height: h * 0.08,
      ),
      Paint()..color = AppColors.navy.withValues(alpha: 0.10),
    );

    final Paint fill = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[AppColors.primaryLight, AppColors.primary],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    final Path tail = Path()
      ..moveTo(bulb.dx - radius * 0.58, bulb.dy + radius * 0.62)
      ..lineTo(bulb.dx, h)
      ..lineTo(bulb.dx + radius * 0.58, bulb.dy + radius * 0.62)
      ..close();

    canvas.drawPath(tail, fill);
    canvas.drawCircle(bulb, radius, fill);

    canvas.drawCircle(bulb, radius * 0.38, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// White rounded tile carrying a single service icon.
class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, this.size = 46, this.color});

  final IconData icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.md),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, color: color ?? AppColors.primary, size: size * 0.48),
    );
  }
}

/// The courier: blue uniform, cap, parcel held at the waist.
class CourierFigure extends StatelessWidget {
  const CourierFigure({
    super.key,
    this.height = 118,
    this.carriesParcel = true,
  });

  final double height;

  /// Register shows the courier gesturing rather than holding a box.
  final bool carriesParcel;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(height * 0.62, height),
      painter: _CourierPainter(carriesParcel: carriesParcel),
    );
  }
}

class _CourierPainter extends CustomPainter {
  const _CourierPainter({required this.carriesParcel});

  final bool carriesParcel;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    final Paint trousers = Paint()..color = HeroPalette.trousers;
    final Paint uniform = Paint()..color = HeroPalette.uniform;
    final Paint skin = Paint()..color = HeroPalette.skin;
    final Paint sleeve = Paint()..color = HeroPalette.uniformDark;

    RRect bar(double l, double t, double r, double b, double radius) {
      return RRect.fromRectAndRadius(
        Rect.fromLTRB(w * l, h * t, w * r, h * b),
        Radius.circular(w * radius),
      );
    }

    // Ground shadow.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.99),
        width: w * 0.86,
        height: h * 0.05,
      ),
      Paint()..color = AppColors.navy.withValues(alpha: 0.10),
    );

    // Legs, then shoes.
    canvas.drawRRect(bar(0.26, 0.60, 0.46, 0.95, 0.09), trousers);
    canvas.drawRRect(bar(0.54, 0.60, 0.74, 0.95, 0.09), trousers);
    canvas.drawRRect(
      bar(0.22, 0.92, 0.48, 0.98, 0.03),
      Paint()..color = HeroPalette.shoes,
    );
    canvas.drawRRect(
      bar(0.52, 0.92, 0.78, 0.98, 0.03),
      Paint()..color = HeroPalette.shoes,
    );

    // Torso and sleeves.
    canvas.drawRRect(bar(0.10, 0.36, 0.28, 0.60, 0.09), sleeve);
    canvas.drawRRect(bar(0.72, 0.36, 0.90, 0.60, 0.09), sleeve);
    canvas.drawRRect(bar(0.22, 0.29, 0.78, 0.64, 0.15), uniform);

    // A lighter placket down the middle of the shirt.
    canvas.drawRRect(
      bar(0.47, 0.31, 0.53, 0.62, 0.02),
      Paint()..color = HeroPalette.uniformDark,
    );

    if (carriesParcel) {
      // Hands come forward to hold the parcel.
      canvas.drawCircle(Offset(w * 0.19, h * 0.61), w * 0.085, skin);
      canvas.drawCircle(Offset(w * 0.81, h * 0.61), w * 0.085, skin);
      final RRect box = bar(0.22, 0.50, 0.78, 0.72, 0.04);
      canvas.drawRRect(box, Paint()..color = HeroPalette.parcel);
      canvas.drawRRect(
        bar(0.46, 0.50, 0.54, 0.72, 0.01),
        Paint()..color = HeroPalette.parcelTape,
      );
      canvas.drawRRect(
        bar(0.22, 0.58, 0.78, 0.63, 0.01),
        Paint()..color = HeroPalette.parcelTape,
      );
    } else {
      // One hand raised in a wave.
      canvas.drawCircle(Offset(w * 0.19, h * 0.61), w * 0.085, skin);
      canvas.drawRRect(bar(0.74, 0.22, 0.90, 0.44, 0.08), sleeve);
      canvas.drawCircle(Offset(w * 0.82, h * 0.21), w * 0.085, skin);
    }

    _paintHeadWithCap(canvas, w, h, skin);
  }

  void _paintHeadWithCap(Canvas canvas, double w, double h, Paint skin) {
    final Offset head = Offset(w * 0.5, h * 0.18);
    final double radius = w * 0.20;

    canvas.drawCircle(head, radius, skin);

    // Cap: the top half of a circle, plus a brim to the right.
    canvas.drawArc(
      Rect.fromCircle(center: head, radius: radius * 1.06),
      math.pi,
      math.pi,
      true,
      Paint()..color = HeroPalette.uniform,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(head.dx + radius * 0.52, head.dy - radius * 0.04),
        width: radius * 1.70,
        height: radius * 0.42,
      ),
      Paint()..color = HeroPalette.uniformDark,
    );
  }

  @override
  bool shouldRepaint(covariant _CourierPainter oldDelegate) =>
      oldDelegate.carriesParcel != carriesParcel;
}

/// The customer: long hair, coral top, phone held up in one hand.
class CustomerFigure extends StatelessWidget {
  const CustomerFigure({super.key, this.height = 118});

  final double height;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(height * 0.62, height),
      painter: _CustomerPainter(),
    );
  }
}

class _CustomerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    final Paint skin = Paint()..color = HeroPalette.skin;
    final Paint blouse = Paint()..color = HeroPalette.blouse;

    RRect bar(double l, double t, double r, double b, double radius) {
      return RRect.fromRectAndRadius(
        Rect.fromLTRB(w * l, h * t, w * r, h * b),
        Radius.circular(w * radius),
      );
    }

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.99),
        width: w * 0.82,
        height: h * 0.05,
      ),
      Paint()..color = AppColors.navy.withValues(alpha: 0.10),
    );

    // Legs and shoes.
    canvas.drawRRect(
      bar(0.28, 0.60, 0.46, 0.95, 0.08),
      Paint()..color = HeroPalette.trousers,
    );
    canvas.drawRRect(
      bar(0.54, 0.60, 0.72, 0.95, 0.08),
      Paint()..color = HeroPalette.trousers,
    );
    canvas.drawRRect(
      bar(0.24, 0.92, 0.48, 0.98, 0.03),
      Paint()..color = HeroPalette.shoes,
    );
    canvas.drawRRect(
      bar(0.52, 0.92, 0.76, 0.98, 0.03),
      Paint()..color = HeroPalette.shoes,
    );

    // Hair falls behind the shoulders, so it is painted first.
    final Offset head = Offset(w * 0.5, h * 0.18);
    final double radius = w * 0.20;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.26, h * 0.06, w * 0.74, h * 0.46),
        Radius.circular(w * 0.24),
      ),
      Paint()..color = HeroPalette.hair,
    );

    // Sleeves in a deeper coral first, so they read as arms rather than
    // widening the torso into one blob.
    final Paint sleeve = Paint()..color = HeroPalette.blouseDark;
    canvas.drawRRect(bar(0.10, 0.36, 0.27, 0.60, 0.08), sleeve);
    canvas.drawRRect(bar(0.73, 0.36, 0.90, 0.52, 0.08), sleeve);
    canvas.drawRRect(bar(0.22, 0.30, 0.78, 0.64, 0.15), blouse);

    // Free hand at her side.
    canvas.drawCircle(Offset(w * 0.185, h * 0.61), w * 0.085, skin);

    // Head sits over the hair, leaving it visible as a frame.
    canvas.drawCircle(head, radius, skin);

    // The other hand comes across to hold the phone in front of her chest.
    canvas.drawRRect(
      bar(0.46, 0.40, 0.66, 0.60, 0.035),
      Paint()..color = HeroPalette.device,
    );
    canvas.drawRRect(
      bar(0.485, 0.425, 0.635, 0.575, 0.02),
      Paint()..color = AppColors.primaryLight,
    );
    canvas.drawCircle(Offset(w * 0.70, h * 0.55), w * 0.085, skin);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
