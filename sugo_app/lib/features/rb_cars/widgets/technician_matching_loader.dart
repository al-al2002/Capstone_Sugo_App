import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';

/// What the matching work has actually reached, as far as the phone can see.
enum MatchingPhase {
  /// Photos uploading, the job being saved. Nothing has been matched yet.
  saving,

  /// The job is saved and the matcher is running on the server.
  matching,

  /// The result is back. Everything on the list is really done.
  done,
}

/// The clock and milestones of one matching run, shared across the screens
/// that show it.
///
/// Posting a job shows the loader twice in a row - once while the job saves
/// and the matcher runs, once while the review screen reads the result back.
/// They are different widgets. Sharing this object is what makes them one
/// continuous animation instead of one that restarts halfway: the second
/// picks up the first one's elapsed time and milestones.
class MatchingSession {
  /// Time on screen so far, advanced by whichever loader is showing.
  Duration elapsed = Duration.zero;

  /// When the matcher started - the first step's tick.
  Duration? matchingSince;

  /// When the result was observed back - the moment every step is done.
  Duration? doneAt;

  /// The bar's value at [doneAt], so it completes from where it was.
  double progressAtDone = 0;
}

/// The frame both navy matching screens share - the letter to the
/// technicians (`RequestSendIntro`) and this analysis screen - so the
/// letter's closing burst lands exactly where this screen's hub appears.
abstract final class MatchingStageLayout {
  /// Room under the status bar for the transparent app bar's back arrow.
  static const double top = 44;

  /// The picture's height for [available] height: 40%, from 210 to 330.
  static double heroHeight(double available) =>
      available.isFinite ? (available * 0.40).clamp(210.0, 330.0) : 330.0;
}

/// The context-aware analysis screen, shown while RB-CARS matches a request.
///
/// ## What is on it (redesigned 2026-11-23)
///
/// A hub: the SUGO emblem in the middle, and round it the four things the
/// matcher weighs - **Weather, Traffic, Rules, Technicians** - each joined to
/// the emblem by SUGO's dashed route line. Under it, "Analyzing your
/// request...", the same pipeline as a checklist on a frosted card, and a
/// progress bar. The hub and the list are one picture of the same state: the
/// step being worked on has its line marching and a light running along it,
/// and its row is highlighted; a finished step's line turns solid and its
/// circle gets the cyan tick the letter animation gave the technicians.
///
/// It replaced a single emblem with pulsing rings (2026-09). The user asked
/// for it to be "beautiful, and fit SUGO and the letter animation": it shares
/// the letter's navy ground, its twinkling backdrop, its ticks and its dashed
/// route, and its hub sits exactly where the letter bursts.
///
/// ## Which ticks are real
///
/// A filled cyan tick means *done, and observed*:
///
/// * "Understanding your request" ticks when the job has actually been saved
///   (`JobPostingProvider.requestSaved`), not on a timer.
/// * The four server steps tick together, in a quick cascade, when the
///   matcher's result arrives - the one moment the phone knows they are done.
///
/// While the matcher runs, the server reports nothing until it finishes: it
/// is a single request. So the highlight moves down the server steps on a
/// ~0.9 s pace, and a step it has moved past gets an *outlined* tick - "we
/// have moved on", not "confirmed". At a glance the list reads like the
/// design; up close it never claims a completion it did not see.
///
/// The bar works the same way: paced by time while waiting, easing toward
/// 90% and never reaching the end on its own, then completing when the result
/// is back. It carries no percentage, because a number would be a claim about
/// work the phone cannot measure.
///
/// ## Not artificial
///
/// The screen is up exactly as long as the real work takes, plus a ~0.7 s
/// finish (the cascade and the bar filling) so a fast result does not flash.
/// That is the brief's "short polished transition", not a wait.
class TechnicianMatchingLoader extends StatefulWidget {
  const TechnicianMatchingLoader({
    super.key,
    this.phase = MatchingPhase.matching,
    this.session,
    this.onFinished,
    this.patienceThreshold = const Duration(seconds: 12),
  });

  final MatchingPhase phase;

  /// Shared with a loader shown before this one, for continuity. A private
  /// session is made when null.
  final MatchingSession? session;

  /// Called once, when [phase] is done and the finishing cascade has played.
  final VoidCallback? onFinished;

  /// After this long, a line says the wait is longer than usual - so a slow
  /// network reads as slow, not as broken.
  final Duration patienceThreshold;

  /// How long the finish takes: the last tick plus the bar filling.
  static const Duration finishHold = Duration(milliseconds: 720);

  @override
  State<TechnicianMatchingLoader> createState() =>
      _TechnicianMatchingLoaderState();
}

/// The pipeline, in the brief's words and the engine's order.
const List<String> _steps = <String>[
  'Understanding your request',
  'Checking current weather',
  'Analyzing traffic conditions',
  'Applying matching rules',
  'Finding suitable technicians',
];

