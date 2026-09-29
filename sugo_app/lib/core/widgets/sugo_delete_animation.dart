import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../theme/app_motion.dart';
import '../theme/app_text_styles.dart';

/// Runs [task] - a delete - under a short animation, and returns its result.
///
/// ## What the person sees
///
/// A black bin: the lid lifts, the request drops in, the lid closes, then a
/// black tick and "Request deleted". About a second in all.
///
/// ## Why it runs *with* the request, not after it
///
/// The animation plays while the server call is in flight, and the tick only
/// appears once that call has succeeded and the drop has finished - whichever
/// is later. So a slow network holds on the closed bin rather than claiming
/// success early, and a fast one still gets the whole gesture rather than a
/// flash. If the call fails the dialog closes at once and the error is
/// rethrown, so the caller's own error handling is unchanged.
///
/// Black on white, at the client's request (2026-09-28).
Future<T> runWithDeleteAnimation<T>(
  BuildContext context,
  Future<T> task, {
  String doneLabel = 'Request deleted',
}) async {
  final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
  final GlobalKey<_DeleteAnimationState> key =
      GlobalKey<_DeleteAnimationState>();

  // Not awaited: the dialog stays up until this function pops it.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext _) => PopScope(
      canPop: false,
      child: _DeleteAnimation(key: key, doneLabel: doneLabel),
    ),
  );

  try {
    final T result = await task;
    await key.currentState?.finish();
    if (navigator.mounted) navigator.pop();
    return result;
  } catch (_) {
    if (navigator.mounted) navigator.pop();
    rethrow;
  }
}

class _DeleteAnimation extends StatefulWidget {
  const _DeleteAnimation({super.key, required this.doneLabel});

  final String doneLabel;

  @override
  State<_DeleteAnimation> createState() => _DeleteAnimationState();
}

class _DeleteAnimationState extends State<_DeleteAnimation>
    with SingleTickerProviderStateMixin {
  /// The drop: lid up, request in, lid down, a settle. Assigned in
  /// [initState], not lazily - see the `late final` trap in
  /// `docs/design-system.md`.
  late final AnimationController _drop;

  bool _done = false;

  @override
  void initState() {
    super.initState();
    _drop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Under "remove animations" the bin is shown already closed and the tick
    // replaces it without the pop. The wait for the server is unchanged, so
    // the dialog still never claims success early.
    if (AppMotion.reduced(context)) {
      _drop.value = 1;
    } else if (_drop.value == 0 && !_drop.isAnimating) {
      _drop.forward();
    }
  }

  /// Waits for the drop to finish, shows the tick, and holds it briefly so it
  /// can be read before the dialog closes.
  Future<void> finish() async {
    if (_drop.isAnimating) await _drop.forward().orCancel.catchError((_) {});
    if (!mounted) return;
    setState(() => _done = true);
    await Future<void>.delayed(const Duration(milliseconds: 650));
  }

  @override
  void dispose() {
    _drop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.panelRadius),
        child: SizedBox(
          width: 190,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.lg,
              AppSizes.xl,
              AppSizes.lg,
              AppSizes.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox.square(
                  dimension: 92,
                  child: AnimatedSwitcher(
                    duration: AppMotion.reduced(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 260),
                    transitionBuilder: (Widget child, Animation<double> a) =>
                        ScaleTransition(
                          scale: CurvedAnimation(
                            parent: a,
                            curve: Curves.easeOutBack,
                          ),
                          child: FadeTransition(opacity: a, child: child),
                        ),
                    child: _done
                        ? const Icon(
                            Icons.check_circle_rounded,
                            key: ValueKey<String>('done'),
                            size: 76,
                            color: AppColors.textPrimary,
                          )
                        : AnimatedBuilder(
                            key: const ValueKey<String>('bin'),
                            animation: _drop,
                            // Expanded to the 92px square: a CustomPaint with
                            // no child sizes itself to zero under the
                            // switcher's loose constraints, and paints nothing.
                            builder: (BuildContext _, Widget? _) =>
                                SizedBox.expand(
                                  child: CustomPaint(
                                    painter: _BinPainter(_drop.value),
                                  ),
                                ),
                          ),
                  ),
                ),
                const SizedBox(height: AppSizes.md),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    _done ? widget.doneLabel : 'Deleting...',
                    key: ValueKey<bool>(_done),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.titleSmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A bin drawn in black strokes, animated by [t] from 0 to 1.
///
/// | t          | what happens                         |
/// |------------|--------------------------------------|
/// | 0.00-0.25  | the lid swings open on its right end |
/// | 0.15-0.70  | the request drops in, fading as it enters |
/// | 0.70-0.85  | the lid swings shut                  |
/// | 0.85-1.00  | the bin gives a small settle         |
class _BinPainter extends CustomPainter {
  _BinPainter(this.t);

  final double t;

  static const Color _ink = AppColors.textPrimary;

  double _phase(double start, double end) =>
      Curves.easeInOut.transform(((t - start) / (end - start)).clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.shortestSide / 100;
    canvas.scale(s);

    final Paint stroke = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Settle: a quick squash of the whole bin at the end.
    final double settle = math.sin(_phase(0.85, 1.0) * math.pi) * 0.05;
    canvas
      ..save()
      ..translate(50, 90)
      ..scale(1 + settle, 1 - settle)
      ..translate(-50, -90);

    // The request, as a small card, dropping in while the lid is up.
    final double fall = _phase(0.15, 0.70);
    final double cardOpacity = 1 - _phase(0.55, 0.70);
    if (fall > 0 && cardOpacity > 0) {
      final double y = -6 + fall * 62;
      final Paint card = Paint()
        ..color = _ink.withValues(alpha: cardOpacity)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(50, y), width: 26, height: 18),
          const Radius.circular(4),
        ),
        card,
      );
      // Two lines of "text" on the card, cut out in white.
      final Paint lines = Paint()
        ..color = Colors.white.withValues(alpha: cardOpacity)
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round;
      canvas
        ..drawLine(Offset(42, y - 3), Offset(58, y - 3), lines)
        ..drawLine(Offset(42, y + 3), Offset(53, y + 3), lines);
    }

    // Body: a tapered bucket with rounded bottom corners.
    final Path body = Path()
      ..moveTo(26, 40)
      ..lineTo(31, 84)
      ..quadraticBezierTo(32, 90, 38, 90)
      ..lineTo(62, 90)
      ..quadraticBezierTo(68, 90, 69, 84)
      ..lineTo(74, 40);
    canvas.drawPath(body, stroke);

    final Paint ribs = Paint()
      ..color = _ink
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(const Offset(42, 52), const Offset(43, 78), ribs)
      ..drawLine(const Offset(50, 52), const Offset(50, 78), ribs)
      ..drawLine(const Offset(58, 52), const Offset(57, 78), ribs);

    // Lid: hinged at its right end, swung up and then back down. Clockwise
    // (positive, with y pointing down) is what lifts the free left end; the
    // first version turned the other way and swung the lid into the bin.
    final double open = _phase(0.0, 0.25) * (1 - _phase(0.70, 0.85));
    canvas
      ..save()
      ..translate(78, 32)
      ..rotate(0.75 * open)
      ..translate(-78, -32);
    final Path lid = Path()
      ..moveTo(20, 32)
      ..lineTo(80, 32)
      ..moveTo(41, 32)
      ..lineTo(41, 24)
      ..lineTo(59, 24)
      ..lineTo(59, 32);
    canvas
      ..drawPath(lid, stroke)
      ..restore()
      ..restore();
  }

  @override
  bool shouldRepaint(covariant _BinPainter oldDelegate) => oldDelegate.t != t;
}
