import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/job_tracking.dart';
import '../models/trip_conditions.dart';
import '../services/tracking_service.dart';
import 'condition_glyphs.dart';

/// "Arriving in 20 min · Weather is good and traffic is light" - the trip card
/// on home-service and shop-pickup legs, for the client AND the technician
/// (2026-11-17).
///
/// ## One source for everything on it
///
/// The countdown, the weather, the traffic and the delay all come from one
/// `job_tracking` row, written by the server's ETA sampler from a single
/// fetch (migration 20261117000005). So the card cannot say "traffic is
/// light" while the delay strip says "delayed by heavy traffic": they are
/// the same reading.
///
/// ## Layout, top to bottom
///
/// 1. A gradient band with the big countdown and a LIVE pill. It warms from
///    navy to amber when the trip runs late, so lateness reads from across
///    the room before a word is read.
/// 2. Two tiles, weather and traffic, each with an animated picture whose
///    motion IS the reading (see `condition_glyphs.dart`).
/// 3. The summary sentence.
/// 4. When late: a strip with how late and, only if the data shows it, why.
///
/// ## Why the technician gets a strip and not a pop-up
///
/// They are driving. A modal dialog over the road is a distraction at
/// exactly the wrong moment, so their delay notice stays inside the card.
/// The client, who is waiting, gets the pop-up (`delay_alert_dialog.dart`).
class TripConditionsCard extends StatefulWidget {
  const TripConditionsCard({
    super.key,
    required this.tracking,
    required this.viewer,
    this.distanceKm,
    this.clock,
  });

  final JobTracking tracking;
  final TripViewer viewer;

  /// Straight-line distance left, when the screen knows it.
  final double? distanceKm;

  /// For tests: what "now" is.
  final DateTime Function()? clock;

  @override
  State<TripConditionsCard> createState() => _TripConditionsCardState();
}

class _TripConditionsCardState extends State<TripConditionsCard> {
  /// The countdown moves on its own between samples (the server samples about
  /// every 90 s), so the card re-reads the clock this often.
  static const Duration _tick = Duration(seconds: 20);

  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(_tick, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TripConditions c = TripConditions.of(
      widget.tracking,
      now: widget.clock?.call(),
    );
    final bool late = widget.tracking.isDelayed;
    final bool reduced = AppMotion.reduced(context);

    final Widget card = AnimatedContainer(
      duration: AppMotion.base,
      curve: AppMotion.standard,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(
          color: late
              ? AppColors.warning.withValues(alpha: 0.55)
              : AppColors.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        // Content height, never stretched to fill a fixed-height parent.
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _EtaBand(
            conditions: c,
            viewer: widget.viewer,
            late: late,
            live: widget.tracking.isLive,
            distanceKm: widget.distanceKm,
          ),
          Padding(
            padding: const EdgeInsets.all(AppSizes.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(child: _WeatherTile(conditions: c)),
                      const SizedBox(width: AppSizes.sm),
                      Expanded(child: _TrafficTile(conditions: c)),
                    ],
                  ),
                ),
                _SummaryLine(conditions: c),
                AnimatedSize(
                  duration: AppMotion.base,
                  curve: AppMotion.standard,
                  alignment: Alignment.topCenter,
                  child: late
                      ? Padding(
                          padding: const EdgeInsets.only(top: AppSizes.sm),
                          child: _DelayStrip(
                            tracking: widget.tracking,
                            viewer: widget.viewer,
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // A short rise-in on first appearance; instant under reduced motion.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: reduced ? Duration.zero : AppMotion.slow,
      curve: AppMotion.emphasized,
      builder: (BuildContext context, double v, Widget? child) => Opacity(
        opacity: v.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, (1 - v) * 14),
          child: child,
        ),
      ),
      child: Semantics(container: true, label: _spoken(c, late), child: card),
    );
  }

  /// One sentence for a screen reader, instead of a dozen fragments.
  String _spoken(TripConditions c, bool late) {
    final String eta = c.etaLabel == null
        ? 'Arrival time is being worked out.'
        : '${c.arrivalTitle(widget.viewer)} ${c.etaLabel}.';
    final String delay = late
        ? ' Running ${widget.tracking.delayLabel ?? 'late'}'
              '${widget.tracking.delayReasonLabel == null ? '.' : ' because of ${widget.tracking.delayReasonLabel}.'}'
        : '';
    return '$eta ${c.summary ?? ''}$delay';
  }
}

// ------------------------------------------------------------------ the band

class _EtaBand extends StatelessWidget {
  const _EtaBand({
    required this.conditions,
    required this.viewer,
    required this.late,
    required this.live,
    required this.distanceKm,
  });