/// Each step's icon - on its row, and (steps 1-4) on its circle in the hub.
const List<IconData> _stepIcons = <IconData>[
  Icons.description_rounded,
  Icons.cloud_rounded,
  Icons.traffic_rounded,
  Icons.tune_rounded,
  Icons.engineering_rounded,
];

/// The hub's four circles: steps 1-4, clockwise from the top left.
const List<String> _hubLabels = <String>[
  'Weather',
  'Traffic',
  'Rules',
  'Technicians',
];
const List<double> _hubAngles = <double>[
  -0.75 * math.pi,
  -0.25 * math.pi,
  0.25 * math.pi,
  0.75 * math.pi,
];

/// How fast the highlight walks the server steps while the matcher runs.
const Duration _stepPace = Duration(milliseconds: 900);

/// Gap between ticks in the finishing cascade.
const Duration _cascadeGap = Duration(milliseconds: 110);

/// How long the bar takes to fill once the result is back.
const Duration _fillDuration = Duration(milliseconds: 420);

enum _StepState { confirmed, passed, active, pending }

class _TechnicianMatchingLoaderState extends State<TechnicianMatchingLoader>
    with SingleTickerProviderStateMixin {
  late final MatchingSession _session = widget.session ?? MatchingSession();
  late final Duration _offset = _session.elapsed;
  late final Ticker _ticker;

  /// Every frame - drives the hub and the bar, and nothing else.
  late final ValueNotifier<Duration> _clock = ValueNotifier<Duration>(
    _session.elapsed,
  );

  /// Only when a step actually changes state - the list does not rebuild at
  /// 60 fps for a tick that happens five times.
  late final ValueNotifier<List<_StepState>> _states =
      ValueNotifier<List<_StepState>>(_computeStates(_session.elapsed));

  final ValueNotifier<bool> _slow = ValueNotifier<bool>(false);
  bool _finishedCalled = false;

  /// A clock that never moves, for the decoration under "remove animations".
  ///
  /// The real clock keeps running either way: it drives the step ticks, the
  /// progress bar and the hand-over to the results, which carry information.
  /// Only the hub's motion and the backdrop are decoration, so only they hold
  /// still - posed after their entrance, with the lines clearly drawn.
  final ValueNotifier<Duration> _still = ValueNotifier<Duration>(
    const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    _markPhase(_session.elapsed);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(TechnicianMatchingLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase) _markPhase(_session.elapsed);
  }

  /// Records a milestone the first time its phase is seen.
  void _markPhase(Duration now) {
    if (widget.phase != MatchingPhase.saving) {
      _session.matchingSince ??= now;
    }
    if (widget.phase == MatchingPhase.done && _session.doneAt == null) {
      _session.progressAtDone = _waitingProgress(now);
      _session.doneAt = now;
    }
  }

  void _onTick(Duration sinceStart) {
    final Duration now = _offset + sinceStart;
    _session.elapsed = now;
    _clock.value = now;

    final List<_StepState> next = _computeStates(now);
    if (!_sameStates(next, _states.value)) _states.value = next;

    _slow.value =
        widget.phase != MatchingPhase.done && now >= widget.patienceThreshold;

    final Duration? doneAt = _session.doneAt;
    if (!_finishedCalled &&
        widget.phase == MatchingPhase.done &&
        doneAt != null &&
        now - doneAt >= TechnicianMatchingLoader.finishHold) {
      _finishedCalled = true;
      widget.onFinished?.call();
    }
  }

  List<_StepState> _computeStates(Duration now) {
    final Duration? since = _session.matchingSince;
    final Duration? doneAt = _session.doneAt;

    return List<_StepState>.generate(_steps.length, (int i) {
      if (i == 0) {
        return since == null ? _StepState.active : _StepState.confirmed;
      }
      if (doneAt != null && now >= doneAt + _cascadeGap * (i - 1)) {
        return _StepState.confirmed;
      }
      if (since == null) return _StepState.pending;

      final int active = math.min(
        _steps.length - 1,
        1 + (now - since).inMilliseconds ~/ _stepPace.inMilliseconds,
      );
      if (i < active) return _StepState.passed;
      if (i == active) return _StepState.active;
      return _StepState.pending;
    });
  }

  static bool _sameStates(List<_StepState> a, List<_StepState> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Paced by time: eases toward 90% and never gets there on its own.
  static double _waitingProgress(Duration now) {
    final double seconds = now.inMilliseconds / 1000;
    return 0.06 + 0.84 * (1 - math.exp(-seconds / 3.2));
  }

  double _progress(Duration now) {
    final Duration? doneAt = _session.doneAt;
    if (doneAt == null) return _waitingProgress(now);
    final double t =
        ((now - doneAt).inMilliseconds / _fillDuration.inMilliseconds).clamp(
          0.0,
          1.0,
        );
    final double eased = Curves.easeOutCubic.transform(t);
    return _session.progressAtDone + (1 - _session.progressAtDone) * eased;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    _states.dispose();
    _slow.dispose();
    _still.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Takes every pixel it is offered. A Scaffold body hands down *loose*
    // constraints, and without this the whole screen shrank to the width of
    // its widest line and sat against the left edge - glow and all - while
    // looking perfectly centred in a test pane that happened to be tight.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints outer) => SizedBox(
        width: outer.hasBoundedWidth ? outer.maxWidth : null,
        height: outer.hasBoundedHeight ? outer.maxHeight : null,
        child: _screen(),
      ),
    );
  }

  Widget _screen() {
    final ValueNotifier<Duration> deco = AppMotion.reduced(context)
        ? _still
        : _clock;
    final TextStyle subtle = TextStyle(
      fontFamily: AppTextStyles.fontFamily,
      fontSize: 13,
      height: 1.4,
      color: Colors.white.withValues(alpha: 0.72),
    );

    return Stack(
      children: <Widget>[
        Positioned.fill(child: MatchingBackdrop(clock: deco)),
        SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) {
              final double hero = MatchingStageLayout.heroHeight(box.maxHeight);

              return SingleChildScrollView(
                child: ConstrainedBox(
                  // Full width, so the column centres on the screen rather
                  // than on its own content.
                  constraints: BoxConstraints(
                    minWidth: box.hasBoundedWidth ? box.maxWidth : 0,
                  ),
                  child: Column(
                    children: <Widget>[
                      const SizedBox(height: MatchingStageLayout.top),
                      SizedBox(
                        width: double.infinity,
                        height: hero,
                        child: ExcludeSemantics(
                          child: ValueListenableBuilder<List<_StepState>>(
                            valueListenable: _states,
                            builder: (_, List<_StepState> states, _) =>
                                _Hub(clock: deco, states: states),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSizes.screenPadding + AppSizes.sm,
                          AppSizes.md,
                          AppSizes.screenPadding + AppSizes.sm,
                          AppSizes.xl,
                        ),
                        child: Column(
                          children: <Widget>[
                            const Text(
                              'Analyzing your request...',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: AppSizes.sm),
                            Text(
                              'SUGO is checking the right technicians for '
                              'your needs.',
                              textAlign: TextAlign.center,
                              style: subtle,
                            ),
                            const SizedBox(height: AppSizes.lg),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 360),
                              child: _GlassCard(
                                child: ValueListenableBuilder<List<_StepState>>(
                                  valueListenable: _states,
                                  builder: (_, List<_StepState> states, _) =>
                                      _StepList(states: states),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSizes.lg),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 360),
                              child: ValueListenableBuilder<Duration>(
                                valueListenable: _clock,
                                builder: (_, Duration now, _) => _ProgressBar(
                                  value: _progress(now),
                                  sheen: deco.value.inMilliseconds / 1000,
                                  done: _session.doneAt != null,
                                ),
                              ),
                            ),
                            ValueListenableBuilder<bool>(
                              valueListenable: _slow,
                              builder: (_, bool slow, _) => AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child: slow
                                    ? Padding(
                                        padding: const EdgeInsets.only(
                                          top: AppSizes.lg,
                                        ),
                                        child: Text(
                                          'This is taking longer than usual. '
                                          'We are still looking - nothing '
                                          'has failed.',
                                          textAlign: TextAlign.center,
                                          style: subtle,
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------- backdrop

/// The navy ground both matching screens stand on: lit from behind the hub,
/// two soft washes of cyan and blue, and faint dots that twinkle in place.
///
/// The dots only change brightness, never position, so when the letter
/// screen fades into the analysis screen the two grounds line up exactly.
class MatchingBackdrop extends StatelessWidget {
  const MatchingBackdrop({super.key, required this.clock});

  /// Time, for the twinkle. A clock that does not move holds it still.
  final ValueListenable<Duration> clock;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _BackdropPainter(clock),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.clock) : super(repaint: clock);

  final ValueListenable<Duration> clock;

  /// (x, y, radius, phase): fixed, so every frame and both screens agree.
  static final List<(double, double, double, double)> _dots = () {
    final math.Random random = math.Random(7);
    return List<(double, double, double, double)>.generate(
      44,
      (_) => (
        random.nextDouble(),
        random.nextDouble(),
        0.6 + random.nextDouble() * 1.3,
        random.nextDouble() * math.pi * 2,
      ),
    );
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.42),
          radius: 1.15,
          colors: <Color>[Color(0xFF0B3C7A), AppColors.navy],
        ).createShader(rect),
    );

    void wash(Offset centre, double radius, Color colour) {
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[colour, colour.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: centre, radius: radius)),
      );
    }

    wash(
      Offset(size.width * 0.08, size.height * 0.06),
      size.width * 0.6,
      AppColors.cyan.withValues(alpha: 0.08),
    );
    wash(
      Offset(size.width * 0.98, size.height * 0.88),
      size.width * 0.75,
      AppColors.secondary.withValues(alpha: 0.12),
    );

    final double t = clock.value.inMilliseconds / 1000;
    final Paint dot = Paint();
    for (final (double x, double y, double r, double phase) in _dots) {
      final double twinkle = 0.5 + 0.5 * math.sin(t * 1.4 + phase);
      dot.color = Colors.white.withValues(
        alpha: (0.05 + 0.20 * twinkle) * (r / 1.9),
      );
      canvas.drawCircle(Offset(x * size.width, y * size.height), r, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) =>
      oldDelegate.clock != clock;
}

// ------------------------------------------------------------------- hub

/// The emblem and the four steps round it, joined by SUGO's dashed route.
///
/// Opens with a little entrance - the emblem springs in and a ring ripples
/// off it, the four circles fly out along their lines - which picks up where
/// the letter's burst left off. The circles and emblem rebuild each frame
/// (a handful of small widgets); the rings, lines and lights are one
/// painter repainting from the clock.
class _Hub extends StatelessWidget {
  const _Hub({required this.clock, required this.states});

  final ValueListenable<Duration> clock;
  final List<_StepState> states;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final Size size = Size(box.maxWidth, box.maxHeight);
        final double m = math.min(size.width, size.height);
        final _HubGeometry g = _HubGeometry(
          centre: size.center(Offset.zero),
          disc: m * 0.32,
          orbit: math.min(size.width * 0.36, size.height * 0.41),
          satellite: (m * 0.16).clamp(38.0, 54.0),
        );

        final Widget emblem = _EmblemDisc(size: g.disc);

        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned.fill(
              child: CustomPaint(painter: _HubPainter(clock, states, g)),
            ),
            ValueListenableBuilder<Duration>(
              valueListenable: clock,
              child: emblem,
              builder: (_, Duration now, Widget? child) {
                final double t = now.inMilliseconds / 1000;
                final double pop = Curves.easeOutBack.transform(
                  (t / 0.7).clamp(0.0, 1.0),
                );
                return Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Positioned(
                      left: g.centre.dx - g.disc / 2,
                      top:
                          g.centre.dy -
                          g.disc / 2 +
                          math.sin(t * 1.6) * m * 0.01,
                      width: g.disc,
                      height: g.disc,
                      child: Transform.scale(
                        scale: 0.55 + 0.45 * pop,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: <Widget>[
                            Positioned.fill(child: child!),
                            // "Understanding your request" ticks on the hub.
                            Positioned(
                              right: g.disc * 0.02,
                              bottom: g.disc * 0.02,
                              width: g.disc * 0.28,
                              height: g.disc * 0.28,
                              child: _Badge(state: states[0]),
                            ),
                          ],
                        ),
                      ),
                    ),
                    for (int i = 0; i < _hubAngles.length; i++)
                      _satelliteAt(i, g, t),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _satelliteAt(int i, _HubGeometry g, double t) {
    final double out = g.flyOut(t, i);
    final Offset at =
        g.centre +
        Offset(math.cos(_hubAngles[i]), math.sin(_hubAngles[i])) *
            (g.orbit * out);
    final bool above = math.sin(_hubAngles[i]) < 0;
    const double labelWidth = 96;
    final double nameRoom = above
        ? _Satellite.labelHeight + _Satellite.labelGap
        : 0;

    return Positioned(
      left: at.dx - labelWidth / 2,
      top: at.dy - g.satellite / 2 - nameRoom,
      width: labelWidth,
      child: Opacity(
        opacity: out.clamp(0.0, 1.0),
        child: _Satellite(
          size: g.satellite,
          icon: _stepIcons[i + 1],
          label: _hubLabels[i],
          state: states[i + 1],
          t: t,
          labelAbove: above,
          labelOpacity: ((g.flyProgress(t, i) - 0.75) / 0.25).clamp(0.0, 1.0),
        ),
      ),
    );
  }
}

class _HubGeometry {
  const _HubGeometry({
    required this.centre,
    required this.disc,
    required this.orbit,
    required this.satellite,
  });

  final Offset centre;

  /// The emblem disc's diameter.
  final double disc;

  /// Distance from the centre to each circle's centre.
  final double orbit;

  /// Each circle's diameter.
  final double satellite;

  /// How far circle [i] has flown out (0 at the centre, 1 in place, with a
  /// slight overshoot), staggered so they leave one after another.
  double flyOut(double t, int i) =>
      Curves.easeOutBack.transform(flyProgress(t, i));

  /// The same, linear and without the overshoot: 0..1 through the flight.
  double flyProgress(double t, int i) =>
      ((t - 0.12 - 0.08 * i) / 0.6).clamp(0.0, 1.0);
}

/// The SUGO emblem in its glowing disc.
class _EmblemDisc extends StatelessWidget {
  const _EmblemDisc({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.cyan.withValues(alpha: 0.65),
          width: 2,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.cyan.withValues(alpha: 0.40),
            blurRadius: size * 0.30,
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          AppAssets.brandEmblem,
          fit: BoxFit.cover,
          excludeFromSemantics: true,
          // The disc's own navy is close enough to the image's that a missing
          // file still reads as an emblem.
          errorBuilder: (BuildContext _, Object _, StackTrace? _) =>
              const ColoredBox(color: AppColors.primary),
        ),
      ),
    );
  }
}

/// One of the four steps round the hub: a circle with its icon, its name on
/// the outside (above for the top two, below for the bottom two, so no name
/// sits across a line), and a tick once done.
class _Satellite extends StatelessWidget {
  const _Satellite({
    required this.size,
    required this.icon,
    required this.label,
    required this.state,
    required this.t,
    required this.labelAbove,
    required this.labelOpacity,
  });

  final double size;
  final IconData icon;
  final String label;
  final _StepState state;
  final double t;
  final bool labelAbove;

  /// The name fades in once its circle has landed, so names never slide
  /// across the emblem on the way out.
  final double labelOpacity;

  /// A fixed box for the name, so a circle can be placed exactly whichever
  /// side its name is on.
  static const double labelHeight = 16;
  static const double labelGap = 6;

  @override
  Widget build(BuildContext context) {
    final bool active = state == _StepState.active;
    // A radar ping off the circle being worked on.
    final double ping = active ? (t * 0.85) % 1.0 : 0;

    final (
      BoxDecoration decoration,
      Color iconColour,
      double labelAlpha,
    ) = switch (state) {
      _StepState.pending => (
        BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.06),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.16),
            width: 1.4,
          ),
        ),
        Colors.white.withValues(alpha: 0.42),
        0.45,
      ),
      _StepState.active => (
        BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF0C3F80),
          border: Border.all(color: AppColors.cyan, width: 2),
          // Steady: the ping ring carries the motion. A glow that moved
          // every frame would keep restarting the AnimatedContainer.
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppColors.cyan.withValues(alpha: 0.40),
              blurRadius: size * 0.40,
            ),
          ],
        ),
        AppColors.cyan,
        1.0,
      ),
      _StepState.passed => (
        BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.08),
          border: Border.all(
            color: AppColors.cyan.withValues(alpha: 0.55),
            width: 1.6,
          ),
        ),
        AppColors.cyan.withValues(alpha: 0.85),
        0.78,
      ),
      _StepState.confirmed => (
        BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[AppColors.secondary, AppColors.cyan],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.35),
            width: 1.4,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppColors.cyan.withValues(alpha: 0.35),
              blurRadius: size * 0.30,
            ),
          ],
        ),
        Colors.white,
        0.92,
      ),
    };

    final Widget name = SizedBox(
      height: _Satellite.labelHeight,
      child: Opacity(
        opacity: labelOpacity,
        child: Center(
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.15,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                color: Colors.white.withValues(alpha: labelAlpha),
              ),
            ),
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (labelAbove) ...<Widget>[
          name,
          const SizedBox(height: _Satellite.labelGap),
        ],
        SizedBox.square(
          dimension: size,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: <Widget>[
              if (active)
                Transform.scale(
                  scale: 1 + 0.6 * ping,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.cyan.withValues(
                          alpha: 0.55 * (1 - ping),
                        ),
                        width: 2,
                      ),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                decoration: decoration,
                child: Center(
                  child: Icon(icon, size: size * 0.46, color: iconColour),
                ),
              ),
              Positioned(
                right: -size * 0.06,
                bottom: -size * 0.06,
                width: size * 0.40,
                height: size * 0.40,
                child: _Badge(state: state),
              ),
            ],
          ),
        ),
        if (!labelAbove) ...<Widget>[
          const SizedBox(height: _Satellite.labelGap),
          name,
        ],
      ],
    );
  }
}

