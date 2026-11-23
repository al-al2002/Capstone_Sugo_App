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
/// Their request as a small SUGO task card - white, a blue edge, a cyan dot,
/// the dashed route line - lifts, tips and drops into a navy-and-white bin
/// standing on SUGO's soft blue disc. The lid shuts with a little burst of
/// cyan, blue and orange, the bin settles, and a blue-to-cyan tick (the same
/// tick the matching checklist uses) ripples in over "Request deleted". About
/// a second in all.
///
/// Redrawn in the brand at the user's request on 2026-11-23 ("make the delete
/// animation like deleting a task fit on SUGO"). It was black on white since
/// 2026-09-28, at the client's request then; the timing below is unchanged.
///
/// ## Why it runs *with* the request, not after it
///
/// The animation plays while the server call is in flight, and the tick only
/// appears once that call has succeeded and the drop has finished - whichever
/// is later. So a slow network holds on the closed bin rather than claiming
/// success early, and a fast one still gets the whole gesture rather than a
/// flash. If the call fails the dialog closes at once and the error is
/// rethrown, so the caller's own error handling is unchanged.
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
  /// The drop: card up, lid up, card in, lid down, burst, settle. Assigned in
  /// [initState], not lazily - see the `late final` trap in
  /// `docs/design-system.md`.
  late final AnimationController _drop;

  bool _done = false;

  @override
  void initState() {
    super.initState();
    _drop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
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
    final bool reduced = AppMotion.reduced(context);

    return Center(
      child: Material(
        color: AppColors.surface,
        elevation: 10,
        shadowColor: AppColors.navy.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppSizes.sheetRadius),
        child: SizedBox(
          width: 200,
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
                  dimension: 100,
                  child: AnimatedSwitcher(
                    duration: reduced
                        ? Duration.zero
                        : const Duration(milliseconds: 280),
                    transitionBuilder: (Widget child, Animation<double> a) =>
                        ScaleTransition(
                          scale: CurvedAnimation(
                            parent: a,
                            curve: Curves.easeOutBack,
                          ),
                          child: FadeTransition(opacity: a, child: child),
                        ),
                    child: _done
                        ? _DoneTick(
                            key: const ValueKey<String>('done'),
                            reduced: reduced,
                          )
                        : AnimatedBuilder(
                            key: const ValueKey<String>('bin'),
                            animation: _drop,
                            // Expanded to the square: a CustomPaint with no
                            // child sizes itself to zero under the switcher's
                            // loose constraints, and paints nothing.
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
                    style: AppTextStyles.titleSmall.copyWith(
                      color: AppColors.primary,
                    ),
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

/// The finish: SUGO's blue-to-cyan tick, with one ripple off it.
class _DoneTick extends StatelessWidget {
  const _DoneTick({super.key, required this.reduced});

  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final Widget disc = Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[AppColors.secondary, AppColors.cyan],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.cyan.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Icon(Icons.check_rounded, size: 46, color: Colors.white),
    );

    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: reduced ? Duration.zero : const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
        builder: (BuildContext _, double v, Widget? child) => Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Transform.scale(
              scale: 1 + 0.38 * v,
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.cyan.withValues(alpha: 0.6 * (1 - v)),
                    width: 2,
                  ),
                ),
              ),
            ),
            child!,
          ],
        ),
        child: disc,
      ),
    );
  }
}

/// The task card, the bin and the burst, animated by [t] from 0 to 1.
///
/// | t          | what happens                                        |
/// |------------|-----------------------------------------------------|
/// | 0.00-0.16  | the task card lifts and tips back a little          |
/// | 0.04-0.26  | the lid swings open on its right end                |
/// | 0.18-0.62  | the card tips forward and drops in, behind the bin's |
/// |            | front, so it disappears into it                     |
/// | 0.62-0.78  | the lid swings shut                                 |
/// | 0.66-0.96  | a burst of cyan, blue and orange off the lid        |
/// | 0.85-1.00  | the bin gives a small settle                        |
class _BinPainter extends CustomPainter {
  _BinPainter(this.t);

  final double t;

  static const Color _navy = AppColors.primary;
  static const Color _blue = AppColors.secondary;
  static const Color _cyan = AppColors.cyan;
  static const Color _edge = Color(0xFFC3D2EA);

  double _phase(double start, double end, [Curve curve = Curves.easeInOut]) =>
      curve.transform(((t - start) / (end - start)).clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.shortestSide / 100;
    canvas.scale(s);

    // The soft blue disc the bin stands on - SUGO's icon-tile wash.
    canvas.drawCircle(
      const Offset(50, 56),
      44,
      Paint()..color = AppColors.primarySoft,
    );

    // Settle: a quick squash of the whole bin at the end.
    final double settle = math.sin(_phase(0.85, 1.0) * math.pi) * 0.05;
    canvas
      ..save()
      ..translate(50, 90)
      ..scale(1 + settle, 1 - settle)
      ..translate(-50, -90);

    // Card first, so the bin's front hides it as it goes in.
    _card(canvas);
    _body(canvas);
    _lid(canvas);
    canvas.restore();

    _burst(canvas);
  }