  final TripConditions conditions;
  final TripViewer viewer;
  final bool late;
  final bool live;
  final double? distanceKm;

  @override
  Widget build(BuildContext context) {
    final String? eta = conditions.etaLabel;
    final List<String> facts = <String>[
      conditions.destinationFor(viewer),
      if (distanceKm != null)
        distanceKm! < 1
            ? '${(distanceKm! * 1000).round()} m'
            : '${distanceKm!.toStringAsFixed(1)} km',
      if (conditions.freshness != null) conditions.freshness!,
    ];

    // Navy-to-blue on time, amber when late, cross-faded rather than
    // switched so the change is noticed rather than jarring.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: late ? 1 : 0),
      duration: AppMotion.slow,
      curve: AppMotion.standard,
      builder: (BuildContext context, double heat, Widget? child) {
        return Container(
          padding: const EdgeInsets.fromLTRB(
            AppSizes.md,
            AppSizes.md,
            AppSizes.md,
            AppSizes.md,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Color.lerp(AppColors.primary, AppColors.accentDark, heat)!,
                Color.lerp(AppColors.secondary, AppColors.accent, heat)!,
              ],
            ),
          ),
          child: child,
        );
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  conditions.arrivalTitle(viewer).toUpperCase(),
                  style: AppTextStyles.overline.copyWith(
                    color: Colors.white.withValues(alpha: 0.78),
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                _RollingText(
                  text: eta ?? 'Calculating…',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: eta == null ? 20 : 30,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  facts.join('  ·  '),
                  style: AppTextStyles.micro.copyWith(
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          _LivePill(live: live),
        ],
      ),
    );
  }
}

/// The countdown rolls up to its new value, like an odometer, instead of
/// blinking - a changed ETA is noticed without being alarming.
class _RollingText extends StatelessWidget {
  const _RollingText({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final bool reduced = AppMotion.reduced(context);
    return AnimatedSwitcher(
      duration: reduced ? Duration.zero : AppMotion.base,
      switchInCurve: AppMotion.emphasized,
      switchOutCurve: AppMotion.exit,
      layoutBuilder: (Widget? current, List<Widget> previous) => Stack(
        alignment: Alignment.centerLeft,
        children: <Widget>[...previous, if (current != null) current],
      ),
      transitionBuilder: (Widget child, Animation<double> a) {
        final bool incoming = child.key == ValueKey<String>(text);
        return ClipRect(
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(0, incoming ? 0.6 : -0.6),
              end: Offset.zero,
            ).animate(a),
            child: FadeTransition(opacity: a, child: child),
          ),
        );
      },
      child: Text(text, key: ValueKey<String>(text), style: style),
    );
  }
}

/// "LIVE" with a breathing dot while the position is fresh; "LAST SEEN"
/// when it has gone quiet, so an old dot is never presented as live.
class _LivePill extends StatefulWidget {
  const _LivePill({required this.live});

  final bool live;

  @override
  State<_LivePill> createState() => _LivePillState();
}