/// The tick on a circle: outlined for "moved past", filled cyan for "done,
/// and observed" - the letter animation's tick. Pops in when it changes.
class _Badge extends StatelessWidget {
  const _Badge({required this.state});

  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final Widget? badge = switch (state) {
      _StepState.confirmed => Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.cyan,
          border: Border.all(color: AppColors.navy, width: 2),
        ),
        child: const FittedBox(
          child: Padding(
            padding: EdgeInsets.all(3),
            child: Icon(Icons.check_rounded, color: Colors.white),
          ),
        ),
      ),
      _StepState.passed => Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.navy,
          border: Border.all(
            color: AppColors.cyan.withValues(alpha: 0.7),
            width: 1.4,
          ),
        ),
        child: FittedBox(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              Icons.check_rounded,
              color: AppColors.cyan.withValues(alpha: 0.85),
            ),
          ),
        ),
      ),
      _ => null,
    };
    if (badge == null) return const SizedBox.shrink();

    return TweenAnimationBuilder<double>(
      key: ValueKey<_StepState>(state),
      tween: Tween<double>(begin: 0, end: 1),
      duration: AppMotion.reduced(context)
          ? Duration.zero
          : const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      builder: (BuildContext _, double v, Widget? child) =>
          Transform.scale(scale: v, child: child),
      child: badge,
    );
  }
}

