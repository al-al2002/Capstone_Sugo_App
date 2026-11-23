import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/technician.dart';
import 'request_send_intro.dart';
import 'technician_avatar.dart';
import 'technician_matching_loader.dart';

/// Sends a booking request under a short "fly away" animation, and returns
/// whether it went through (2026-11-23).
///
/// ## What the client sees
///
/// They tap **Send request**; the sheet closes, and their request - the
/// sealed SUGO envelope from the letter animation - lifts off, flies up
/// along SUGO's dashed route to the technician's photo, tilting into each
/// curve, and disappears into it. The photo ripples cyan, a tick pops on it,
/// and the card says "Request sent to Lyra".
///
/// ## Honest, like the delete animation
///
/// It runs WITH the request, not after it. The tick appears only once the
/// server has accepted the request and the flight has landed, whichever is
/// later: on a slow network the photo shows a turning "waiting" ring rather
/// than claiming success early, and a fast one still gets the whole flight.
/// A refused request ([task] returns false) or a failed one (it throws)
/// closes the animation at once, with no tick, and the caller's own error
/// handling takes over - exactly as before.
///
/// No paper plane: SUGO retired it in the September rebrand because it read
/// as Telegram. The envelope is SUGO's own messenger.
Future<bool> runWithSendAnimation(
  BuildContext context,
  Future<bool> task, {
  required String name,
  Technician? technician,
}) async {
  final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
  final GlobalKey<_SendAnimationState> key = GlobalKey<_SendAnimationState>();

  // Not awaited: the dialog stays up until this function pops it.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: AppColors.navy.withValues(alpha: 0.55),
    builder: (BuildContext _) => PopScope(
      canPop: false,
      child: _SendAnimation(key: key, name: name, technician: technician),
    ),
  );

  try {
    final bool ok = await task;
    if (ok) await key.currentState?.succeed();
    if (navigator.mounted) navigator.pop();
    return ok;
  } catch (_) {
    if (navigator.mounted) navigator.pop();
    rethrow;
  }
}

class _SendAnimation extends StatefulWidget {
  const _SendAnimation({super.key, required this.name, this.technician});

  final String name;
  final Technician? technician;

  @override
  State<_SendAnimation> createState() => _SendAnimationState();
}

/// The decoration clock for the card's backdrop: held still.
final ValueNotifier<Duration> _stillCard = ValueNotifier<Duration>(
  const Duration(milliseconds: 1600),
);