  /// The request, as a small SUGO task card.
  void _card(Canvas canvas) {
    final double lift = _phase(0.0, 0.16, Curves.easeOutCubic);
    final double fall = _phase(0.18, 0.62, Curves.easeInCubic);
    if (fall >= 1) return;

    final double y = 22 - 8 * lift + 56 * fall;
    final double angle = -0.14 * lift + 0.5 * fall;
    final double scale = 1 + 0.06 * lift - 0.22 * fall;

    canvas
      ..save()
      ..translate(50, y)
      ..rotate(angle)
      ..scale(scale);

    final RRect card = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: 38, height: 26),
      const Radius.circular(4.5),
    );
    canvas
      ..drawRRect(
        card.shift(const Offset(0, 2.5)),
        Paint()
          ..color = _navy.withValues(alpha: 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      )
      ..drawRRect(card, Paint()..color = Colors.white)
      ..save()
      ..clipRRect(card)
      ..drawRect(const Rect.fromLTWH(-19, -13, 4, 26), Paint()..color = _blue)
      ..restore()
      ..drawRRect(
        card,
        Paint()
          ..color = _edge
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );

    // A cyan dot and two lines of "text".
    canvas.drawCircle(const Offset(-9.5, -6), 2.5, Paint()..color = _cyan);
    canvas
      ..drawLine(
        const Offset(-4.5, -6),
        const Offset(12, -6),
        Paint()
          ..color = _navy
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round,
      )
      ..drawLine(
        const Offset(-12, 1),
        const Offset(7, 1),
        Paint()
          ..color = AppColors.textSecondary.withValues(alpha: 0.55)
          ..strokeWidth = 2.1
          ..strokeCap = StrokeCap.round,
      );

    // The route line, in miniature.
    final Paint dash = Paint()
      ..color = _blue.withValues(alpha: 0.75)
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round;
    for (double x = -12; x < 11; x += 5) {
      canvas.drawLine(Offset(x, 7.5), Offset(x + 2.4, 7.5), dash);
    }

    canvas.restore();
  }

  /// A tapered bucket: white, navy outline, blue ribs.
  void _body(Canvas canvas) {
    final Path outline = Path()
      ..moveTo(26, 40)
      ..lineTo(31, 84)
      ..quadraticBezierTo(32, 90, 38, 90)
      ..lineTo(62, 90)
      ..quadraticBezierTo(68, 90, 69, 84)
      ..lineTo(74, 40);
    final Path fill = Path.from(outline)..close();

    canvas
      ..drawPath(fill, Paint()..color = Colors.white)
      ..drawPath(
        outline,
        Paint()
          ..color = _navy
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );

    final Paint ribs = Paint()
      ..color = _blue
      ..strokeWidth = 3.6
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(const Offset(41.5, 51), const Offset(42.5, 79), ribs)
      ..drawLine(const Offset(50, 51), const Offset(50, 79), ribs)
      ..drawLine(const Offset(58.5, 51), const Offset(57.5, 79), ribs);
  }

  /// A solid navy lid, hinged at its right end: up, then back down.
  /// Clockwise (positive, with y pointing down) lifts the free left end.
  void _lid(Canvas canvas) {
    final double open = _phase(0.04, 0.26) * (1 - _phase(0.62, 0.78));
    canvas
      ..save()
      ..translate(78, 33)
      ..rotate(0.8 * open)
      ..translate(-78, -33)
      ..drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTRB(20, 29, 80, 37),
          const Radius.circular(4),
        ),
        Paint()..color = _navy,
      )
      ..drawPath(
        Path()
          ..moveTo(42, 29)
          ..lineTo(42, 23)
          ..lineTo(58, 23)
          ..lineTo(58, 29),
        Paint()
          ..color = _navy
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      )
      // A cyan glint along the lid's top edge.
      ..drawLine(
        const Offset(26, 31),
        const Offset(40, 31),
        Paint()
          ..color = _cyan.withValues(alpha: 0.85)
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round,
      )
      ..restore();
  }

  /// A small burst off the lid as it shuts: "gone".
  void _burst(Canvas canvas) {
    final double p = _phase(0.66, 0.96, Curves.easeOutCubic);
    if (p <= 0 || p >= 1) return;

    const List<(double, Color, double)> bits = <(double, Color, double)>[
      (-2.62, _cyan, 3.0),
      (-2.15, _blue, 2.4),
      (-1.75, AppColors.accent, 2.6),
      (-1.40, _cyan, 2.2),
      (-0.98, _blue, 2.8),
      (-0.52, _cyan, 2.4),
    ];
    for (final (double angle, Color colour, double radius) in bits) {
      final double distance = 8 + 24 * p;
      canvas.drawCircle(
        Offset(
          50 + math.cos(angle) * distance,
          28 + math.sin(angle) * distance,
        ),
        radius * (1 - 0.4 * p),
        Paint()..color = colour.withValues(alpha: 1 - p),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BinPainter oldDelegate) => oldDelegate.t != t;
}
