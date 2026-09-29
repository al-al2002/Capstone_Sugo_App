import 'package:flutter/material.dart';

import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_text_styles.dart';

/// The splash screen's loading animation: the SUGO van driving along a dashed
/// road, over "Getting SUGO ready...".
///
/// The van is the same one the app uses everywhere a job is on its way (the
/// route line on the home card and the booking), and the one on the new logo,
/// so the first moving thing a person sees is the thing the app does.
///
/// It loops for as long as the app is actually loading - it is not a timer
/// dressed as progress, so it says nothing about *how far* along the load is.
/// Under "remove animations" the van parks in the middle of the road and the
/// words alone say that something is happening.
class SplashLoader extends StatefulWidget {
  const SplashLoader({super.key, this.label = 'Getting SUGO ready...'});

  final String label;

  /// Width of the road.
  static const double roadWidth = 200;

  @override
  State<SplashLoader> createState() => _SplashLoaderState();
}

class _SplashLoaderState extends State<SplashLoader>
    with SingleTickerProviderStateMixin {
  // Assigned in initState, never lazily - see the `late final` trap in
  // docs/design-system.md.
  late final AnimationController _drive;

  static const double _van = 26;

  @override
  void initState() {
    super.initState();
    _drive = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _drive
        ..stop()
        ..value = 0.5;
    } else if (!_drive.isAnimating) {
      _drive.repeat();
    }
  }

  @override
  void dispose() {
    _drive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      liveRegion: true,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: SplashLoader.roadWidth,
            height: _van + 6,
            child: AnimatedBuilder(
              animation: _drive,
              builder: (BuildContext context, Widget? van) {
                // Eases in and out of each crossing so the van reads as
                // driving, not sliding; fades at both ends of the road so it
                // enters and leaves rather than teleporting back.
                final double t = Curves.easeInOut.transform(_drive.value);
                final double fade = (1 - (2 * _drive.value - 1).abs()) * 4;
                return Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 2,
                      child: CustomPaint(
                        size: Size(SplashLoader.roadWidth, 2),
                        painter: _RoadPainter(),
                      ),
                    ),
                    Positioned(
                      left: t * (SplashLoader.roadWidth - _van),
                      bottom: 5,
                      child: Opacity(
                        opacity: fade.clamp(0.0, 1.0),
                        child: van,
                      ),
                    ),
                  ],
                );
              },
              child: const Icon(
                Icons.local_shipping_rounded,
                size: _van,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            widget.label,
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The dashed road, in faint white so it reads on the poster's blue.
class _RoadPainter extends CustomPainter {
  const _RoadPainter();

  static const double _dash = 8;
  static const double _gap = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = const Color(0x8CFFFFFF)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final double y = size.height / 2;
    for (double x = 0; x < size.width; x += _dash + _gap) {
      final double end = x + _dash > size.width ? size.width : x + _dash;
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RoadPainter oldDelegate) => false;
}
