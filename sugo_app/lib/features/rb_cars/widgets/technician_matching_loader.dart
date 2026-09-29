import 'dart:math' as math;

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

/// The context-aware analysis screen, shown while RB-CARS matches a request.
///
/// ## What is on it
///
/// The SUGO emblem in a pulsing, scanning disc; "Analyzing your
/// request..."; the pipeline as a checklist - the request, the weather, the
/// traffic, the matching rules, the technicians; and a progress bar.
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

  /// Every frame - drives the emblem and the bar, and nothing else.
  late final ValueNotifier<Duration> _clock = ValueNotifier<Duration>(
    _session.elapsed,
  );

  /// Only when a step actually changes state - the list does not rebuild at
  /// 60 fps for a tick that happens five times.
  late final ValueNotifier<List<_StepState>> _states =
      ValueNotifier<List<_StepState>>(_computeStates(_session.elapsed));

  final ValueNotifier<bool> _slow = ValueNotifier<bool>(false);
  bool _finishedCalled = false;

  /// A clock that never moves, for the emblem under "remove animations".
  ///
  /// The real clock keeps running either way: it drives the step ticks, the
  /// progress bar and the hand-over to the results, which carry information.
  /// Only the orbiting emblem is decoration, so only it holds still - posed
  /// at a moment where the arc and the emblem are both clearly drawn.
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
    final double t = ((now - doneAt).inMilliseconds /
            _fillDuration.inMilliseconds)
        .clamp(0.0, 1.0);
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
    return DecoratedBox(
      // Lit from behind the emblem, falling off to the brand's darkest navy.
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.42),
          radius: 1.15,
          colors: <Color>[Color(0xFF0B3C7A), AppColors.navy],
        ),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool bounded = constraints.maxHeight.isFinite;
            // The emblem gives way first on a short screen, and whatever
            // still does not fit scrolls rather than overflowing.
            final double emblem = bounded
                ? (constraints.maxHeight * 0.32).clamp(140.0, 230.0)
                : 230.0;

            return SingleChildScrollView(
              child: ConstrainedBox(
                // Full width as well as full height, so the column centres
                // on the screen rather than on its own content.
                constraints: BoxConstraints(
                  minWidth: constraints.hasBoundedWidth
                      ? constraints.maxWidth
                      : 0,
                  minHeight: bounded ? constraints.maxHeight : 0,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.screenPadding + AppSizes.sm,
                    vertical: AppSizes.xl,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      _Emblem(
                        size: emblem,
                        clock: AppMotion.reduced(context) ? _still : _clock,
                      ),
                      const SizedBox(height: AppSizes.xl + AppSizes.sm),
                      const Text(
                        'Analyzing your request...',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: AppSizes.sm),
                      Text(
                        'SUGO is checking the right technicians for your '
                        'needs.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: Colors.white.withValues(alpha: 0.72),
                        ),
                      ),
                      const SizedBox(height: AppSizes.xl + AppSizes.sm),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 340),
                        child: ValueListenableBuilder<List<_StepState>>(
                          valueListenable: _states,
                          builder: (_, List<_StepState> states, _) =>
                              _StepList(states: states),
                        ),
                      ),
                      const SizedBox(height: AppSizes.xl + AppSizes.sm),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 340),
                        child: ValueListenableBuilder<Duration>(
                          valueListenable: _clock,
                          builder: (_, Duration now, _) =>
                              _ProgressBar(value: _progress(now)),
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
                                    'This is taking longer than usual. We are '
                                    'still looking - nothing has failed.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.4,
                                      color: Colors.white.withValues(
                                        alpha: 0.72,
                                      ),
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- emblem

/// The emblem (house, wrench, van) in its disc, with a glow, pulsing rings
/// and a scanning arc.
///
/// The rings and the arc are one `CustomPainter` repainting from [clock]
/// directly - no widget rebuilds for them at all. Only the emblem's gentle
/// float rebuilds, and that is a single transform.
class _Emblem extends StatelessWidget {
  const _Emblem({required this.size, required this.clock});

  final double size;
  final ValueNotifier<Duration> clock;

  @override
  Widget build(BuildContext context) {
    final double disc = size * 0.5;

    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Positioned.fill(
            child: CustomPaint(painter: _EmblemPainter(clock)),
          ),
          ValueListenableBuilder<Duration>(
            valueListenable: clock,
            builder: (_, Duration now, Widget? child) {
              final double t = now.inMilliseconds / 1000;
              return Transform.translate(
                offset: Offset(0, math.sin(t * 1.6) * size * 0.012),
                child: child,
              );
            },
            child: Container(
              width: disc,
              height: disc,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.cyan.withValues(alpha: 0.55),
                  width: 2,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.cyan.withValues(alpha: 0.35),
                    blurRadius: size * 0.12,
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  AppAssets.brandEmblem,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                  // The disc's own navy is close enough to the image's that
                  // a missing file still reads as an emblem.
                  errorBuilder: (BuildContext _, Object _, StackTrace? _) =>
                      const ColoredBox(color: AppColors.primary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmblemPainter extends CustomPainter {
  _EmblemPainter(this.clock) : super(repaint: clock);

  final ValueNotifier<Duration> clock;

  /// One ring every this long; three are in flight at once.
  static const double _ringPeriod = 2.4;

  @override
  void paint(Canvas canvas, Size size) {
    final double t = clock.value.inMilliseconds / 1000;
    final Offset c = size.center(Offset.zero);
    final double r = size.shortestSide / 2;

    // Glow behind everything.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            AppColors.cyan.withValues(alpha: 0.22),
            AppColors.secondary.withValues(alpha: 0.08),
            Colors.transparent,
          ],
          stops: const <double>[0.2, 0.55, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // Pulses travelling outward from the disc and fading as they go.
    for (int i = 0; i < 3; i++) {
      final double phase = ((t / _ringPeriod) + i / 3) % 1.0;
      final double radius = r * (0.5 + 0.48 * phase);
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = AppColors.cyan.withValues(alpha: 0.45 * (1 - phase)),
      );
    }

    // A fixed orbit, and an arc sweeping round it - "scanning".
    final double orbit = r * 0.66;
    canvas.drawCircle(
      c,
      orbit,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.10),
    );
    // The canvas turns, not the gradient: a sweep gradient is defined on
    // 0..2π, so an arc drawn across the 0 angle would lose its bright head
    // for a moment on every lap.
    const double sweep = math.pi * 0.55;
    final Rect orbitRect = Rect.fromCircle(center: Offset.zero, radius: orbit);
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..rotate((t * 1.9) % (2 * math.pi))
      ..drawArc(
        orbitRect,
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
              AppColors.cyan,
            ],
          ).createShader(orbitRect),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(covariant _EmblemPainter oldDelegate) =>
      oldDelegate.clock != clock;
}

// ------------------------------------------------------------- checklist

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int i = 0; i < _steps.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == _steps.length - 1 ? 0 : AppSizes.md + 2,
              ),
              child: _StepRow(label: _steps[i], state: states[i]),
            ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.label, required this.state});

  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final (Color colour, FontWeight weight) = switch (state) {
      _StepState.confirmed => (Colors.white.withValues(alpha: 0.92), FontWeight.w600),
      _StepState.passed => (Colors.white.withValues(alpha: 0.80), FontWeight.w600),
      _StepState.active => (Colors.white, FontWeight.w700),
      _StepState.pending => (Colors.white.withValues(alpha: 0.42), FontWeight.w500),
    };

    return Row(
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
      ],
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

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      // Full width explicitly: inside a centred Column the constraints are
      // loose, and the Stack would otherwise shrink to the fill - no track,
      // and a bar that grows from the middle.
      child: SizedBox(
        width: double.infinity,
        height: 6,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: ColoredBox(color: Colors.white.withValues(alpha: 0.12)),
            ),
            FractionallySizedBox(
              // Fills from the left; the default would grow it from the middle.
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[AppColors.secondary, AppColors.cyan],
                  ),
                ),
                child: SizedBox.expand(),
              ),
            ),
          ],
        ),
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