class _HubPainter extends CustomPainter {
  _HubPainter(this.clock, this.states, this.g) : super(repaint: clock);

  final ValueListenable<Duration> clock;
  final List<_StepState> states;
  final _HubGeometry g;

  /// One ring every this long; three are in flight at once.
  static const double _ringPeriod = 2.6;

  @override
  void paint(Canvas canvas, Size size) {
    final double t = clock.value.inMilliseconds / 1000;
    final Offset c = g.centre;
    final double r = g.disc / 2;
    final double entrance = Curves.easeOutCubic.transform(
      (t / 0.9).clamp(0.0, 1.0),
    );

    // Glow behind everything.
    final double glow = g.orbit * 1.15;
    canvas.drawCircle(
      c,
      glow,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            AppColors.cyan.withValues(alpha: 0.20),
            AppColors.secondary.withValues(alpha: 0.07),
            Colors.transparent,
          ],
          stops: const <double>[0.15, 0.55, 1],
        ).createShader(Rect.fromCircle(center: c, radius: glow)),
    );

    // The entrance ripple, continuing the letter's burst.
    if (entrance < 1) {
      canvas.drawCircle(
        c,
        r * (1 + 1.8 * entrance),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = AppColors.cyan.withValues(alpha: 0.55 * (1 - entrance)),
      );
    }

    // Pulses travelling out from the emblem, fading as they go.
    for (int i = 0; i < 3; i++) {
      final double phase = ((t / _ringPeriod) + i / 3) % 1.0;
      canvas.drawCircle(
        c,
        r + (g.orbit - r) * phase,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = AppColors.cyan.withValues(
            alpha: 0.26 * (1 - phase) * entrance,
          ),
      );
    }

    // The orbit, as a dashed ring turning slowly.
    const int dashes = 56;
    const double step = 2 * math.pi / dashes;
    final Rect orbitRect = Rect.fromCircle(center: c, radius: g.orbit);
    final Paint orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.10 * entrance);
    for (int k = 0; k < dashes; k++) {
      canvas.drawArc(
        orbitRect,
        k * step + t * 0.10,
        step * 0.42,
        false,
        orbitPaint,
      );
    }

    // The lines from the emblem to each step.
    for (int i = 0; i < _hubAngles.length; i++) {
      _line(canvas, i, t);
    }

    // A thin track round the emblem, and an arc sweeping it - "scanning".
    final double scan = r + 8;
    canvas.drawCircle(
      c,
      scan,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.10 * entrance),
    );
    // The canvas turns, not the gradient: a sweep gradient is defined on
    // 0..2π, so an arc drawn across the 0 angle would lose its bright head
    // for a moment on every lap.
    const double sweep = math.pi * 0.55;
    final Rect scanRect = Rect.fromCircle(center: Offset.zero, radius: scan);
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..rotate((t * 1.9) % (2 * math.pi))
      ..drawArc(
        scanRect,
        0,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            endAngle: sweep,
            colors: <Color>[
              AppColors.cyan.withValues(alpha: 0),
              AppColors.cyan.withValues(alpha: entrance),
            ],
          ).createShader(scanRect),
      )
      ..restore();
  }

  /// The route from the emblem to step [i], drawn as far as the circle has
  /// flown out, in the look of its state.
  void _line(Canvas canvas, int i, double t) {
    final Offset dir = Offset(math.cos(_hubAngles[i]), math.sin(_hubAngles[i]));
    final double out = g.flyOut(t, i).clamp(0.0, 1.0);
    final double r0 = g.disc / 2 + 12;
    final double r1 = (g.orbit - g.satellite / 2 - 6) * out;
    if (r1 <= r0) return;
    final Offset a = g.centre + dir * r0;
    final Offset b = g.centre + dir * r1;

    switch (states[i + 1]) {
      case _StepState.pending:
        _dashed(canvas, a, b, _stroke(Colors.white.withValues(alpha: 0.14)));
      case _StepState.passed:
        _dashed(canvas, a, b, _stroke(AppColors.cyan.withValues(alpha: 0.45)));
      case _StepState.active:
        // Marching outward, with a light running along it.
        _dashed(
          canvas,
          a,
          b,
          _stroke(AppColors.cyan.withValues(alpha: 0.55), width: 2),
          shift: -t * 26,
        );
        final double f = (t * 0.9) % 1.0;
        final Offset light = Offset.lerp(a, b, f)!;
        final double fade = math.sin(f * math.pi);
        canvas
          ..drawCircle(
            light,
            7,
            Paint()
              ..color = AppColors.cyan.withValues(alpha: 0.45 * fade)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
          )
          ..drawCircle(
            light,
            2.6,
            Paint()..color = Colors.white.withValues(alpha: fade),
          );
      case _StepState.confirmed:
        canvas
          ..drawLine(
            a,
            b,
            Paint()
              ..color = AppColors.cyan.withValues(alpha: 0.35)
              ..strokeWidth = 6
              ..strokeCap = StrokeCap.round
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
          )
          ..drawLine(
            a,
            b,
            Paint()
              ..shader = const LinearGradient(
                colors: <Color>[AppColors.secondary, AppColors.cyan],
              ).createShader(Rect.fromPoints(a, b))
              ..strokeWidth = 2.4
              ..strokeCap = StrokeCap.round,
          );
    }
  }

  static Paint _stroke(Color colour, {double width = 1.6}) => Paint()
    ..color = colour
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round;

  /// SUGO's dashed route between [a] and [b]; [shift] slides the dashes.
  static void _dashed(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint, {
    double dash = 5,
    double gap = 5,
    double shift = 0,
  }) {
    final double length = (b - a).distance;
    if (length <= 0) return;
    final Offset unit = (b - a) / length;
    final double period = dash + gap;
    for (double s = -(shift % period); s < length; s += period) {
      final double s0 = math.max(0, s);
      final double s1 = math.min(length, s + dash);
      if (s1 > s0) canvas.drawLine(a + unit * s0, a + unit * s1, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _HubPainter oldDelegate) =>
      oldDelegate.clock != clock ||
      !identical(oldDelegate.states, states) ||
      oldDelegate.g.centre != g.centre ||
      oldDelegate.g.orbit != g.orbit;
}

// ------------------------------------------------------------- checklist

/// A frosted panel on the navy: the checklist sits on it.
class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.sm),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppSizes.sheetRadius - 2),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: child,
    );
  }
}

