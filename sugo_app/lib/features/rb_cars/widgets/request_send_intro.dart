import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import 'technician_matching_loader.dart';

/// The opening of "Find technician" / "Save & find technicians": the request
/// as a letter, sealed, and passed from technician to technician - then the
/// analysis screen (`TechnicianMatchingLoader`) takes over. Added 2026-11-23
/// at the user's request: "a letter passing to the technician, slide show,
/// then the main finding animation".
///
/// ## What happens, in about 2.8 s
///
/// | t (of 1)   | what the client sees                                     |
/// |------------|----------------------------------------------------------|
/// | 0.00-0.14  | their request rises in as a letter - the job and price   |
/// | 0.10-0.22  | an envelope opens behind it                              |
/// | 0.22-0.42  | the letter slips in and the flap folds shut              |
/// | 0.41-0.50  | a SUGO seal stamps it                                    |
/// | 0.44-0.68  | technicians slide in, one after another, like slides     |
/// | 0.52-0.60  | the envelope shrinks and glides to the first of them     |
/// | 0.60-0.88  | it hops from one to the next along SUGO's dashed route;  |
/// |            | each lights up and ticks as it is reached                |
/// | 0.88-1.00  | it rises into the centre and bursts into the glow the    |
/// |            | analysis screen opens on                                 |
///
/// ## Not a wait
///
/// It plays WHILE the job saves - the posting screen starts the save on its
/// first frame, under this - so it covers the start of a wait that is already
/// happening rather than adding one. Only a save faster than 2.8 s, which
/// matching (live weather and traffic) rarely is, sees the whole of it.
///
/// ## Honest
///
/// The technicians are drawn, not real people, and the line under it says
/// "Nobody is booked yet": matching weighs the technicians nearby, and the
/// client still chooses who gets the request.
///
/// Under "remove animations" it is skipped, and the analysis screen shows at
/// once.
class RequestSendIntro extends StatefulWidget {
  const RequestSendIntro({
    super.key,
    required this.title,
    this.detail,
    this.editing = false,
    this.onDone,
  });

  /// The job, as the letter shows it: "Keyboard or trackpad not working".
  final String title;

  /// A second line: "Laptop / PC · ₱600".
  final String? detail;

  /// Saving changes to a posted job ("Packing up your changes").
  final bool editing;

  /// Called once, when it has played (or at once under reduced motion).
  final VoidCallback? onDone;

  static const Duration duration = Duration(milliseconds: 2800);

  @override
  State<RequestSendIntro> createState() => _RequestSendIntroState();
}

/// Phase boundaries, as fractions of [RequestSendIntro.duration].
abstract final class _T {
  static const double letterIn = 0.00, letterInEnd = 0.14;
  static const double backIn = 0.10, backInEnd = 0.22;
  static const double letterDown = 0.22, letterDownEnd = 0.34;
  static const double flap = 0.33, flapEnd = 0.42;
  static const double seal = 0.41, sealEnd = 0.50;
  static const double techIn = 0.44, techStagger = 0.04, techInSpan = 0.12;
  static const double glide = 0.52, glideEnd = 0.60;
  static const double travel = 0.60, travelEnd = 0.88;
  static const double exit = 0.88;
}

/// The four drawn technicians, across the stage.
const List<double> _techX = <double>[0.2, 0.4, 0.6, 0.8];

/// The route: x runs 0.12 -> 0.88 of the width as p runs 0 -> 1, so a
/// technician at x sits at p = (x - 0.12) / 0.76, and the hops land on them.
const double _pathX0 = 0.12, _pathXSpan = 0.76;
double _pAt(double x) => (x - _pathX0) / _pathXSpan;

