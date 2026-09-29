import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_text_styles.dart';

/// Where something is on a [SugoRouteLine]: waiting *at* a stop, or
/// travelling the leg *after* one.
///
/// Two kinds of position rather than a free-running percentage, on purpose.
/// The database records which stage a job is in - `jobs.status`, the tracking
/// stage - and never "62% of the way". A position can only be one of the
/// states the data can actually say, so the line cannot claim more progress
/// than the server has recorded.
@immutable
class SugoRoutePosition {
  /// Waiting at [stop]: reached it, and nothing is moving towards the next.
  const SugoRoutePosition.at(this.stop) : moving = false;

  /// Travelling the leg from [stop] towards the one after it.
  const SugoRoutePosition.leaving(this.stop) : moving = true;

  /// Index of the last stop reached.
  final int stop;

  /// True while on the leg after [stop].
  final bool moving;

  /// The marker's place along the line, in stops: 1.0 is the second stop,
  /// 1.5 half way along the leg after it.
  double get progress => stop + (moving ? 0.5 : 0);

  @override
  bool operator ==(Object other) =>
      other is SugoRoutePosition &&
      other.stop == stop &&
      other.moving == moving;

  @override
  int get hashCode => Object.hash(stop, moving);
}

/// The Dispatch signature: a job drawn as a trip.
///
/// *Sugo* means sending someone on an errand, and that is what the app does -
/// it sends a technician to a broken device and back. So wherever a job's
/// progress is shown (the home card, the matching screen, the booking, the
/// technician's active job) it is drawn the same way: a dashed route with
/// named stops, the distance already covered solid in SUGO blue, and the
/// service van from the logo marking where the job is now.
///
/// The marker was the logo's paper plane until the 2026-09-29 rebrand retired
/// the plane (it read as Telegram's). The van is the better fit anyway: the
/// new emblem and the splash both say "from your home to our shop", and a van
/// on a road is literally that.
///
/// ## Reading it without colour
///
/// Stops behind are filled discs, stops ahead are hollow rings, and the line
/// ahead is dashed where the line behind is solid - three differences of
/// *shape*, so it survives greyscale and colour blindness. The current stop's
/// label is also the only bold one.
///
/// ## Motion
///
/// The van slides when the position changes - that is the app reporting a
/// real change, so it moves. It never moves on its own, and under "remove
/// animations" it jumps instead of sliding.
class SugoRouteLine extends StatelessWidget {
  const SugoRouteLine({
    super.key,
    required this.stops,
    required this.position,
  });

  /// Stop names, first to last - short words ("Posted", "Matched"). At least
  /// two; checked in [build], because a const constructor cannot read a
  /// list's length.
  final List<String> stops;

  final SugoRoutePosition position;

  /// Diameter of the van marker.
  static const double markerSize = 24;

  static const double _labelGap = 6;

  int get _last => stops.length - 1;

  /// The position clamped onto this route, so a stage the caller did not
  /// expect can never draw the van off the end of the line.
  SugoRoutePosition get _safe {
    final int stop = position.stop.clamp(0, _last);
    return stop == _last
        ? SugoRoutePosition.at(_last)
        : (position.moving
              ? SugoRoutePosition.leaving(stop)
              : SugoRoutePosition.at(stop));
  }

  String get _spoken {
    final SugoRoutePosition p = _safe;
    final String here = stops[p.stop];
    if (p.moving) {
      return 'Progress: past $here, on the way to ${stops[p.stop + 1]}. '
          'Stop ${p.stop + 1} of ${stops.length} reached.';
    }
    return 'Progress: $here. Stop ${p.stop + 1} of ${stops.length} reached.';
  }

  @override
  Widget build(BuildContext context) {
    assert(stops.length >= 2, 'A route needs at least two stops.');
    final SugoRoutePosition p = _safe;
    final bool arrived = p.stop == _last && !p.moving;
    final double target = p.progress;

    return Semantics(
      label: _spoken,
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        // Begins at the target, so the first frame draws the van in place;
        // only a later change of position slides it.
        tween: Tween<double>(begin: target, end: target),
        duration: AppMotion.reduced(context) ? Duration.zero : AppMotion.slow,
        curve: AppMotion.emphasized,
        builder: (BuildContext context, double progress, Widget? labels) {
          return LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double column = constraints.maxWidth / stops.length;
              final double x = column / 2 + progress * column;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    height: markerSize,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _RoutePainter(
                              count: stops.length,
                              progress: progress,
                              reached: p.stop,
                            ),
                          ),
                        ),
                        Positioned(
                          left: x - markerSize / 2,
                          top: 0,
                          child: _Marker(arrived: arrived),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: _labelGap),
                  labels!,
                ],
              );
            },
          );
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (int i = 0; i < stops.length; i++)
              Expanded(
                child: Text(
                  stops[i],
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: i == p.stop
                      ? AppTextStyles.micro.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                        )
                      : AppTextStyles.micro.copyWith(
                          fontWeight: i < p.stop
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The navy disc: the logo's van while under way, a tick on arrival. The van
/// faces right, the way the route runs.
class _Marker extends StatelessWidget {
  const _Marker({required this.arrived});

  final bool arrived;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: SugoRouteLine.markerSize,
      height: SugoRouteLine.markerSize,
      decoration: const BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(
        arrived ? Icons.check_rounded : Icons.local_shipping_rounded,
        size: arrived ? 15 : 14,
        color: Colors.white,
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  const _RoutePainter({
    required this.count,
    required this.progress,
    required this.reached,
  });

  final int count;

  /// Where the van is, in stops. May be mid-animation.
  final double progress;

  /// The last stop the data says was reached.
  final int reached;

  static const double _dot = 10;
  static const double _dash = 5;
  static const double _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final double column = size.width / count;
    final double y = size.height / 2;
    double xAt(double stop) => column / 2 + stop * column;

    final double start = xAt(0);
    final double end = xAt(count - 1.0);
    final double here = xAt(progress);

    // What is still ahead: a dashed hairline.
    final Paint dashed = Paint()
      ..color = AppColors.border
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (double x = here; x < end; x += _dash + _gap) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + _dash, end), y),
        dashed,
      );
    }

    // What is behind: solid SUGO blue.
    if (here > start) {
      canvas.drawLine(
        Offset(start, y),
        Offset(here, y),
        Paint()
          ..color = AppColors.secondary
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }

    // The stops. The marker is drawn over whichever one it sits on.
    for (int i = 0; i < count; i++) {
      final Offset c = Offset(xAt(i.toDouble()), y);
      if (i <= reached) {
        canvas.drawCircle(c, _dot / 2, Paint()..color = AppColors.secondary);
      } else {
        canvas.drawCircle(c, _dot / 2, Paint()..color = AppColors.surface);
        canvas.drawCircle(
          c,
          _dot / 2 - 1,
          Paint()
            ..color = AppColors.border
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RoutePainter old) =>
      old.progress != progress || old.count != count || old.reached != reached;
}