class _StepList extends StatelessWidget {
  const _StepList({required this.states});

  final List<_StepState> states;

  @override
  Widget build(BuildContext context) {
    final int active = states.indexOf(_StepState.active);
    return Semantics(
      liveRegion: true,
      label: active == -1
          ? 'Analysis complete'
          : 'Analyzing your request: ${_steps[active]}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < _steps.length; i++)
            _StepRow(label: _steps[i], icon: _stepIcons[i], state: states[i]),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.icon,
    required this.state,
  });

  final String label;
  final IconData icon;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final bool active = state == _StepState.active;
    final (Color colour, FontWeight weight) = switch (state) {
      _StepState.confirmed => (
        Colors.white.withValues(alpha: 0.92),
        FontWeight.w600,
      ),
      _StepState.passed => (
        Colors.white.withValues(alpha: 0.80),
        FontWeight.w600,
      ),
      _StepState.active => (Colors.white, FontWeight.w700),
      _StepState.pending => (
        Colors.white.withValues(alpha: 0.42),
        FontWeight.w500,
      ),
    };

    // The step being worked on is lit, with a cyan edge - the same step whose
    // line is marching in the hub above.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.sm + 1,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        gradient: active
            ? LinearGradient(
                colors: <Color>[
                  AppColors.cyan.withValues(alpha: 0.16),
                  AppColors.cyan.withValues(alpha: 0.03),
                ],
              )
            : null,
        border: Border.all(
          color: active
              ? AppColors.cyan.withValues(alpha: 0.35)
              : Colors.transparent,
        ),
      ),
      child: Row(
        children: <Widget>[
          SizedBox.square(
            dimension: 24,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              transitionBuilder: (Widget child, Animation<double> animation) =>
                  ScaleTransition(
                    scale: CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutBack,
                    ),
                    child: FadeTransition(opacity: animation, child: child),
                  ),
              child: KeyedSubtree(
                key: ValueKey<_StepState>(state),
                child: _StepIcon(state: state),
              ),
            ),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 260),
              // Names the family: AnimatedDefaultTextStyle *replaces* the
              // inherited style, and without it the checklist fell back to the
              // phone's own font.
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 15,
                height: 1.3,
                fontWeight: weight,
                color: colour,
              ),
              child: Text(label),
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          Icon(
            icon,
            size: 16,
            color: active
                ? AppColors.cyan
                : Colors.white.withValues(
                    alpha: state == _StepState.pending ? 0.22 : 0.40,
                  ),
          ),
        ],
      ),
    );
  }
}