class _SendAnimationState extends State<_SendAnimation>
    with TickerProviderStateMixin {
  /// The flight: lift, curve up, vanish into the photo.
  late final AnimationController _fly;

  /// Turns the waiting ring once the envelope has landed and the server has
  /// not answered yet. A loop, on purpose: it is a waiting indicator.
  late final AnimationController _wait;

  /// The ripple and the tick, once the request has gone through.
  late final AnimationController _success;

  bool _done = false;

  @override
  void initState() {
    super.initState();
    _fly = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    )..addStatusListener(_onFlight);
    _wait = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _success = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      // Landed already; the wait for the server is unchanged, so the tick
      // still never comes early.
      _fly.value = 1;
    } else if (_fly.value == 0 && !_fly.isAnimating) {
      _fly.forward();
    }
  }

  void _onFlight(AnimationStatus status) {
    if (status == AnimationStatus.completed &&
        !_done &&
        mounted &&
        !AppMotion.reduced(context)) {
      _wait.repeat();
    }
  }

  /// Waits for the flight to land, shows the tick, and holds it briefly so
  /// it can be read before the card closes.
  Future<void> succeed() async {
    if (_fly.isAnimating) await _fly.forward().orCancel.catchError((_) {});
    if (!mounted) return;
    _wait.stop();
    setState(() => _done = true);
    if (AppMotion.reduced(context)) {
      _success.value = 1;
    } else {
      await _success.forward().orCancel.catchError((_) {});
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }

  @override
  void dispose() {
    _fly.dispose();
    _wait.dispose();
    _success.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String first = widget.name.trim().isEmpty
        ? 'your technician'
        : widget.name.trim();

    return Center(
      child: Material(
        color: AppColors.navy,
        elevation: 12,
        shadowColor: AppColors.navy,
        borderRadius: BorderRadius.circular(AppSizes.sheetRadius + 4),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 280,
          child: Stack(
            children: <Widget>[
              Positioned.fill(child: MatchingBackdrop(clock: _stillCard)),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.lg,
                  AppSizes.lg,
                  AppSizes.lg,
                  AppSizes.xl,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SizedBox(
                      height: 228,
                      width: double.infinity,
                      child: ExcludeSemantics(
                        child: AnimatedBuilder(
                          animation: Listenable.merge(<Listenable>[
                            _fly,
                            _wait,
                            _success,
                          ]),
                          builder: (BuildContext _, Widget? _) => _Flight(
                            fly: _fly.value,
                            wait: _wait.value,
                            waiting: _fly.isCompleted && !_done,
                            success: _done ? _success.value : 0,
                            technician: widget.technician,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSizes.sm),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      transitionBuilder: (Widget child, Animation<double> a) =>
                          FadeTransition(
                            opacity: a,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.3),
                                end: Offset.zero,
                              ).animate(a),
                              child: child,
                            ),
                          ),
                      child: Column(
                        key: ValueKey<bool>(_done),
                        children: <Widget>[
                          Text(
                            _done
                                ? 'Request sent to $first'
                                : 'Sending your request...',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: AppSizes.xs),
                          Text(
                            _done
                                ? 'They still need to accept before it is '
                                      'confirmed.'
                                : 'Passing it to $first now.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 13,
                              height: 1.4,
                              color: Colors.white.withValues(alpha: 0.72),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One frame of the flight, a pure function of its four values.
///
/// | fly        | what happens                                          |
/// |------------|-------------------------------------------------------|
/// | 0.00-0.14  | the envelope lifts off the bottom, with a little wobble |
/// | 0.12-0.90  | it flies an S-curve up to the photo, tilting into it, |
/// |            | the dashed route drawing behind it                    |
/// | 0.80-0.96  | it shrinks into the photo and is gone                 |
class _Flight extends StatelessWidget {
  const _Flight({
    required this.fly,
    required this.wait,
    required this.waiting,
    required this.success,
    required this.technician,
  });

  final double fly;
  final double wait;
  final bool waiting;
  final double success;
  final Technician? technician;

  static const double _avatar = 68;
  static const double _envelope = 88;

  double _phase(double start, double end, [Curve curve = Curves.easeInOut]) =>
      curve.transform(((fly - start) / (end - start)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double w = box.maxWidth;
        final double h = box.maxHeight;
        final Offset target = Offset(w / 2, _avatar / 2 + 8);
        final Offset start = Offset(w / 2, h - _envelope * 0.33 - 6);

        // An S-curve: out to the left, back across to the right, up into
        // the photo.
        Offset at(double u) {
          final Offset p0 = start;
          final Offset p1 = Offset(w * 0.08, h * 0.72);
          final Offset p2 = Offset(w * 0.92, h * 0.42);
          final Offset p3 = target;
          final double v = 1 - u;
          return p0 * (v * v * v) +
              p1 * (3 * v * v * u) +
              p2 * (3 * v * u * u) +
              p3 * (u * u * u);
        }

        final double lift = _phase(0, 0.14, Curves.easeOutCubic);
        final double u = _phase(0.12, 0.90, Curves.easeInOutCubic);
        final double vanish = _phase(0.80, 0.96, Curves.easeInCubic);

        final Offset here = at(u) + Offset(0, (1 - lift) * 14);
        final Offset ahead = at(math.min(1, u + 0.02));
        final Offset behind = at(math.max(0, u - 0.02));
        final double tilt = u <= 0 || u >= 1
            ? math.sin(lift * math.pi) * 0.08
            : ((math.atan2(ahead.dy - behind.dy, ahead.dx - behind.dx) +
                          math.pi / 2) *
                      0.35)
                  .clamp(-0.45, 0.45);
        final double scale = (0.88 + 0.12 * lift) * (1 - 0.75 * vanish);

        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            // The route drawn behind the envelope.
            Positioned.fill(
              child: CustomPaint(
                painter: _TrailPainter(at: at, upTo: u, fade: 1 - success),
              ),
            ),

            // The technician, waiting at the end of the route.
            Positioned(
              left: target.dx - _avatar / 2,
              top: target.dy - _avatar / 2,
              width: _avatar,
              height: _avatar,
              child: _Recipient(
                technician: technician,
                size: _avatar,
                catchPulse: _phase(0.86, 1),
                waiting: waiting,
                wait: wait,
                success: success,
              ),
            ),

            // The envelope.
            if (vanish < 1)
              Positioned(
                left: here.dx - _envelope / 2,
                top: here.dy - _envelope * 0.33,
                width: _envelope,
                height: _envelope * 0.66,
                child: Opacity(
                  opacity: 1 - vanish,
                  child: Transform.rotate(
                    angle: tilt,
                    child: Transform.scale(
                      scale: scale,
                      child: const SealedEnvelope(width: _envelope),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The photo the envelope flies to: it bumps as the envelope lands, turns a
/// cyan ring while the server answers, then ripples and takes a tick.
class _Recipient extends StatelessWidget {
  const _Recipient({
    required this.technician,
    required this.size,
    required this.catchPulse,
    required this.waiting,
    required this.wait,
    required this.success,
  });

  final Technician? technician;
  final double size;
  final double catchPulse;
  final bool waiting;
  final double wait;
  final double success;

  @override
  Widget build(BuildContext context) {
    final double bump = math.sin(catchPulse * math.pi) * 0.10;
    final double tick = Curves.easeOutBack.transform(
      (success / 0.7).clamp(0.0, 1.0),
    );
    final Technician? who = technician;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: <Widget>[
        // A soft light behind the photo.
        Positioned(
          left: -size * 0.45,
          top: -size * 0.45,
          width: size * 1.9,
          height: size * 1.9,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[
                  AppColors.cyan.withValues(alpha: 0.28),
                  AppColors.cyan.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
        // The ripple once it has gone through.
        if (success > 0)
          Transform.scale(
            scale: 1 + 0.75 * success,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.cyan.withValues(alpha: 0.7 * (1 - success)),
                  width: 2.5,
                ),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        // The waiting ring, turning.
        if (waiting)
          Positioned(
            left: -7,
            top: -7,
            width: size + 14,
            height: size + 14,
            child: Transform.rotate(
              angle: wait * 2 * math.pi,
              child: const CustomPaint(painter: _WaitArcPainter()),
            ),
          ),
        Transform.scale(
          scale: 1 + bump,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: AppColors.cyan.withValues(alpha: 0.45),
                  blurRadius: 16,
                ),
              ],
            ),
            child: who != null
                ? TechnicianAvatar(technician: who, size: size - 6)
                : Container(
                    width: size - 6,
                    height: size - 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: <Color>[AppColors.primary, AppColors.secondary],
                      ),
                    ),
                    child: const Icon(
                      Icons.engineering_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
          ),
        ),
        // The tick.
        if (success > 0)
          Positioned(
            right: -4,
            bottom: -4,
            width: size * 0.40,
            height: size * 0.40,
            child: Transform.scale(
              scale: tick,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: <Color>[AppColors.secondary, AppColors.cyan],
                  ),
                  border: Border.all(color: AppColors.navy, width: 2.5),
                ),
                child: Icon(
                  Icons.check_rounded,
                  size: size * 0.26,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _WaitArcPainter extends CustomPainter {
  const _WaitArcPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    const double sweep = math.pi * 0.7;
    canvas.drawArc(
      rect.deflate(1.5),
      0,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          endAngle: sweep,
          colors: <Color>[AppColors.cyan.withValues(alpha: 0), AppColors.cyan],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_WaitArcPainter old) => false;
}

/// SUGO's dashed route behind the envelope, with a soft glow under it.
class _TrailPainter extends CustomPainter {
  _TrailPainter({required this.at, required this.upTo, required this.fade});

  final Offset Function(double u) at;
  final double upTo;
  final double fade;

  @override
  void paint(Canvas canvas, Size size) {
    if (upTo <= 0 || fade <= 0) return;
    const int samples = 90;
    final Path path = Path()..moveTo(at(0).dx, at(0).dy);
    for (int i = 1; i <= samples; i++) {
      final Offset p = at(upTo * i / samples);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = AppColors.cyan.withValues(alpha: 0.16 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Dashes along the same path.
    final Paint dash = Paint()
      ..color = AppColors.cyan.withValues(alpha: 0.75 * fade)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    double run = 0;
    Offset previous = at(0);
    for (int i = 1; i <= samples * 2; i++) {
      final Offset p = at(upTo * i / (samples * 2));
      final double length = (p - previous).distance;
      if ((run % 12) < 6 && length > 0) canvas.drawLine(previous, p, dash);
      run += length;
      previous = p;
    }
  }

  @override
  bool shouldRepaint(_TrailPainter old) => old.upTo != upTo || old.fade != fade;
}
