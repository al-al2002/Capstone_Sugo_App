import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_empty_state.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_app_bar.dart';
import '../../../core/widgets/sugo_skeleton.dart';
import '../../rb_cars/models/job.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../models/job_tracking.dart';
import '../services/tracking_service.dart';
import '../widgets/return_method_card.dart';
import '../widgets/route_map_card.dart';

/// The technician's side of a pickup or delivery.
///
/// Two responsibilities, deliberately separate:
///
/// * **Sharing position.** A toggle starts a `geolocator` stream and pushes
///   each fix to `job_tracking`. It is opt-in per trip rather than always-on,
///   because continuous background location is a serious thing to take from
///   someone and they should be able to see exactly when it is running.
/// * **Advancing the stage.** One button moves the job to the next stage, which
///   is what the client's timeline reads.
///
/// The location stream is cancelled in [dispose] and whenever the toggle goes
/// off, so leaving this screen stops the tracking rather than quietly draining
/// the battery for the rest of the day.
class TechnicianDeliveryScreen extends StatefulWidget {
  const TechnicianDeliveryScreen({super.key, required this.job});

  final Job job;

  @override
  State<TechnicianDeliveryScreen> createState() =>
      _TechnicianDeliveryScreenState();
}

class _TechnicianDeliveryScreenState extends State<TechnicianDeliveryScreen> {
  final TrackingService _service = TrackingService();

  StreamSubscription<Position>? _positions;

  /// When the ETA was last resampled, so the position stream can drive it
  /// without calling TomTom on every fix. The server enforces its own floor
  /// too - this only avoids the wasted round trip.
  DateTime? _lastEtaSample;
  JobTracking? _tracking;

  /// What the client asked for, or null while they have not answered.
  ///
  /// The technician does not choose this - since the return-method work on
  /// 2026-09-23 the fork after the repair belongs to the client, and this
  /// screen only reports what they picked. Null is not the same as delivery:
  /// it means nobody has said, and the screen says so.
  ReturnMethod? _returnChoice;

  /// What will actually happen, which is delivery until told otherwise. The
  /// database enforces the same default.
  ReturnMethod get _returnMethod => _returnChoice ?? ReturnMethod.delivery;