class _StepIcon extends StatelessWidget {
  const _StepIcon({required this.state});

  final _StepState state;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case _StepState.confirmed:
        return Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[AppColors.secondary, AppColors.cyan],
            ),
          ),
          child: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
        );
      case _StepState.passed:
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.cyan.withValues(alpha: 0.6),
              width: 1.6,
            ),
          ),
          child: Icon(
            Icons.check_rounded,
            size: 14,
            color: AppColors.cyan.withValues(alpha: 0.8),
          ),
        );
      case _StepState.active:
        return Padding(
          padding: const EdgeInsets.all(2),
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            strokeCap: StrokeCap.round,
            color: AppColors.cyan,
            backgroundColor: Colors.white.withValues(alpha: 0.12),
          ),
        );
      case _StepState.pending:
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.22),
              width: 1.6,
            ),
          ),
        );
    }
  }
}

/// The bar: blue to cyan, a glowing head, and a light sweeping along the
/// filled part while the work is still going.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.value,
    required this.sheen,
    required this.done,
  });

  final double value;

  /// Seconds, for the sweeping light (held still under reduced motion).
  final double sheen;

  /// The result is back: the sweep stops, the bar just completes.
  final bool done;

  @override
  Widget build(BuildContext context) {
    final double v = value.clamp(0.0, 1.0);
    // Full width explicitly: inside a centred Column the constraints are
    // loose, and the Stack would otherwise shrink to the fill - no track,
    // and a bar that grows from the middle.
    return SizedBox(
      width: double.infinity,
      height: 14,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final double width = box.maxWidth;
          final double fill = width * v;
          final double sweep = ((sheen * 0.6) % 1.0) * 1.6 - 0.3;

          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                child: SizedBox(
                  width: width,
                  height: 6,
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: ColoredBox(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: fill,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: const <Color>[
                                AppColors.secondary,
                                AppColors.cyan,
                              ],
                            ),
                          ),
                          child: done
                              ? null
                              : DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment(-1 + 2 * sweep - 0.3, 0),
                                      end: Alignment(-1 + 2 * sweep + 0.3, 0),
                                      colors: <Color>[
                                        Colors.white.withValues(alpha: 0),
                                        Colors.white.withValues(alpha: 0.45),
                                        Colors.white.withValues(alpha: 0),
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // The head: a small light where the fill ends.
              if (fill > 4)
                Positioned(
                  left: fill - 7,
                  width: 14,
                  height: 14,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: AppColors.cyan.withValues(alpha: 0.85),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------- scaffolds

/// The loader as a whole screen: navy edge to edge, light status bar, a
/// transparent app bar that only carries the back arrow.
class MatchingLoaderScaffold extends StatelessWidget {
  const MatchingLoaderScaffold({
    super.key,
    required this.loader,
    this.canGoBack = true,
  });

  final Widget loader;

  /// False while a job is still being saved - leaving then would strand it.
  final bool canGoBack;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.navy,
        extendBodyBehindAppBar: true,
        // The one raw AppBar left after the Dispatch roll-out, on purpose:
        // transparent over the navy analysis screen, with white icons.
        // SugoAppBar is drawn for the light page ground.
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: canGoBack,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        body: loader,
      ),
    );
  }
}

/// Shows the analysis screen while matching runs, then hands off to
/// [results] once the result is back and the finish has played.
///
/// ## When it shows at all
///
/// * **Arriving from a post**: the job was saved and matched on the previous
///   screen. The analysis stays up, finishing, while the result is read back,
///   so the client sees one continuous screen rather than navy, then white,
///   then results.
/// * **A re-match** with nothing on screen yet: the matcher is running again.
///
/// Merely opening a job that already has results is not analysis - nothing is
/// being analysed - so it never shows then. That case gets a skeleton list
/// inside [results].
///
/// A failed match skips the finish: ticking every step and then showing an
/// error would claim a success that did not happen.
class MatchingHandoff extends StatefulWidget {
  const MatchingHandoff({
    super.key,
    required this.loading,
    required this.matching,
    required this.failed,
    required this.results,
    this.arrivedFromPost = false,
    this.session,
  });

  /// Loading with nothing on screen yet.
  final bool loading;

  /// The matcher itself is running (a re-match), not just a read.
  final bool matching;

  /// The run ended in an error.
  final bool failed;

  final bool arrivedFromPost;

  /// The session the posting screen started, for continuity.
  final MatchingSession? session;

  final Widget results;

  @override
  State<MatchingHandoff> createState() => _MatchingHandoffState();
}

class _MatchingHandoffState extends State<MatchingHandoff> {
  late MatchingSession _session = widget.session ?? MatchingSession();
  late bool _arrivalPending = widget.arrivedFromPost;
  late bool _showing = _wants;
  bool _finished = false;

  bool get _wants =>
      widget.loading && (widget.matching || _arrivalPending) && !widget.failed;

  @override
  void didUpdateWidget(MatchingHandoff oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.failed && _showing) {
      _hide();
    } else if (_wants && !_showing) {
      // A fresh re-match: a fresh clock, so it does not start "done".
      _session = MatchingSession();
      _showing = true;
      _finished = false;
    } else if (!_wants && _showing && _finished) {
      _hide();
    }
  }

  void _hide() {
    _showing = false;
    _arrivalPending = false;
  }

  void _onFinished() {
    _finished = true;
    if (!_wants && mounted) setState(_hide);
  }

  @override
  Widget build(BuildContext context) {
    final MatchingPhase phase = widget.loading && widget.matching
        ? MatchingPhase.matching
        : MatchingPhase.done;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      child: _showing
          ? KeyedSubtree(
              key: ObjectKey(_session),
              child: MatchingLoaderScaffold(
                loader: TechnicianMatchingLoader(
                  phase: phase,
                  session: _session,
                  onFinished: _onFinished,
                ),
              ),
            )
          : KeyedSubtree(
              key: const ValueKey<String>('results'),
              child: widget.results,
            ),
    );
  }
}