class _LivePillState extends State<_LivePill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_LivePill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.live != widget.live) _sync();
  }

  void _sync() {
    if (widget.live && !AppMotion.reduced(context)) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color dot = widget.live ? const Color(0xFF4ADE80) : AppColors.hint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 10,
            height: 10,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (BuildContext context, Widget? _) => Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  Transform.scale(
                    scale: 1 + _pulse.value * 1.3,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dot.withValues(alpha: 0.5 * (1 - _pulse.value)),
                      ),
                    ),
                  ),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dot,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            widget.live ? 'LIVE' : 'LAST SEEN',
            style: AppTextStyles.overline.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- the tiles

class _WeatherTile extends StatelessWidget {
  const _WeatherTile({required this.conditions});

  final TripConditions conditions;

  @override
  Widget build(BuildContext context) {
    final WeatherLevel? level = conditions.weather;
    final (Color tint, Color ink) = switch (level) {
      WeatherLevel.good => (AppColors.successSoft, AppColors.success),
      WeatherLevel.fair => (AppColors.primarySofter, AppColors.primary),
      WeatherLevel.bad => (AppColors.warningSoft, AppColors.warning),
      null => (AppColors.background, AppColors.textSecondary),
    };
    return _Tile(
      tint: tint,
      ink: ink,
      label: 'Weather',
      headline: level?.headline,
      detail: conditions.weatherDetail,
      sampled: conditions.sampled,
      picture: level == null
          ? const Icon(
              Icons.wb_cloudy_outlined,
              size: 26,
              color: AppColors.hint,
            )
          : WeatherGlyph(level: level, size: 34),
    );
  }
}

class _TrafficTile extends StatelessWidget {
  const _TrafficTile({required this.conditions});

  final TripConditions conditions;

  @override
  Widget build(BuildContext context) {
    final TrafficLevel? level = conditions.traffic;
    final (Color tint, Color ink) = switch (level) {
      TrafficLevel.clear ||
      TrafficLevel.light => (AppColors.successSoft, AppColors.success),
      TrafficLevel.moderate => (AppColors.warningSoft, AppColors.warning),
      TrafficLevel.heavy ||
      TrafficLevel.closed => (AppColors.errorSoft, AppColors.error),
      null => (AppColors.background, AppColors.textSecondary),
    };
    return _Tile(
      tint: tint,
      ink: ink,
      label: 'Traffic',
      headline: level?.headline,
      detail: conditions.trafficDetail,
      sampled: conditions.sampled,
      picture: level == null
          ? const Icon(Icons.traffic_outlined, size: 26, color: AppColors.hint)
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: SizedBox(
                width: double.infinity,
                height: 24,
                child: TrafficFlow(level: level, height: 24),
              ),
            ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.tint,
    required this.ink,
    required this.label,
    required this.headline,
    required this.detail,
    required this.sampled,
    required this.picture,
  });

  final Color tint;
  final Color ink;
  final String label;
  final String? headline;
  final String? detail;
  final bool sampled;
  final Widget picture;