class _RequestSendIntroState extends State<RequestSendIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _doneCalled = false;

  /// Time for the shared backdrop's twinkle, driven by [_c].
  final ValueNotifier<Duration> _backdropClock = ValueNotifier<Duration>(
    Duration.zero,
  );

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: RequestSendIntro.duration)
      ..addListener(
        () => _backdropClock.value = RequestSendIntro.duration * _c.value,
      )
      ..addStatusListener((AnimationStatus status) {
        if (status == AnimationStatus.completed) _done();
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      // Posed sealed, for the one frame before the analysis screen.
      _c.value = _T.sealEnd;
      WidgetsBinding.instance.addPostFrameCallback((_) => _done());
    } else if (_c.value == 0 && !_c.isAnimating) {
      _c.forward();
    }
  }

  void _done() {
    if (_doneCalled || !mounted) return;
    _doneCalled = true;
    widget.onDone?.call();
  }

  @override
  void dispose() {
    _c.dispose();
    _backdropClock.dispose();
    super.dispose();
  }

  String _headline(double v) {
    if (v < _T.glide) {
      return widget.editing
          ? 'Packing up your changes'
          : 'Packing up your request';
    }
    if (v < _T.exit) return 'Passing it to technicians near you';
    return 'Finding your best match';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints outer) => SizedBox(
        width: outer.hasBoundedWidth ? outer.maxWidth : null,
        height: outer.hasBoundedHeight ? outer.maxHeight : null,
        child: Stack(
          children: <Widget>[
            // The analysis screen's own ground, dots and all, so the
            // hand-over is seamless.
            Positioned.fill(child: MatchingBackdrop(clock: _backdropClock)),
            SafeArea(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints box) {
                  final double width = math.min(
                    box.maxWidth - 2 * AppSizes.screenPadding,
                    380,
                  );
                  // The analysis screen's frame: the burst at the centre of
                  // this picture is where its hub appears.
                  final double height = MatchingStageLayout.heroHeight(
                    box.maxHeight,
                  );

                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: box.maxWidth),
                      child: Column(
                        children: <Widget>[
                          const SizedBox(height: MatchingStageLayout.top),
                          Semantics(
                            label: 'Sending your request',
                            child: ExcludeSemantics(
                              child: SizedBox(
                                width: width,
                                height: height,
                                child: AnimatedBuilder(
                                  animation: _c,
                                  builder: (BuildContext _, Widget? _) =>
                                      _Stage(
                                        v: _c.value,
                                        size: Size(width, height),
                                        title: widget.title,
                                        detail: widget.detail,
                                      ),
                                ),
                              ),
                            ),
                          ),
                          // Where the analysis screen's title sits, so one
                          // headline fades into the other in place.
                          const SizedBox(height: AppSizes.md),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSizes.screenPadding + AppSizes.sm,
                            ),
                            child: AnimatedBuilder(
                              animation: _c,
                              builder: (BuildContext _, Widget? _) =>
                                  _Headline(text: _headline(_c.value)),
                            ),
                          ),
                          const SizedBox(height: AppSizes.sm),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSizes.screenPadding + AppSizes.sm,
                            ),
                            child: Text(
                              'Nobody is booked yet - you choose from your top 3.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 13,
                                height: 1.4,
                                color: Colors.white.withValues(alpha: 0.72),
                              ),
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
        ),
      ),
    );
  }
}

