import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/job_tracking.dart';
import '../models/trip_conditions.dart';
import '../services/delay_alerts.dart';
import 'condition_glyphs.dart';

/// Shows the "running late" pop-up for [tracking] if this trip has not had one.
///
/// Returns true when the client asked to see the live map, which only happens
/// when [offerTracking] is set: the tracking screen passes false, because the
/// map is already in front of them.
///
/// Safe to call on every realtime update. [DelayAlerts.claim] lets exactly one
/// call per trip through, and every other call returns false without showing
/// anything.
///
/// [clientTrip] is the technician's version: the CLIENT is late on their way
/// to collect the unit.
Future<bool> maybeShowDelayAlert(
  BuildContext context,
  JobTracking tracking, {
  bool offerTracking = false,
  bool clientTrip = false,
}) async {
  if (!await DelayAlerts.claim(tracking, clientTrip: clientTrip)) return false;
  if (!context.mounted) return false;
  final bool? track = await showDialog<bool>(
    context: context,
    builder: (_) => DelayAlertDialog(
      tracking: tracking,
      offerTracking: offerTracking,
      clientTrip: clientTrip,
    ),
  );
  return track ?? false;
}

/// The pop-up itself, redesigned 2026-11-17.
///
/// ## What changed, and what did not
///
/// It used to be a plain `AlertDialog` with an icon tile. It now opens on an
/// animated picture of the CAUSE - rain from a dark cloud, cars crawling with
/// their brake lights on, both, or a ticking clock when no cause is known -
/// so the reason lands before the sentence is read. It also says when they
/// now expect to arrive, from the same live estimate.
///
/// The words that carry the facts are unchanged, on purpose: "Running late",
/// "About 15 minutes behind because of bad weather.", and nothing about
/// traffic or weather when the data did not show either.
///
/// ## Why the cause is sometimes missing
///
/// `delay_reason` is null unless the sampled traffic or weather actually
/// supported the claim (see `eta_sampler.ts`). A technician who is simply
/// behind gets no excuse invented on their behalf, so this says "behind the
/// original estimate" and stops there - and the picture is a clock, not a
/// storm.
///
/// ## Why "about 15 minutes"
///
/// The estimate is straight-line distance over a sampled speed, rounded to
/// five minutes by [JobTracking.delayLabel]. A precise-sounding arrival time
/// that slips again reads as a lie; "about" is what the method can support.
///
/// ## Why the picture stops
///
/// It plays three cycles and holds still. A pop-up is read once; one that
/// keeps moving after it has been read is noise.
class DelayAlertDialog extends StatelessWidget {
  const DelayAlertDialog({
    super.key,
    required this.tracking,
    this.offerTracking = false,
    this.clientTrip = false,
  });

  final JobTracking tracking;
  final bool offerTracking;

  /// The client is the one travelling, and the technician is being told.
  final bool clientTrip;

  static const int _cycles = 3;

  IconData get _icon => switch (tracking.delayReason) {
    'weather' || 'both' => Icons.thunderstorm_rounded,
    'traffic' => Icons.traffic_rounded,
    _ => Icons.schedule_rounded,
  };

  /// The chip under the headline. No mention of traffic or weather unless
  /// the server attributed the delay to them.
  String get _causeChip => switch (tracking.delayReason) {
    'weather' => 'Bad weather on the way',
    'traffic' => 'Heavy traffic on the way',
    'both' => 'Traffic and weather',
    _ => 'Behind the first estimate',
  };

  String get _headline {
    final String behind = tracking.delayLabel ?? 'behind the estimate';
    final String sentence = behind[0].toUpperCase() + behind.substring(1);
    final String? cause = tracking.delayReasonLabel;
    return cause == null
        ? '$sentence the original estimate.'
        : '$sentence because of $cause.';
  }