  @override
  Widget build(BuildContext context) {
    // Before the first sample: "Checking…". After it, a missing reading means
    // the provider was down: "Not available", never a guess.
    final String shown = headline ?? (sampled ? 'Not available' : 'Checking…');
    return AnimatedContainer(
      duration: AppMotion.base,
      curve: AppMotion.standard,
      padding: const EdgeInsets.all(AppSizes.sm + 2),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            height: 34,
            child: Align(alignment: Alignment.centerLeft, child: picture),
          ),
          const SizedBox(height: AppSizes.xs),
          Text(label, style: AppTextStyles.micro),
          AnimatedSwitcher(
            duration: AppMotion.base,
            child: Text(
              shown,
              key: ValueKey<String>(shown),
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: headline == null ? AppColors.textSecondary : ink,
              ),
            ),
          ),
          if (detail != null)
            Text(
              detail!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.micro.copyWith(height: 1.3),
            ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------- summary, delay

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.conditions});

  final TripConditions conditions;

  @override
  Widget build(BuildContext context) {
    final String? summary = conditions.summary;
    if (summary == null || conditions.tracking.isDelayed) {
      return const SizedBox.shrink();
    }
    final bool clear = conditions.looksClear;
    return Padding(
      padding: const EdgeInsets.only(top: AppSizes.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            clear ? Icons.check_circle_rounded : Icons.info_rounded,
            size: 16,
            color: clear ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              clear
                  ? '$summary On schedule.'
                  : '$summary It may take a little longer.',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// How late, and why only when the data shows why.
class _DelayStrip extends StatelessWidget {
  const _DelayStrip({required this.tracking, required this.viewer});

  final JobTracking tracking;
  final TripViewer viewer;

  @override
  Widget build(BuildContext context) {
    final String behind = tracking.delayLabel ?? 'behind the estimate';
    final String? cause = tracking.delayReasonLabel;
    final IconData icon = switch (tracking.delayReason) {
      'weather' || 'both' => Icons.thunderstorm_rounded,
      'traffic' => Icons.traffic_rounded,
      _ => Icons.schedule_rounded,
    };
    // The traveller is told the other side can see it; the one waiting is
    // told why (2026-11-17: on a client trip, the client is the traveller).
    final bool travelling = TripConditions.of(tracking).isTravelling(viewer);
    final String other = viewer == TripViewer.client ? 'technician' : 'client';
    final String detail = travelling
        ? (cause == null
              ? 'Behind your first estimate. Your $other can see this.'
              : 'Slowed by $cause. Your $other can see why.')
        : (cause == null
              ? 'Behind the first estimate. Their position is still live.'
              : 'Delayed by $cause. Their position is still live.');

    return Container(
      padding: const EdgeInsets.all(AppSizes.sm + 2),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Throb(child: Icon(icon, size: 20, color: AppColors.warning)),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Running $behind', style: AppTextStyles.bodyStrong),
                const SizedBox(height: 2),
                Text(detail, style: AppTextStyles.micro.copyWith(height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A slow, small scale pulse that draws the eye without flashing.
class _Throb extends StatefulWidget {
  const _Throb({required this.child});

  final Widget child;

  @override
  State<_Throb> createState() => _ThrobState();
}

class _ThrobState extends State<_Throb> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: Tween<double>(
      begin: 1,
      end: 1.14,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
    child: widget.child,
  );
}

// ------------------------------------------------------- technician, live

/// [TripConditionsCard] that keeps itself up to date from the live
/// `job_tracking` row, for the technician's trip screens.
///
/// Those screens drive the trip (start, arrive, share) but do not listen to
/// the row the SERVER writes - the ETA and the conditions. This subscribes
/// for as long as the card is on screen, so neither screen's own state
/// handling had to change. A failed subscription leaves the last row on
/// screen rather than an error: the card is information, not a control.
class LiveTripConditionsCard extends StatefulWidget {
  const LiveTripConditionsCard({
    super.key,
    required this.jobId,
    required this.initial,
    this.viewer = TripViewer.technician,
    this.service,
  });

  final String jobId;
  final JobTracking initial;
  final TripViewer viewer;

  /// The screen's own service, so a test's fake is used here too.
  final TrackingService? service;

  @override
  State<LiveTripConditionsCard> createState() => _LiveTripConditionsCardState();
}

class _LiveTripConditionsCardState extends State<LiveTripConditionsCard> {
  StreamSubscription<JobTracking?>? _live;
  late JobTracking _row = widget.initial;

  @override
  void initState() {
    super.initState();
    try {
      _live = (widget.service ?? TrackingService()).watch(widget.jobId).listen((
        JobTracking? row,
      ) {
        if (row != null && mounted) setState(() => _row = row);
      }, onError: (Object _) {});
    } catch (_) {
      // No live updates (offline, or a test without them): keep [initial].
    }
  }

  @override
  void didUpdateWidget(LiveTripConditionsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The screen moved the trip on itself (a new leg): take its row.
    if (widget.initial.stage != _row.stage) _row = widget.initial;
  }

  @override
  void dispose() {
    _live?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      TripConditionsCard(tracking: _row, viewer: widget.viewer);
}