/// The headline under the stage, changing with the phase: slides up into
/// place as the old line fades.
class _Headline extends StatelessWidget {
  const _Headline({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.reduced(context)
          ? Duration.zero
          : const Duration(milliseconds: 320),
      transitionBuilder: (Widget child, Animation<double> a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.35),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
      child: Text(
        text,
        key: ValueKey<String>(text),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          height: 1.2,
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ stage

/// One frame of the stage at [v] (0..1). Rebuilt each frame; everything in it
/// is a pure function of [v] and [size].
class _Stage extends StatelessWidget {
  const _Stage({
    required this.v,
    required this.size,
    required this.title,
    required this.detail,
  });

  final double v;
  final Size size;
  final String title;
  final String? detail;

  /// 0..1 progress through [start, end], eased.
  double _phase(double start, double end, [Curve curve = Curves.easeInOut]) =>
      curve.transform(((v - start) / (end - start)).clamp(0.0, 1.0));

  double get _envW => (size.width * 0.5).clamp(140.0, 190.0);
  double get _envH => _envW * 0.66;
  double get _tech => (size.width * 0.13).clamp(38.0, 54.0);
  double get _techY => size.height * 0.82;

  /// The envelope's size while it travels, as a share of its full size.
  static const double _travelScale = 0.40;

  double get _hopLow => _techY - _tech / 2 - _envH * _travelScale / 2 - 6;
  double get _hopHeight => size.height * 0.17;

  /// A point on the hopping route, p 0..1.
  Offset _route(double p) {
    final double x = size.width * (_pathX0 + _pathXSpan * p);
    final double gap = _pAt(_techX[1]) - _pAt(_techX[0]);
    final double hop = (math.sin(math.pi * (p - _pAt(_techX[0])) / gap)).abs();
    return Offset(x, _hopLow - _hopHeight * hop);
  }

  /// Where the envelope is, how big, how visible, and how it leans.
  ({Offset centre, double scale, double opacity, double tilt}) _carrier() {
    final Offset rest = Offset(size.width / 2, size.height * 0.40);
    if (v < _T.glide) {
      return (centre: rest, scale: 1, opacity: 1, tilt: 0);
    }
    if (v < _T.travel) {
      final double g = _phase(_T.glide, _T.glideEnd, Curves.easeInOutCubic);
      return (
        centre: Offset.lerp(rest, _route(0), g)!,
        scale: 1 + (_travelScale - 1) * g,
        opacity: 1,
        // Leans into the glide to the left, then straightens.
        tilt: -0.22 * math.sin(math.pi * g),
      );
    }
    if (v < _T.exit) {
      final double p = _phase(_T.travel, _T.travelEnd, Curves.linear);
      // Nose along the hop: up as it leaves a technician, down as it lands.
      final Offset d =
          _route(math.min(1, p + 0.004)) - _route(math.max(0, p - 0.004));
      return (
        centre: _route(p),
        scale: _travelScale,
        opacity: 1,
        tilt: (math.atan2(d.dy, d.dx) * 0.3).clamp(-0.32, 0.32),
      );
    }
    // Into the centre first (0.88-0.96), then it shrinks into the burst and
    // is gone (0.95-1.00) - so the burst comes out of the envelope.
    final double e = _phase(_T.exit, 0.96, Curves.easeInOutCubic);
    final double vanish = _phase(0.95, 1, Curves.easeInCubic);
    return (
      centre: Offset.lerp(_route(1), _exitPoint, e)!,
      scale: _travelScale * (1 - 0.25 * e) * (1 - 0.8 * vanish),
      opacity: 1 - vanish,
      tilt: -0.25 * math.sin(math.pi * e),
    );
  }

  /// The centre of the picture - where the analysis screen's hub appears,
  /// since both screens share `MatchingStageLayout`.
  Offset get _exitPoint => Offset(size.width / 2, size.height * 0.5);

  /// Seconds into the animation, for the technicians' idle bob.
  double get _seconds => v * RequestSendIntro.duration.inMilliseconds / 1000;

  /// Travel progress p (0..1), or null before the envelope sets off.
  double? get _p =>
      v < _T.travel ? null : _phase(_T.travel, _T.travelEnd, Curves.linear);

  @override
  Widget build(BuildContext context) {
    final ({Offset centre, double scale, double opacity, double tilt}) carrier =
        _carrier();
    final double? p = _p;
    final double glow = _envW * 0.85 * carrier.scale;

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        // The burst the analysis screen opens on.
        if (v >= _T.exit)
          Positioned.fill(
            child: CustomPaint(
              painter: _BurstPainter(
                centre: _exitPoint,
                t: _phase(0.95, 1, Curves.easeOutCubic),
                maxRadius: math.min(size.width, size.height) * 0.55,
              ),
            ),
          ),

        // SUGO's dashed route, drawn only as far as the envelope has gone.
        if (p != null)
          Positioned.fill(
            child: CustomPaint(
              painter: _TrailPainter(
                route: _route,
                upTo: p,
                fade: 1 - _phase(_T.exit, 0.96),
              ),
            ),
          ),

        // The technicians, sliding in one after another.
        for (int i = 0; i < _techX.length; i++) _techAt(i),

        // A soft light the envelope carries with it.
        Positioned(
          left: carrier.centre.dx - glow,
          top: carrier.centre.dy - glow,
          width: glow * 2,
          height: glow * 2,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    AppColors.cyan.withValues(
                      alpha:
                          0.20 *
                          carrier.opacity *
                          _phase(_T.backIn, _T.backInEnd),
                    ),
                    AppColors.cyan.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),

        // The letter and its envelope.
        Positioned(
          left: carrier.centre.dx - _envW / 2,
          top: carrier.centre.dy - _envH / 2,
          width: _envW,
          height: _envH,
          child: Opacity(
            opacity: carrier.opacity,
            child: Transform.rotate(
              angle: carrier.tilt,
              child: Transform.scale(
                scale: carrier.scale,
                child: _Envelope(
                  width: _envW,
                  height: _envH,
                  letterIn: _phase(
                    _T.letterIn,
                    _T.letterInEnd,
                    Curves.easeOutCubic,
                  ),
                  backIn: _phase(_T.backIn, _T.backInEnd, Curves.easeOutCubic),
                  letterDown: _phase(
                    _T.letterDown,
                    _T.letterDownEnd,
                    Curves.easeInOutCubic,
                  ),
                  flap: _phase(_T.flap, _T.flapEnd, Curves.easeInOutCubic),
                  seal: _phase(_T.seal, _T.sealEnd, Curves.linear),
                  title: title,
                  detail: detail,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _techAt(int i) {
    final double start = _T.techIn + _T.techStagger * i;
    final double slide = _phase(
      start,
      start + _T.techInSpan,
      Curves.easeOutCubic,
    );
    // Lit from the moment the envelope touches down on them, over a fixed
    // ~170 ms - timed on the clock, not the route, so the last one finishes
    // its bounce during the exit instead of freezing half-way.
    final double touch =
        _T.travel + _pAt(_techX[i]) * (_T.travelEnd - _T.travel);
    final double lit = ((v - touch) / 0.06).clamp(0.0, 1.0);
    final double dx = (1 - slide) * size.width * 0.7;
    // A gentle idle bob, each a little out of step, so they read as people
    // waiting rather than icons.
    final double bob = math.sin(_seconds * 2.4 + i * 1.3) * 1.6 * slide;

    return Positioned(
      left: size.width * _techX[i] - _tech / 2 + dx,
      top: _techY - _tech / 2 + bob,
      width: _tech,
      height: _tech,
      child: Opacity(
        opacity: slide,
        child: _Technician(size: _tech, lit: lit, variant: i),
      ),
    );
  }
}

// --------------------------------------------------------------- envelope

/// The letter animation's envelope, already sealed - for anywhere else a
/// request is "sent" (2026-11-23: the Send request fly-away). The same
/// drawing, so both moments use one messenger.
class SealedEnvelope extends StatelessWidget {
  const SealedEnvelope({super.key, required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width * 0.66,
      child: _Envelope(
        width: width,
        height: width * 0.66,
        letterIn: 1,
        backIn: 1,
        letterDown: 1,
        flap: 1,
        seal: 1,
        title: '',
        detail: null,
      ),
    );
  }
}

/// The letter going into its envelope, the flap folding, the seal stamping.
///
/// Layers, back to front: the open flap (its inside), the envelope's inside,
/// the letter, the pocket (left, right and bottom panels, which hide the
/// letter as it goes in), the closing flap, the seal. The flap is drawn
/// behind the letter while it is open and in front once it passes upright.
class _Envelope extends StatelessWidget {
  const _Envelope({
    required this.width,
    required this.height,
    required this.letterIn,
    required this.backIn,
    required this.letterDown,
    required this.flap,
    required this.seal,
    required this.title,
    required this.detail,
  });

  final double width;
  final double height;
  final double letterIn;
  final double backIn;
  final double letterDown;
  final double flap;
  final double seal;
  final String title;
  final String? detail;

  static const Color _inside = Color(0xFFD7E4F7);
  static const Color _flapInside = Color(0xFFC6D7F0);
  static const Color _paper = Color(0xFFFFFFFF);
  static const Color _edge = Color(0xFFC3D2EA);

  @override
  Widget build(BuildContext context) {
    final double letterW = width * 0.84;
    final double letterH = width * 0.56;

    // Above the envelope at first, then all the way in.
    final double startY = height / 2 - width * 0.40;
    final double endY = height / 2 + width * 0.04;
    final double letterCentreY =
        startY + (endY - startY) * letterDown + (1 - letterIn) * 22;

    // Open is pi (flipped up, behind); shut is 0 (down, in front).
    final double angle = math.pi * (1 - flap);
    final bool flapInFront = angle <= math.pi / 2;
    final double flapH = height * 0.58;

    // Positioned on the outside: it has to be the Stack's direct child.
    Widget flapWidget(Color fill, {double opacity = 1}) => Positioned(
      left: 0,
      top: 0,
      width: width,
      height: flapH,
      child: Opacity(
        opacity: opacity,
        child: Transform(
          alignment: Alignment.topCenter,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0016)
            ..rotateX(angle),
          child: CustomPaint(
            painter: _FlapPainter(fill: fill, edge: _edge),
          ),
        ),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        if (!flapInFront && backIn > 0)
          flapWidget(_flapInside, opacity: backIn),

        // The inside of the envelope.
        Positioned.fill(
          child: Opacity(
            opacity: backIn,
            child: Transform.translate(
              offset: Offset(0, (1 - backIn) * 14),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _inside,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28 * backIn),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // The letter.
        Positioned(
          left: (width - letterW) / 2,
          top: letterCentreY - letterH / 2,
          width: letterW,
          height: letterH,
          child: Opacity(
            opacity: letterIn,
            child: Transform.scale(
              scale: 0.92 + 0.08 * letterIn,
              child: _Letter(width: letterW, title: title, detail: detail),
            ),
          ),
        ),

        // The pocket, in front of the letter.
        Positioned.fill(
          child: Opacity(
            opacity: backIn,
            child: Transform.translate(
              offset: Offset(0, (1 - backIn) * 14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CustomPaint(
                  painter: _PocketPainter(fill: _paper, edge: _edge),
                ),
              ),
            ),
          ),
        ),

        if (flapInFront) flapWidget(const Color(0xFFF4F8FE)),

        // The seal, stamped where the flap's tip lands.
        if (seal > 0)
          Positioned(
            left: width / 2 - width * 0.12,
            top: flapH - width * 0.12,
            width: width * 0.24,
            height: width * 0.24,
            child: _Seal(t: seal),
          ),
      ],
    );
  }
}

/// The request as a letter: what it is for, and what it costs.
class _Letter extends StatelessWidget {
  const _Letter({required this.width, required this.title, this.detail});

  final double width;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final double k = width / 143;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8 * k),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.30),
            blurRadius: 14 * k,
            offset: Offset(0, 5 * k),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(10 * k, 9 * k, 10 * k, 8 * k),
        child: MediaQuery.withNoTextScaling(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 8 * k,
                    height: 8 * k,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: <Color>[AppColors.secondary, AppColors.cyan],
                      ),
                    ),
                  ),
                  SizedBox(width: 5 * k),
                  Text(
                    'SUGO REQUEST',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 7.5 * k,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.9 * k,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 6 * k),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 11.5 * k,
                  fontWeight: FontWeight.w800,
                  height: 1.18,
                  color: AppColors.navy,
                ),
              ),
              const Spacer(),
              // A dashed rule: the route line, in miniature.
              CustomPaint(
                size: Size(width, 2 * k),
                painter: _DashRule(color: AppColors.secondary, k: k),
              ),
              SizedBox(height: 5 * k),
              if (detail != null)
                Text(
                  detail!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 9 * k,
                    fontWeight: FontWeight.w700,
                    color: AppColors.secondaryDark,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The SUGO seal: pops in with an overshoot, and a ring ripples off it.
class _Seal extends StatelessWidget {
  const _Seal({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final double pop = Curves.easeOutBack.transform((t / 0.6).clamp(0.0, 1.0));
    final double ripple = Curves.easeOutCubic.transform(t);

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: <Widget>[
        // The ripple.
        Transform.scale(
          scale: 1 + 0.9 * ripple,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.cyan.withValues(alpha: 0.7 * (1 - ripple)),
                width: 2,
              ),
            ),
            child: const SizedBox.expand(),
          ),
        ),
        Transform.scale(
          scale: pop,
          child: Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[AppColors.secondary, AppColors.cyan],
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: AppColors.cyan.withValues(alpha: 0.45),
                  blurRadius: 10,
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                AppAssets.brandEmblem,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                errorBuilder: (BuildContext _, Object _, StackTrace? _) =>
                    const ColoredBox(color: AppColors.primary),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ technicians

/// A drawn technician (not a real person): a navy-to-blue disc with a hard
/// hat. Reached, the ring turns cyan, it bounces once, and a tick pops.
class _Technician extends StatelessWidget {
  const _Technician({
    required this.size,
    required this.lit,
    required this.variant,
  });

  final double size;
  final double lit;
  final int variant;

  static const List<List<Color>> _discs = <List<Color>>[
    <Color>[Color(0xFF0B3C7A), AppColors.secondary],
    <Color>[Color(0xFF0A4A8F), Color(0xFF1593F0)],
    <Color>[Color(0xFF0B3C7A), Color(0xFF0E9FD8)],
    <Color>[Color(0xFF09356D), AppColors.secondary],
  ];

  @override
  Widget build(BuildContext context) {
    final double bounce = math.sin(math.pi * lit) * 0.16;
    final double tick = Curves.easeOutBack.transform(
      ((lit - 0.25) / 0.75).clamp(0.0, 1.0),
    );

    return Transform.scale(
      scale: 1 + bounce,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: <Widget>[
          // Glow once reached.
          if (lit > 0)
            Positioned(
              left: -size * 0.35,
              top: -size * 0.35,
              width: size * 1.7,
              height: size * 1.7,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: <Color>[
                      AppColors.cyan.withValues(alpha: 0.40 * lit),
                      AppColors.cyan.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _discs[variant % _discs.length],
              ),
              border: Border.all(
                color: Color.lerp(
                  Colors.white.withValues(alpha: 0.28),
                  AppColors.cyan,
                  lit,
                )!,
                width: 2 + lit,
              ),
            ),
            child: Icon(
              Icons.engineering_rounded,
              size: size * 0.56,
              color: Colors.white,
            ),
          ),
          // Before: a little wrench badge. Reached: a cyan tick.
          Positioned(
            right: -size * 0.06,
            bottom: -size * 0.06,
            width: size * 0.40,
            height: size * 0.40,
            child: tick > 0
                ? Transform.scale(
                    scale: tick,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.cyan,
                        border: Border.all(color: AppColors.navy, width: 2),
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        size: size * 0.26,
                        color: Colors.white,
                      ),
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.navy,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      Icons.build_rounded,
                      size: size * 0.20,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- painters

class _FlapPainter extends CustomPainter {
  _FlapPainter({required this.fill, required this.edge});

  final Color fill;
  final Color edge;

  @override
  void paint(Canvas canvas, Size size) {
    final Path flap = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2 + 10, size.height - 6)
      ..quadraticBezierTo(
        size.width / 2,
        size.height + 2,
        size.width / 2 - 10,
        size.height - 6,
      )
      ..close();
    canvas
      ..drawPath(flap, Paint()..color = fill)
      ..drawPath(
        flap,
        Paint()
          ..color = edge
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeJoin = StrokeJoin.round,
      );
  }

  @override
  bool shouldRepaint(_FlapPainter old) => old.fill != fill || old.edge != edge;
}

class _PocketPainter extends CustomPainter {
  _PocketPainter({required this.fill, required this.edge});

  final Color fill;
  final Color edge;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width, h = size.height;
    final Paint paper = Paint()..color = fill;
    final Paint line = Paint()
      ..color = edge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeJoin = StrokeJoin.round;

    // Left and right panels meet just below the middle; the bottom panel
    // rises over both.
    final Path sides = Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.5, h * 0.58)
      ..lineTo(0, h)
      ..close()
      ..moveTo(w, 0)
      ..lineTo(w * 0.5, h * 0.58)
      ..lineTo(w, h)
      ..close();
    final Path bottom = Path()
      ..moveTo(0, h)
      ..lineTo(w * 0.5, h * 0.50)
      ..lineTo(w, h)
      ..close();

    canvas
      ..drawPath(sides, Paint()..color = const Color(0xFFEFF4FC))
      ..drawPath(sides, line)
      ..drawPath(bottom, paper)
      ..drawPath(bottom, line);
  }

  @override
  bool shouldRepaint(_PocketPainter old) =>
      old.fill != fill || old.edge != edge;
}

class _DashRule extends CustomPainter {
  _DashRule({required this.color, required this.k});

  final Color color;
  final double k;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 1.6 * k
      ..strokeCap = StrokeCap.round;
    final double y = size.height / 2;
    for (double x = 0; x < size.width * 0.62; x += 7 * k) {
      canvas.drawLine(Offset(x, y), Offset(x + 3.5 * k, y), p);
    }
  }

  @override
  bool shouldRepaint(_DashRule old) => old.color != color || old.k != k;
}

/// The dashed route behind the envelope - SUGO's signature line, drawn only
/// as far as the envelope has actually travelled.
class _TrailPainter extends CustomPainter {
  _TrailPainter({required this.route, required this.upTo, required this.fade});

  final Offset Function(double p) route;
  final double upTo;
  final double fade;

  static const double _dash = 7, _gap = 6;

  @override
  void paint(Canvas canvas, Size size) {
    if (upTo <= 0 || fade <= 0) return;
    final Paint paint = Paint()
      ..color = AppColors.cyan.withValues(alpha: 0.70 * fade)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    const int samples = 160;

    // A soft glow under the dashes, so the route reads as light.
    final Path glow = Path()..moveTo(route(0).dx, route(0).dy);
    for (int i = 1; i <= samples; i++) {
      final Offset point = route(upTo * i / samples);
      glow.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      glow,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = AppColors.cyan.withValues(alpha: 0.16 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    double run = 0;
    Offset previous = route(0);
    for (int i = 1; i <= samples; i++) {
      final double p = upTo * i / samples;
      final Offset point = route(p);
      final double length = (point - previous).distance;
      // Draws the parts of this little segment that fall on a dash.
      final double cycle = _dash + _gap;
      final double phase = run % cycle;
      if (phase < _dash) {
        final double drawn = math.min(_dash - phase, length);
        canvas.drawLine(
          previous,
          Offset.lerp(previous, point, drawn / length)!,
          paint,
        );
      }
      run += length;
      previous = point;
    }
  }

  @override
  bool shouldRepaint(_TrailPainter old) => old.upTo != upTo || old.fade != fade;
}

/// The glow and ring the envelope bursts into - where the analysis screen's
/// emblem appears next.
class _BurstPainter extends CustomPainter {
  _BurstPainter({
    required this.centre,
    required this.t,
    required this.maxRadius,
  });

  final Offset centre;
  final double t;
  final double maxRadius;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final double r = maxRadius * t;
    canvas
      ..drawCircle(
        centre,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[
              AppColors.cyan.withValues(alpha: 0.30 * (1 - t * 0.6)),
              AppColors.secondary.withValues(alpha: 0.10 * (1 - t)),
              Colors.transparent,
            ],
            stops: const <double>[0.0, 0.55, 1.0],
          ).createShader(Rect.fromCircle(center: centre, radius: r)),
      )
      ..drawCircle(
        centre,
        r * 0.8,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = AppColors.cyan.withValues(alpha: 0.65 * (1 - t)),
      );
  }

  @override
  bool shouldRepaint(_BurstPainter old) =>
      old.t != t || old.centre != centre || old.maxRadius != maxRadius;
}
