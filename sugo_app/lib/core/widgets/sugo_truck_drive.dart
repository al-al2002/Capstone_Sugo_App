import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../theme/app_motion.dart';

/// A truck driving down a road: the tracking screens' sign that a trip is
/// under way (2026-09-29, "butangi og truck animation").
///
/// ## What it says, and what it does not
///
/// The truck stays put and the road runs beneath it, the way a vehicle looks
/// from the one beside it. That says "moving" without saying "how far": the
/// map and the arrival time answer that, from real data. A truck crossing a
/// bar would look like progress, and nothing here would make it true - the
/// same honesty rule as the booking route line.
///
/// So it only drives while the position is live ([moving]). A trip whose
/// position has gone quiet parks the truck and greys it, rather than showing
/// wheels turning for someone who may be stuck. Under "remove animations" it
/// is a still picture.
class SugoTruckDrive extends StatefulWidget {
  const SugoTruckDrive({
    super.key,
    this.moving = true,
    this.icon = Icons.local_shipping_rounded,
    this.destinationIcon,
    this.semanticLabel = 'On the way',
  });

  /// True while the traveller's position is live.
  final bool moving;

  /// The vehicle. A truck for the technician; the client's own trip to the
  /// workshop may pass something else.
  final IconData icon;

  /// Where the road ends - a house, a shop. Null for an open road.
  final IconData? destinationIcon;

  final String semanticLabel;

  static const double height = 56;

  @override
  State<SugoTruckDrive> createState() => _SugoTruckDriveState();
}

class _SugoTruckDriveState extends State<SugoTruckDrive>
    with SingleTickerProviderStateMixin {
  // Assigned in initState, never lazily - see the `late final` trap in
  // docs/design-system.md.
  late final AnimationController _drive;

  @override
  void initState() {
    super.initState();
    _drive = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(SugoTruckDrive oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final bool drive = widget.moving && !AppMotion.reduced(context);
    if (drive && !_drive.isAnimating) {
      _drive.repeat();
    } else if (!drive && _drive.isAnimating) {
      _drive.stop();
    }
  }

  @override
  void dispose() {
    _drive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color truck = widget.moving ? AppColors.primary : AppColors.hint;

    return Semantics(
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: Container(
        height: SugoTruckDrive.height,
        decoration: BoxDecoration(
          color: AppColors.primarySofter,
          borderRadius: BorderRadius.circular(AppSizes.radius),
        ),
        clipBehavior: Clip.antiAlias,
        child: AnimatedBuilder(
          animation: _drive,
          builder: (BuildContext context, Widget? _) {
            final double t = _drive.value;
            // Two small bumps per loop: the cab rides the road, not a rail.
            final double bob = widget.moving
                ? -1.6 * math.sin(t * math.pi * 2 * 2).abs()
                : 0;

            return LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) {
                final double truckX = box.maxWidth * 0.36;
                return Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _RoadPainter(
                          offset: widget.moving ? t : 0,
                        ),
                      ),
                    ),
                    if (widget.moving)
                      Positioned(
                        left: truckX - 26,
                        top: 20,
                        child: _SpeedLines(phase: t),
                      ),
                    Positioned(
                      // Wheels on the kerb line (height - 12).
                      left: truckX,
                      top: 13 + bob,
                      child: Icon(widget.icon, size: 30, color: truck),
                    ),
                    if (widget.destinationIcon != null)
                      Positioned(
                        right: AppSizes.md,
                        top: 18,
                        child: Icon(
                          widget.destinationIcon,
                          size: 24,
                          color: AppColors.accentDark,
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// The road: a kerb line and a dashed centre line that scrolls left, so the
/// truck above it appears to drive right.
class _RoadPainter extends CustomPainter {
  const _RoadPainter({required this.offset});

  /// 0..1 of one dash-and-gap.
  final double offset;

  static const double _dash = 12;
  static const double _gap = 10;

  @override
  void paint(Canvas canvas, Size size) {
    final double kerb = size.height - 12;
    canvas.drawLine(
      Offset(0, kerb),
      Offset(size.width, kerb),
      Paint()
        ..color = AppColors.primarySoft
        ..strokeWidth = 2,
    );

    final Paint dash = Paint()
      ..color = AppColors.secondary.withValues(alpha: 0.45)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final double y = kerb + 6;
    final double shift = offset * (_dash + _gap);
    for (double x = -shift; x < size.width; x += _dash + _gap) {
      canvas.drawLine(Offset(x, y), Offset(x + _dash, y), dash);
    }
  }

  @override
  bool shouldRepaint(covariant _RoadPainter oldDelegate) =>
      oldDelegate.offset != offset;
}

/// Three short strokes trailing the truck, flickering with its speed.
class _SpeedLines extends StatelessWidget {
  const _SpeedLines({required this.phase});

  final double phase;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        for (int i = 0; i < 3; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: 4),
          Opacity(
            opacity: (0.25 + 0.55 * ((phase + i / 3) % 1)).clamp(0.0, 1.0),
            child: Container(
              width: i == 1 ? 18 : 12,
              height: 2.5,
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