  @override
  Widget build(BuildContext context) {
    final bool reduced = AppMotion.reduced(context);
    final String? newEta = TripConditions.of(tracking).etaLabel;

    final Widget body = Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSizes.xl,
        vertical: AppSizes.xl,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.sheetRadius + 4),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _CauseHero(reason: tracking.delayReason, cycles: _cycles),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.lg,
                  AppSizes.lg,
                  AppSizes.lg,
                  AppSizes.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // Short enough for one line at 20: the longer "Your
                    // technician is running late" left "late" alone on a
                    // second line.
                    Text(
                      'Running late',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.title,
                    ),
                    const SizedBox(height: AppSizes.sm),
                    Center(
                      child: _CauseChip(icon: _icon, text: _causeChip),
                    ),
                    const SizedBox(height: AppSizes.md),
                    Text(
                      _headline,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyStrong,
                    ),
                    if (newEta != null) ...<Widget>[
                      const SizedBox(height: AppSizes.md),
                      _NewArrival(
                        label: clientTrip
                            ? 'Your client now arrives in'
                            : 'Now arriving in',
                        eta: newEta,
                      ),
                    ],
                    const SizedBox(height: AppSizes.md),
                    Text(
                      clientTrip
                          ? 'Your client is still on the way to the shop, and '
                                'their position on the map is live.'
                          : 'Your technician is still on the way, and their '
                                'position on the map is live. You can message '
                                'them from the tracking screen.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.caption,
                    ),
                    const SizedBox(height: AppSizes.lg),
                    if (offerTracking) ...<Widget>[
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(true),
                        icon: const Icon(Icons.near_me_rounded, size: 18),
                        label: const Text('See live map'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(
                            AppSizes.buttonHeight,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSizes.xs),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          minimumSize: const Size.fromHeight(
                            AppSizes.touchTarget,
                          ),
                        ),
                        child: const Text('Close'),
                      ),
                    ] else
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(
                            AppSizes.buttonHeight,
                          ),
                        ),
                        child: const Text('OK'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // A small spring in: it is news, not an alarm.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.88, end: 1),
      duration: reduced ? Duration.zero : AppMotion.slow,
      curve: AppMotion.playful,
      builder: (BuildContext context, double scale, Widget? child) =>
          Transform.scale(scale: scale, child: child),
      child: body,
    );
  }
}

/// The animated picture of the cause, on a warm band.
class _CauseHero extends StatelessWidget {
  const _CauseHero({required this.reason, required this.cycles});

  final String? reason;
  final int cycles;

  @override
  Widget build(BuildContext context) {
    final Widget picture = switch (reason) {
      'weather' => WeatherGlyph(
        level: WeatherLevel.bad,
        size: 84,
        cycles: cycles * 3, // rain is quick; three "beats" of it
      ),
      'traffic' => SizedBox(
        width: 200,
        child: TrafficFlow(
          level: TrafficLevel.heavy,
          height: 40,
          cycles: cycles,
        ),
      ),
      'both' => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          WeatherGlyph(level: WeatherLevel.bad, size: 70, cycles: cycles * 3),
          const SizedBox(width: AppSizes.md),
          SizedBox(
            width: 130,
            child: TrafficFlow(
              level: TrafficLevel.heavy,
              height: 34,
              cycles: cycles,
            ),
          ),
        ],
      ),
      _ => _TickingClock(size: 76, cycles: cycles),
    };

    return Container(
      height: 132,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[AppColors.warningSoft, AppColors.surface],
        ),
      ),
      child: ExcludeSemantics(child: picture),
    );
  }
}

class _CauseChip extends StatelessWidget {
  const _CauseChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: AppColors.warning),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: AppTextStyles.micro.copyWith(
                color: AppColors.warning,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Now arriving in · 35 min", the live estimate after the delay.
class _NewArrival extends StatelessWidget {
  const _NewArrival({required this.label, required this.eta});

  final String label;
  final String eta;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.schedule_rounded,
            size: 18,
            color: AppColors.primary,
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(child: Text(label, style: AppTextStyles.caption)),
          Text(
            eta,
            style: const TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// A clock whose minute hand sweeps on: "behind schedule", with no cause
/// claimed. Drawn, not an icon, and it plays [cycles] sweeps then rests.
class _TickingClock extends StatefulWidget {
  const _TickingClock({required this.size, required this.cycles});

  final double size;
  final int cycles;

  @override
  State<_TickingClock> createState() => _TickingClockState();
}

class _TickingClockState extends State<_TickingClock>
    with SingleTickerProviderStateMixin, GlyphLoop<_TickingClock> {
  @override
  int? get cycles => widget.cycles;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    play(
      period: const Duration(milliseconds: 1800),
      still: AppMotion.reduced(context),
      rest: 0.15,
    );
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: Size.square(widget.size),
      painter: _ClockPainter(loop),
    ),
  );
}

class _ClockPainter extends CustomPainter {
  _ClockPainter(this.t) : super(repaint: t);

  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = AppColors.surface);
    canvas.drawCircle(
      c,
      r - 2,
      Paint()
        ..color = AppColors.warning
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    final Paint tick = Paint()
      ..color = AppColors.warning.withValues(alpha: 0.5)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 12; i++) {
      final double a = i * math.pi / 6;
      final Offset d = Offset(math.sin(a), -math.cos(a));
      canvas.drawLine(c + d * (r * 0.72), c + d * (r * 0.84), tick);
    }
    final Paint hand = Paint()
      ..color = AppColors.textPrimary
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    // Hour hand fixed; the minute hand sweeps a full turn per cycle.
    canvas.drawLine(c, c + const Offset(0.36, -0.25) * r, hand);
    final double a = t.value * 2 * math.pi;
    canvas.drawLine(
      c,
      c + Offset(math.sin(a), -math.cos(a)) * (r * 0.62),
      hand,
    );
    canvas.drawCircle(c, 4, Paint()..color = AppColors.textPrimary);
  }

  @override
  bool shouldRepaint(_ClockPainter old) => false;
}