  bool _isLoading = true;
  bool _isSharing = false;
  bool _isBusy = false;
  String? _error;
  int _fixesSent = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // Stopping the stream here is what guarantees location sharing cannot
    // outlive the screen.
    _positions?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // `start` resumes: it returns an existing row untouched and only
      // inserts when there is none. Re-entering this screen must never move
      // the job back to the first stage - the client is watching the same row.
      final JobTracking tracking = await _service.start(widget.job.id);
      // Never throws - an unreadable choice reads as "not chosen".
      final ReturnMethod? choice = await _service.returnChoice(widget.job.id);
      if (!mounted) return;
      setState(() {
        _tracking = tracking;
        _returnChoice = choice;
        _isLoading = false;
      });
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure.message;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleSharing(bool value) async {
    if (!value) {
      await _positions?.cancel();
      _positions = null;
      setState(() => _isSharing = false);
      return;
    }

    final LocationReadiness readiness = await _service.prepareLocation();
    if (!mounted) return;

    if (!readiness.isReady) {
      UiFeedback.showError(context, readiness.reason!);
      return;
    }

    _positions = _service.positionStream().listen(
      (Position position) async {
        await _service.pushPosition(widget.job.id, position);
        // Piggy-backs on the position stream rather than running a timer of
        // its own: a stationary vehicle sends no fixes, so there is nothing to
        // re-estimate, and a timer would keep sampling traffic for a van that
        // has not moved.
        unawaited(_maybeSampleEta());
        if (!mounted) return;
        setState(() {
          _fixesSent += 1;
          _tracking = _tracking == null
              ? null
              : JobTracking(
                  id: _tracking!.id,
                  jobId: _tracking!.jobId,
                  technicianId: _tracking!.technicianId,
                  stage: _tracking!.stage,
                  latitude: position.latitude,
                  longitude: position.longitude,
                  accuracyM: position.accuracy,
                  heading: position.heading,
                  note: _tracking!.note,
                  startedAt: _tracking!.startedAt,
                  updatedAt: DateTime.now(),
                );
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        UiFeedback.showError(context, 'Lost the location signal.');
      },
    );

    setState(() => _isSharing = true);
  }

  /// Moves to [next]. Taken as an argument rather than read from the current
  /// stage, because `in_repair` has two exits and only the technician knows
  /// which one the client agreed to.
  Future<void> _advance(TrackingStage next) async {
    final JobTracking? current = _tracking;
    if (current == null || _isBusy) return;
    if (!current.stage.nextOptions.contains(next)) return;

    setState(() => _isBusy = true);

    try {
      final JobTracking updated = await _service.setStage(widget.job.id, next);
      if (!mounted) return;
      setState(() => _tracking = updated);

      // Nothing is moving during the repair or after delivery, so stop the
      // stream rather than reporting a parked van for hours.
      if (!next.showsMap && _isSharing) {
        await _toggleSharing(false);
      }

      if (!mounted) return;
      UiFeedback.showSuccess(context, 'Updated to "${next.label}".');
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      UiFeedback.showError(context, failure.message);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  /// Button wording for moving to [stage].
  ///
  /// The post-repair stages have to read as *reports*, not as decisions. The
  /// technician is no longer choosing between delivering and holding the unit
  /// - the client chose - so "Deliver it to the client" would offer an option
  /// that is not theirs to take. "Start the delivery" says what the button
  /// does: it begins the trip the client asked for.
  String _actionLabel(TrackingStage stage) => switch (stage) {
    TrackingStage.outForDelivery => 'Start the delivery',
    TrackingStage.readyForCollection => 'Mark it ready for collection',
    // Ending a collection is the client walking out with it, not a drop-off.
    TrackingStage.delivered
        when _tracking?.stage == TrackingStage.readyForCollection =>
      'The client has collected it',
    _ => 'Mark as "${stage.label}"',
  };

  /// Resamples the ETA at most once per [TrackingService.etaSampleInterval].
  ///
  /// Deliberately fire-and-forget. The delay it detects is delivered to the
  /// client through the realtime row, not through this screen, so nothing here
  /// waits on it and a failure changes nothing the technician can see.
  Future<void> _maybeSampleEta() async {
    final DateTime now = DateTime.now();
    final DateTime? last = _lastEtaSample;
    if (last != null &&
        now.difference(last) < TrackingService.etaSampleInterval) {
      return;
    }
    _lastEtaSample = now;
    await _service.sampleEta(widget.job.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const SugoAppBar(title: 'Pickup and delivery'),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_isLoading) {
      // Shaped like the stage card and the steps that are coming, so the
      // screen does not jump when they land.
      return const Padding(
        padding: EdgeInsets.all(AppSizes.screenPadding),
        child: SugoSkeletonList(count: 3, showAvatar: false),
      );
    }

    final JobTracking? tracking = _tracking;

    if (tracking == null) {
      return ListView(
        padding: const EdgeInsets.all(AppSizes.screenPadding),
        children: <Widget>[
          const SizedBox(height: AppSizes.xxl),
          SugoEmptyState.error(
            title: 'Could not start tracking',
            message: _error ?? 'Could not start tracking.',
            onAction: _load,
          ),
        ],
      );
    }

    final TrackingStage stage = tracking.stage;
    final bool clientCollects = _returnMethod == ReturnMethod.clientPickup;

    // After the repair the enum offers two exits - deliver it, or hold it for
    // collection - and this screen keeps exactly one of them: the one the
    // client asked for.
    //
    // It used to offer both, which made the technician the decider. That is
    // the wrong person: they cannot know whether somebody can get to the shop
    // on a weekday, and a unit marked "ready for collection" for a client who
    // was expecting it at their door is a wasted week. The client chooses on
    // their own tracking screen; the technician is told, and carries it out.
    final List<TrackingStage> options = stage.nextOptions
        .where((TrackingStage next) {
          if (!stage.asksReturnChoice) return true;
          return clientCollects
              ? next == TrackingStage.readyForCollection
              : next == TrackingStage.outForDelivery;
        })
        .toList(growable: false);

    final bool travels = options.any((TrackingStage s) => s.showsMap);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPadding,
        AppSizes.lg,
        AppSizes.screenPadding,
        AppSizes.xxl,
      ),
      children: <Widget>[
        _JourneyCard(stage: stage),
        const SizedBox(height: AppSizes.lg),

        // What happens after the bench, and who said so. Shown from the
        // repair onwards, because that is when the client is asked - before
        // it, there is nothing to report.
        if (!stage.isFinished && !stage.isInboundLeg) ...<Widget>[
          if (clientCollects)
            const ClientPickupBanner()
          else
            _DeliveryPlanCard(
              job: widget.job,
              chosen: _returnChoice == ReturnMethod.delivery,
              underway: stage.isOutboundLeg,
            ),
          const SizedBox(height: AppSizes.lg),
        ],

        _SharingCard(
          isSharing: _isSharing,
          stageNeedsMap: stage.showsMap,
          fixesSent: _fixesSent,
          tracking: tracking,
          onChanged: _toggleSharing,
        ),

        const SizedBox(height: AppSizes.lg),
        SugoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('The job', style: AppTextStyles.label),
              const SizedBox(height: AppSizes.sm),
              Row(
                children: <Widget>[
                  Icon(
                    widget.job.deviceType.icon,
                    size: 19,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(
                    child: Text(
                      widget.job.title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.job.hasLocation) ...<Widget>[
                const SizedBox(height: AppSizes.sm),
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.place_rounded,
                      size: 17,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: AppSizes.sm),
                    Expanded(
                      child: Text(
                        'Client at ${widget.job.locationLabel}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: AppSizes.xl),
        if (options.isNotEmpty) ...<Widget>[
          // A travelling stage with the location switch off is a promise the
          // app cannot keep: the client is shown "heading to the shop" and a
          // map with nothing moving on it, which reads as a stalled technician
          // rather than as a missing permission. So the stage cannot be
          // advanced into travel until sharing is actually on.
          //
          // Stages that show no map - the bench - are unaffected: nothing is
          // moving, so there is nothing to share.
          if (travels && !_isSharing) ...<Widget>[
            Container(
              padding: const EdgeInsets.all(AppSizes.md),
              decoration: BoxDecoration(
                color: AppColors.warningSoft,
                borderRadius: BorderRadius.circular(AppSizes.tileRadius),
                border: Border.all(color: AppColors.warning),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.location_off_rounded,
                    size: 18,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(
                    child: Text(
                      // Only reachable on a leg that actually travels: the
                      // post-repair fork is now filtered down to the client's
                      // own choice, so a technician whose client is collecting
                      // the unit never sees a location warning about a trip
                      // they are not making.
                      'Turn on your location first. The client needs to see '
                      'where their appliance is once you mark this stage.',
                      style: AppTextStyles.caption.copyWith(
                        fontSize: 12,
                        height: 1.35,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSizes.md),
          ],
          // In practice this is always one button now - the post-repair fork
          // is filtered to the client's choice above. The loop stays because
          // the transition graph is the enum's to define, not this screen's:
          // if a stage ever gains a second exit that really is the
          // technician's to pick, it renders rather than silently vanishing.
          for (int i = 0; i < options.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: AppSizes.sm),
            if (i == 0)
              PrimaryButton(
                label: _actionLabel(options[i]),
                isLoading: _isBusy,
                onPressed: (options[i].showsMap && !_isSharing)
                    ? null
                    : () => _advance(options[i]),
              )
            else
              SizedBox(
                width: double.infinity,
                height: AppSizes.buttonHeight,
                child: OutlinedButton(
                  onPressed: _isBusy || (options[i].showsMap && !_isSharing)
                      ? null
                      : () => _advance(options[i]),
                  child: Text(_actionLabel(options[i])),
                ),
              ),
          ],
        ] else
          Container(
            padding: const EdgeInsets.all(AppSizes.lg),
            decoration: BoxDecoration(
              color: AppColors.successSoft,
              borderRadius: BorderRadius.circular(AppSizes.tileRadius),
              border: Border.all(
                color: AppColors.success.withValues(alpha: 0.25),
              ),
            ),
            child: const Row(
              children: <Widget>[
                Icon(
                  Icons.check_circle_rounded,
                  size: 20,
                  color: AppColors.success,
                ),
                SizedBox(width: AppSizes.md),
                Expanded(
                  child: Text(
                    'Delivered. Close the job from your dashboard to record '
                    'the outcome.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSizes.sm),
        Text(
          'The client sees this stage and your position on their tracking '
          'screen.',
          textAlign: TextAlign.center,
          style: AppTextStyles.caption.copyWith(fontSize: 12),
        ),
      ],
    );
  }
}

/// "The client wants it delivered" - and the way back to them.
///
/// ## Why the route lives here
///
/// A pickup job ends with a drive the app never used to help with: `job-route`
/// refused anything that was not a home visit, so the technician taking a
/// repaired laptop back had a pin on a card and nothing else. It now routes
/// both legs of a pickup job, and this is where the return leg is offered -
/// on the screen the technician already has open while they load the van.
///
/// ## Why it distinguishes "chosen" from "not chosen"
///
/// No row in `job_return_preferences` means delivery, because that is the
/// default the database applies. But "they asked you to deliver it" and
/// "nobody has said, so it is a delivery" are different facts, and only one of
/// them is something the client has committed to. Saying which is which is
/// what stops a technician driving across town on an assumption.
class _DeliveryPlanCard extends StatelessWidget {
  const _DeliveryPlanCard({
    required this.job,
    required this.chosen,
    required this.underway,
  });

  final Job job;

  /// True when the client explicitly asked for a delivery.
  final bool chosen;

  /// True once the unit is out for delivery.
  final bool underway;

  @override
  Widget build(BuildContext context) {
    return SugoCard(
      pressable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppSizes.radius),
                ),
                child: const Icon(
                  Icons.delivery_dining_rounded,
                  size: 20,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      underway
                          ? 'Taking it back to the client'
                          : chosen
                          ? 'The client asked for a delivery'
                          : 'Delivery, unless the client says otherwise',
                      style: AppTextStyles.bodyStrong.copyWith(fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      underway
                          ? 'They can follow you on their tracking screen '
                                'while your location is on.'
                          : chosen
                          ? 'They chose this on their tracking screen. Bring '
                                'it back when it is ready.'
                          : 'They have not chosen yet. Delivery is what '
                                'happens by default, and they can still switch '
                                'to collecting it while you are working on it.',
                      style: AppTextStyles.caption.copyWith(height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (job.hasLocation) ...<Widget>[
            const SizedBox(height: AppSizes.md),
            RouteMapCard(
              jobId: job.id,
              latitude: job.latitude!,
              longitude: job.longitude!,
              title: 'Client address',
              address: job.locationLabel,
            ),
          ] else ...<Widget>[
            const SizedBox(height: AppSizes.md),
            Text(
              'This job has no pinned address, so there is no route to draw. '
              'Message the client to agree where to meet.',
              style: AppTextStyles.caption.copyWith(height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}

class _SharingCard extends StatelessWidget {
  const _SharingCard({
    required this.isSharing,
    required this.stageNeedsMap,
    required this.fixesSent,
    required this.tracking,
    required this.onChanged,
  });

  final bool isSharing;
  final bool stageNeedsMap;
  final int fixesSent;
  final JobTracking tracking;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SugoCard(
      borderColor: isSharing ? AppColors.success.withValues(alpha: 0.4) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSharing ? AppColors.successSoft : AppColors.divider,
                  borderRadius: BorderRadius.circular(AppSizes.radius),
                ),
                child: Icon(
                  isSharing
                      ? Icons.location_on_rounded
                      : Icons.location_off_rounded,
                  size: 20,
                  color: isSharing ? AppColors.success : AppColors.hint,
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      isSharing ? 'Sharing your location' : 'Location off',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      isSharing
                          ? '$fixesSent update${fixesSent == 1 ? '' : 's'} sent'
                          : 'The client cannot see where you are',
                      style: AppTextStyles.caption.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              Switch(
                value: isSharing,
                onChanged: onChanged,
                activeThumbColor: Colors.white,
                activeTrackColor: AppColors.success,
              ),
            ],
          ),
          if (!stageNeedsMap) ...<Widget>[
            const SizedBox(height: AppSizes.md),
            Text(
              'Nothing is moving at this stage, so the client is not shown a '
              'map. You can leave this off until the next leg.',
              style: AppTextStyles.caption.copyWith(
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ] else if (!isSharing) ...<Widget>[
            const SizedBox(height: AppSizes.md),
            Text(
              'Turn this on while you are travelling. It stops automatically '
              'when you leave this screen.',
              style: AppTextStyles.caption.copyWith(
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Where the unit is in its whole round trip, not just the current stage.
///
/// ## Why the whole journey
///
/// The screen used to show one card: the current stage and the words "Current
/// stage". A technician mid-job could see where they were but not how much
/// was left or what came next - and on a pickup job that crosses a day or two,
/// "what do I do after this?" is the question they actually open the screen
/// with.
///
/// So the current stage stays the hero, and underneath it the full route is
/// drawn as a stepper: finished stages ticked, the current one lit, the rest
/// waiting. The route comes from `TrackingStage.timelineFor`, the same one the
/// client's tracking screen uses, so both people are looking at the same map
/// of the job.
class _JourneyCard extends StatelessWidget {
  const _JourneyCard({required this.stage});

  final TrackingStage stage;

  @override
  Widget build(BuildContext context) {
    final List<TrackingStage> route = TrackingStage.timelineFor(stage);
    final int current = route.indexOf(stage);

    return SugoCard(
      padding: const EdgeInsets.all(AppSizes.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // ---------------------------------------------------------- hero
          Row(
            children: <Widget>[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: stage.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSizes.radius),
                ),
                child: Icon(stage.icon, size: 26, color: stage.color),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      current < 0
                          ? 'Current stage'
                          : 'Stage ${current + 1} of ${route.length}',
                      style: AppTextStyles.overline.copyWith(
                        color: stage.color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(stage.label, style: AppTextStyles.title),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          // Overall progress, so "how much is left" is answered at a glance
          // before the list below is read.
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSizes.pillRadius),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: 0,
                end: current < 0 ? 0 : (current + 1) / route.length,
              ),
              duration: AppMotion.slow,
              curve: AppMotion.emphasized,
              builder: (BuildContext context, double value, Widget? _) =>
                  LinearProgressIndicator(
                    value: value,
                    minHeight: 6,
                    backgroundColor: AppColors.divider,
                    color: stage.color,
                  ),
            ),
          ),
          const SizedBox(height: AppSizes.lg),

          // ------------------------------------------------------- stepper
          for (int i = 0; i < route.length; i++)
            _JourneyStep(
              stage: route[i],
              done: current >= 0 && i < current,
              active: i == current,
              isLast: i == route.length - 1,
            ),
        ],
      ),
    );
  }
}

class _JourneyStep extends StatelessWidget {
  const _JourneyStep({
    required this.stage,
    required this.done,
    required this.active,
    required this.isLast,
  });

  final TrackingStage stage;
  final bool done;
  final bool active;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final Color tone = done
        ? AppColors.success
        : active
        ? stage.color
        : AppColors.hint;

    return IntrinsicHeight(
      // Bounded by IntrinsicHeight, so the connector can stretch to the row's
      // height without handing an unbounded constraint to anything - the
      // mistake that broke the Community feed card.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: 26,
            child: Column(
              children: <Widget>[
                AnimatedContainer(
                  duration: AppMotion.base,
                  curve: AppMotion.standard,
                  width: active ? 24 : 20,
                  height: active ? 24 : 20,
                  decoration: BoxDecoration(
                    color: done || active ? tone : AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: tone, width: 2),
                  ),
                  child: Icon(
                    done ? Icons.check_rounded : stage.icon,
                    size: active ? 13 : 11,
                    color: done || active ? Colors.white : tone,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: done ? AppColors.success : AppColors.divider,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSizes.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    stage.label,
                    style: AppTextStyles.titleSmall.copyWith(
                      fontSize: 13,
                      color: done || active
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                  // Only the current step explains itself. Six blurbs at once
                  // is a wall of text; one is a caption.
                  if (active) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(stage.blurb, style: AppTextStyles.micro),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
