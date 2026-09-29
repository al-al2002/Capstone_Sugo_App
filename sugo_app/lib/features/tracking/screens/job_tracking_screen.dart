import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_elevation.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/contact_launcher.dart';
import '../../../core/widgets/sugo_avatar.dart';
import '../../../core/widgets/sugo_button.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_empty_state.dart';
import '../../../core/widgets/sugo_icon_button.dart';
import '../../../core/widgets/sugo_sheet.dart';
import '../../../core/widgets/sugo_status_badge.dart';
import '../../../core/widgets/sugo_timeline.dart';
import '../../../core/widgets/sugo_truck_drive.dart';
import '../../chat/screens/chat_thread_screen.dart';
import '../../rb_cars/models/job.dart';
import '../../rb_cars/models/technician.dart';
import '../models/job_tracking.dart';
import '../services/tracking_service.dart';
import '../services/delay_alerts.dart';
import '../widgets/collection_trip_panel.dart';
import '../widgets/delay_alert_dialog.dart';
import '../widgets/tracking_map.dart';
import '../widgets/weather_chip.dart';
import '../../rb_cars/models/technician_profile_details.dart';
import '../../rb_cars/services/technician_directory_service.dart';
import '../widgets/return_method_card.dart';
import '../widgets/route_map_card.dart';

/// What the client watches while their appliance is away.
///
/// ## The redesign: the map is the screen
///
/// Tracking used to be a scrolling list of cards with a 300px map card partway
/// down it. But a tracking screen has one job - *where is my technician* - and
/// a map in a box, below the fold, is a picture of that answer rather than the
/// answer itself.
///
/// The map is now full-bleed behind everything, and the detail lives in a
/// sheet the client can drag up for the timeline or down to see the road. That
/// is the pattern every delivery app uses, and it is not fashion: it keeps the
/// moving thing visible while you read about it.
///
/// Stages that have nothing to show on a map - on the bench, waiting at the
/// shop - keep the old scrolling layout, because a frozen pin for four hours
/// reads as a broken feed rather than as bench work in progress.
///
/// ## Two journeys, and where each leg is heading
///
/// A home visit (2026-09-29) is one trip: the technician drives to the client
/// and repairs it there. A rerouted job travels twice, and the destination
/// flips between its legs:
///
/// * **To the client** - the technician on the way (either journey), and the
///   repaired unit out for delivery. The destination is the client's address.
/// * **To the shop** - collected, returning to shop. The destination is the
///   workshop.
///
/// Getting that the wrong way round would draw a line to the wrong end of the
/// city, so [_destinationFor] is the one place that decides it. It used to pin
/// the workshop for "On the way to you" as well - see
/// [TrackingStage.headsToClient].
///
/// ## Running late
///
/// When the trip slips ten minutes past its first estimate, a pop-up says so
/// once ([maybeShowDelayAlert]); the banner in the sheet stays for as long as
/// it is true.
class JobTrackingScreen extends StatefulWidget {
  const JobTrackingScreen({super.key, required this.job, this.technician});

  final Job job;

  /// Used for the workshop pin and the contact row. Null when the snapshot was
  /// not passed through, in which case the screen fetches the public profile
  /// so the sheet can still name and call the technician.
  final Technician? technician;

  @override
  State<JobTrackingScreen> createState() => _JobTrackingScreenState();
}

class _JobTrackingScreenState extends State<JobTrackingScreen> {
  final TrackingService _service = TrackingService();
  final TechnicianDirectoryService _directory = TechnicianDirectoryService();

  late final Stream<JobTracking?> _stream = _service.watch(widget.job.id);

  Technician? _technician;
  bool _contactUnlocked = false;

  @override
  void initState() {
    super.initState();
    _technician = widget.technician;
    _loadTechnician();
  }

  /// The technician behind this booking, for the name, photo and phone number.
  ///
  /// Best effort: the map and the stages are the point of this screen, and a
  /// directory hiccup must not take them down with it.
  Future<void> _loadTechnician() async {
    final String? id = widget.job.assignedTechnicianId;
    if (id == null) return;
    try {
      final TechnicianProfile profile = await _directory.byId(id);
      if (!mounted) return;
      setState(() {
        _technician = profile.technician;
        _contactUnlocked = profile.contactUnlocked;
      });
    } catch (_) {
      // Keep whatever the caller passed in.
    }
  }

  TrackingJourney get _journey => TrackingJourney.of(widget.job.servicePath);

  /// Where the current leg is heading.
  LatLng? _destinationFor(TrackingStage stage) {
    if (stage.headsToClient) {
      // The technician coming to the client, or the unit coming back.
      if (!widget.job.hasLocation) return null;
      return LatLng(widget.job.latitude!, widget.job.longitude!);
    }

    // The rest heads to the workshop. Falls back to the technician's own
    // coordinates when no shop address is recorded.
    final Technician? tech = _technician;
    final double? lat = tech?.latitude;
    final double? lon = tech?.longitude;
    if (lat == null || lon == null) return null;
    return LatLng(lat, lon);
  }

  String _destinationLabel(TrackingStage stage) =>
      stage.headsToClient ? 'Your address' : 'Workshop';

  /// The delay pop-up, after this frame. Called on every update; it shows at
  /// most once per trip. No "see the map" button - the map is right here.
  void _maybeAlert(JobTracking tracking) {
    if (!DelayAlerts.isAlertable(tracking)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowDelayAlert(context, tracking);
    });
  }

  Future<void> _message() async {
    await openChatThread(
      context,
      jobId: widget.job.id,
      title: _technician?.displayName ?? 'Your technician',
      avatarUrl: _technician?.avatarUrl,
      subtitle: jobThreadSubtitle(
        widget.job.deviceType.wire,
        widget.job.problemSymptom,
        widget.job.status,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: StreamBuilder<JobTracking?>(
        stream: _stream,
        builder: (BuildContext context, AsyncSnapshot<JobTracking?> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _Framed(
              child: Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.hasError) {
            return _Framed(
              child: Padding(
                padding: const EdgeInsets.all(AppSizes.screenPadding),
                child: SugoEmptyState.error(
                  title: 'Tracking is unavailable',
                  message:
                      'We could not reach the tracking service. Check your '
                      'connection and try again.',
                  onAction: () => setState(() {}),
                ),
              ),
            );
          }

          final JobTracking? tracking = snapshot.data;
          final String? technicianId = widget.job.assignedTechnicianId;
          if (tracking != null) _maybeAlert(tracking);

          // A trip the technician has not set off on yet. The "how do you
          // want it back?" card used to sit here on a workshop repair, which
          // asked the question before the unit had even been collected - it
          // now waits for the bench. See `TrackingStage.asksReturnChoice`.
          if (tracking == null &&
              TrackingJourney.tracks(widget.job.servicePath) &&
              technicianId != null) {
            return _Framed(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.screenPadding,
                  AppSizes.lg,
                  AppSizes.screenPadding,
                  AppSizes.xxl,
                ),
                children: <Widget>[_NotStarted(journey: _journey)],
              ),
            );
          }

          if (tracking == null) {
            return _Framed(
              child: Padding(
                padding: const EdgeInsets.all(AppSizes.screenPadding),
                child: SugoEmptyState(
                  icon: Icons.home_repair_service_rounded,
                  title: 'Nothing to track',
                  message:
                      'There is no trip to follow for this booking. A map '
                      'appears here once a technician sets off.',
                ),
              ),
            );
          }

          // Map-first only while something is actually moving.
          if (tracking.stage.showsMap) {
            return _LiveTracking(
              job: widget.job,
              journey: _journey,
              tracking: tracking,
              technician: _technician,
              contactUnlocked: _contactUnlocked,
              destination: _destinationFor(tracking.stage),
              destinationLabel: _destinationLabel(tracking.stage),
              onMessage: _message,
            );
          }

          return _Framed(
            child: _StationaryBody(
              job: widget.job,
              journey: _journey,
              tracking: tracking,
              technician: _technician,
              contactUnlocked: _contactUnlocked,
              onMessage: _message,
            ),
          );
        },
      ),
    );
  }
}

/// A plain app-bar frame for the states that are not map-first.
class _Framed extends StatelessWidget {
  const _Framed({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.sm,
              AppSizes.sm,
              AppSizes.screenPadding,
              0,
            ),
            child: Row(
              children: <Widget>[
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                ),
                const SizedBox(width: AppSizes.xs),
                Text('Track your repair', style: AppTextStyles.title),
              ],
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// The map-first layout: a full-bleed map with a draggable detail sheet.
class _LiveTracking extends StatelessWidget {
  const _LiveTracking({
    required this.job,
    required this.journey,
    required this.tracking,
    required this.technician,
    required this.contactUnlocked,
    required this.destination,
    required this.destinationLabel,
    required this.onMessage,
  });

  final Job job;
  final TrackingJourney journey;
  final JobTracking tracking;
  final Technician? technician;
  final bool contactUnlocked;
  final LatLng? destination;
  final String destinationLabel;
  final Future<void> Function() onMessage;

  /// Straight-line distance to the destination, in kilometres.
  ///
  /// Straight-line, and the label says so, because that is what the data
  /// supports - the app does not pay for a routing call per position fix. A
  /// "2.3 km" that is really 4 km of one-way streets is a small lie; "2.3 km
  /// away" without claiming a driving distance is not.
  double? get _distanceKm {
    final LatLng? to = destination;
    if (to == null || !tracking.hasPosition) return null;
    return const Distance().as(
      LengthUnit.Kilometer,
      LatLng(tracking.latitude!, tracking.longitude!),
      to,
    );
  }

  String? get _etaLabel {
    final DateTime? eta = tracking.projectedArrivalAt;
    if (eta == null) return null;
    final int minutes = eta.difference(DateTime.now()).inMinutes;
    if (minutes <= 0) return 'Arriving now';
    if (minutes < 60) return '$minutes min';
    final int hours = minutes ~/ 60;
    return '${hours}h ${minutes % 60}m';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        // The map fills the screen; the sheet floats over its lower half.
        Positioned.fill(
          child: TrackingMap(
            tracking: tracking,
            destination: destination,
            destinationLabel: destinationLabel,
            destinationIcon: tracking.stage.headsToClient
                ? Icons.home_rounded
                : Icons.storefront_rounded,
            height: double.infinity,
            rounded: false,
            bottomInset: MediaQuery.sizeOf(context).height * 0.42,
          ),
        ),

        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.md),
            child: Row(
              children: <Widget>[
                SugoIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  tooltip: 'Back',
                  style: SugoIconButtonStyle.glass,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.md,
                    vertical: AppSizes.sm,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                    boxShadow: AppElevation.sm,
                  ),
                  child: Text(
                    job.reference,
                    style: AppTextStyles.micro.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        DraggableScrollableSheet(
          initialChildSize: 0.42,
          minChildSize: 0.26,
          maxChildSize: 0.92,
          builder: (BuildContext context, ScrollController controller) {
            return Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppSizes.sheetRadius),
                ),
                boxShadow: AppElevation.xl,
              ),
              clipBehavior: Clip.antiAlias,
              child: ListView(
                controller: controller,
                padding: EdgeInsets.zero,
                children: <Widget>[
                  const SugoSheetHandle(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSizes.screenPadding,
                      AppSizes.xs,
                      AppSizes.screenPadding,
                      AppSizes.xxl,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _StageHeader(tracking: tracking, journey: journey),
                        const SizedBox(height: AppSizes.md),
                        // The truck on its way - driving only while the
                        // position is live (2026-09-29).
                        SugoTruckDrive(
                          moving: tracking.isLive,
                          destinationIcon: tracking.stage.headsToClient
                              ? Icons.home_rounded
                              : Icons.storefront_rounded,
                        ),
                        const SizedBox(height: AppSizes.md),
                        _LiveFacts(
                          eta: _etaLabel,
                          distanceKm: _distanceKm,
                          tracking: tracking,
                        ),
                        if (tracking.isDelayed) ...<Widget>[
                          const SizedBox(height: AppSizes.md),
                          _DelayBanner(tracking: tracking),
                        ],
                        const SizedBox(height: AppSizes.lg),
                        _TechnicianRow(
                          technician: technician,
                          contactUnlocked: contactUnlocked,
                          onMessage: onMessage,
                        ),
                        WeatherChip(
                          jobId: tracking.jobId,
                          headsToClient: tracking.stage.headsToClient,
                        ),
                        // Only on the bench of a workshop repair. See
                        // `TrackingStage.asksReturnChoice` for why the
                        // question waits until the repair is actually in hand.
                        if (tracking.stage.asksReturnChoiceOn(journey))
                          ...<Widget>[
                          const SizedBox(height: AppSizes.lg),
                          ReturnMethodCard(
                            jobId: tracking.jobId,
                            technicianId: tracking.technicianId,
                            stage: tracking.stage,
                          ),
                        ],
                        const SizedBox(height: AppSizes.xl),
                        const SectionHeader(title: 'Progress'),
                        const SizedBox(height: AppSizes.lg),
                        SugoTimeline(
                          steps: trackingSteps(
                            tracking.stage,
                            journey: journey,
                          ),
                          compact: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// The non-map layout: on the bench, waiting at the shop, delivered.
class _StationaryBody extends StatelessWidget {
  const _StationaryBody({
    required this.job,
    required this.journey,
    required this.tracking,
    required this.technician,
    required this.contactUnlocked,
    required this.onMessage,
  });

  final Job job;
  final TrackingJourney journey;
  final JobTracking tracking;
  final Technician? technician;
  final bool contactUnlocked;
  final Future<void> Function() onMessage;

  @override
  Widget build(BuildContext context) {
    final TrackingStage stage = tracking.stage;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPadding,
        AppSizes.lg,
        AppSizes.screenPadding,
        AppSizes.xxl,
      ),
      children: <Widget>[
        SugoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _StageHeader(tracking: tracking, journey: journey),
              const SizedBox(height: AppSizes.lg),
              _TechnicianRow(
                technician: technician,
                contactUnlocked: contactUnlocked,
                onMessage: onMessage,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSizes.md),
        if (stage.isAwaitingCollection)
          _ReadyForCollection(
            jobId: tracking.jobId,
            technicianId: tracking.technicianId,
            tracking: tracking,
          )
        else
          _AtBench(stage: stage, journey: journey),
        const SizedBox(height: AppSizes.xl),
        const SectionHeader(title: 'Progress'),
        const SizedBox(height: AppSizes.md),
        SugoCard(
          child: SugoTimeline(steps: trackingSteps(stage, journey: journey)),
        ),
      ],
    );
  }
}

/// The stages of this job's journey, as timeline steps.
List<SugoTimelineStep> trackingSteps(
  TrackingStage current, {
  TrackingJourney journey = TrackingJourney.workshop,
}) {
  final List<TrackingStage> route = TrackingStage.timelineFor(
    current,
    journey: journey,
  );
  final int index = route.indexOf(current);

  return <SugoTimelineStep>[
    for (int i = 0; i < route.length; i++)
      SugoTimelineStep(
        title: route[i].labelOn(journey),
        icon: route[i].icon,
        state: i < index
            ? SugoStepState.done
            : i == index
            ? SugoStepState.current
            : SugoStepState.upcoming,
        subtitle: route[i].blurbOn(journey),
      ),
  ];
}

class _StageHeader extends StatelessWidget {
  const _StageHeader({required this.tracking, required this.journey});

  final JobTracking tracking;
  final TrackingJourney journey;

  @override
  Widget build(BuildContext context) {
    final TrackingStage stage = tracking.stage;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: stage.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppSizes.radius),
          ),
          child: Icon(stage.icon, size: 25, color: stage.color),
        ),
        const SizedBox(width: AppSizes.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(stage.labelOn(journey), style: AppTextStyles.title),
              const SizedBox(height: 2),
              Text(stage.blurbOn(journey), style: AppTextStyles.caption),
            ],
          ),
        ),
      ],
    );
  }
}

/// ETA, distance and freshness - the three numbers a waiting client wants.
class _LiveFacts extends StatelessWidget {
  const _LiveFacts({
    required this.eta,
    required this.distanceKm,
    required this.tracking,
  });

  final String? eta;
  final double? distanceKm;
  final JobTracking tracking;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        if (eta != null)
          Expanded(
            child: _FactTile(
              icon: Icons.schedule_rounded,
              label: 'Arriving in',
              value: eta!,
              emphasis: true,
            ),
          ),
        if (eta != null && distanceKm != null) const SizedBox(width: AppSizes.md),
        if (distanceKm != null)
          Expanded(
            child: _FactTile(
              icon: Icons.straighten_rounded,
              label: 'Straight-line',
              value: distanceKm! < 1
                  ? '${(distanceKm! * 1000).round()} m'
                  : '${distanceKm!.toStringAsFixed(1)} km',
            ),
          ),
        if (eta == null && distanceKm == null)
          Expanded(
            child: _FactTile(
              icon: Icons.my_location_rounded,
              label: 'Position',
              value: tracking.freshnessLabel,
            ),
          ),
      ],
    );
  }
}

class _FactTile extends StatelessWidget {
  const _FactTile({
    required this.icon,
    required this.label,
    required this.value,
    this.emphasis = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.md,
      ),
      decoration: BoxDecoration(
        color: emphasis ? AppColors.primarySoft : AppColors.background,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            icon,
            size: 18,
            color: emphasis ? AppColors.primary : AppColors.textSecondary,
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(label, style: AppTextStyles.micro),
                const SizedBox(height: 1),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleSmall.copyWith(
                    fontSize: 15,
                    color: emphasis ? AppColors.primary : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Who is carrying the job, and the two ways to reach them.
class _TechnicianRow extends StatelessWidget {
  const _TechnicianRow({
    required this.technician,
    required this.contactUnlocked,
    required this.onMessage,
  });

  final Technician? technician;
  final bool contactUnlocked;
  final Future<void> Function() onMessage;

  @override
  Widget build(BuildContext context) {
    final Technician? tech = technician;

    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
      ),
      child: Row(
        children: <Widget>[
          SugoAvatar(
            name: tech?.displayName,
            imageUrl: tech?.avatarUrl,
            size: 44,
            verified: tech?.isVerified ?? false,
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  tech?.displayName ?? 'Your technician',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleSmall,
                ),
                const SizedBox(height: 2),
                if (tech != null && tech.rating > 0)
                  Row(
                    children: <Widget>[
                      const Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${tech.rating.toStringAsFixed(1)} · '
                        '${tech.totalJobs} jobs',
                        style: AppTextStyles.micro,
                      ),
                    ],
                  )
                else
                  Text('Handling your repair', style: AppTextStyles.micro),
              ],
            ),
          ),
          SugoIconButton(
            icon: Icons.chat_bubble_outline_rounded,
            tooltip: 'Message',
            style: SugoIconButtonStyle.tonal,
            size: 40,
            onPressed: onMessage,
          ),
          const SizedBox(width: AppSizes.sm),
          SugoIconButton(
            icon: Icons.call_rounded,
            tooltip: contactUnlocked
                ? 'Call your technician'
                : 'Calling unlocks with a confirmed booking',
            style: contactUnlocked
                ? SugoIconButtonStyle.filled
                : SugoIconButtonStyle.surface,
            size: 40,
            iconColor: contactUnlocked ? null : AppColors.hint,
            onPressed: contactUnlocked && tech?.phone != null
                ? () => ContactLauncher.call(context, tech!.phone)
                : null,
          ),
        ],
      ),
    );
  }
}

/// Shown instead of the map while the repair itself is under way: on the
/// workshop bench, or at the client's home.
class _AtBench extends StatelessWidget {
  const _AtBench({required this.stage, required this.journey});

  final TrackingStage stage;
  final TrackingJourney journey;

  @override
  Widget build(BuildContext context) {
    final bool done = stage.isFinished;
    final bool atHome = journey == TrackingJourney.homeVisit;

    return Container(
      padding: const EdgeInsets.all(AppSizes.xl),
      decoration: BoxDecoration(
        color: done ? AppColors.successSoft : AppColors.accentSofter,
        borderRadius: BorderRadius.circular(AppSizes.panelRadius),
      ),
      child: Column(
        children: <Widget>[
          Icon(
            done ? Icons.verified_rounded : Icons.handyman_rounded,
            size: 34,
            color: done ? AppColors.success : AppColors.accentDark,
          ),
          const SizedBox(height: AppSizes.md),
          Text(
            done
                ? 'All done'
                : atHome
                ? 'Your technician is with you'
                : 'No map while it is on the bench',
            textAlign: TextAlign.center,
            style: AppTextStyles.titleSmall,
          ),
          const SizedBox(height: AppSizes.xs),
          Text(
            done
                ? 'Your appliance has been returned. Rate the job from your '
                      'bookings when you are ready.'
                : atHome
                ? 'They have arrived, so the map is closed. You will be asked '
                      'to rate the job once they mark it complete.'
                : 'Nothing is moving during the repair itself. The map comes '
                      'back when it heads out for delivery.',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }
}

/// Tells the client their technician is running behind, and why when we know.
///
/// ## Why the wording hedges
///
/// The delay comes from straight-line distance over a sampled traffic speed,
/// which is a real estimate but not a routed one. "About 15 minutes behind"
/// is what that method can honestly support; "arriving 14:37" is not, and a
/// precise-sounding time that slips again reads as a lie rather than as an
/// estimate.
///
/// ## Why the cause can be absent
///
/// `delayReason` is null unless the sampled traffic or weather actually
/// supported the claim. A technician who is simply running behind gets no
/// excuse invented on their behalf.
class _DelayBanner extends StatelessWidget {
  const _DelayBanner({required this.tracking});

  final JobTracking tracking;

  @override
  Widget build(BuildContext context) {
    final String? cause = tracking.delayReasonLabel;
    final String delay = tracking.delayLabel ?? 'running late';

    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.schedule_rounded,
            size: 18,
            color: AppColors.warning,
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Running $delay', style: AppTextStyles.bodyStrong),
                const SizedBox(height: 2),
                Text(
                  cause == null
                      ? 'Your technician is behind the original estimate. '
                            'Their position on the map is still live.'
                      : 'Delayed by $cause. Their position on the map is '
                            'still live.',
                  style: AppTextStyles.micro,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown once the repair is done and the client is collecting it themselves.
///
/// ## Why this is not `_AtBench`
///
/// Both stages hide the live map, so they used to share a card - which told a
/// client whose repair was FINISHED that "nothing is moving during the repair
/// itself" and that "the map comes back when it heads out for delivery".
/// Neither is true here: the work is done and no delivery is coming, because
/// they said they would come and get it.
///
/// ## Why it fetches
///
/// A client cannot read `technicians`, so the workshop location is not on any
/// row this screen already has. `technician_profile` releases it behind the
/// same booking gate as the phone number - and a client who is collecting
/// their own appliance has, by definition, a booking.
class _ReadyForCollection extends StatefulWidget {
  const _ReadyForCollection({
    required this.jobId,
    required this.technicianId,
    required this.tracking,
  });

  final String jobId;
  final String technicianId;

  /// The live row, for the client's own trip to the shop.
  final JobTracking tracking;

  @override
  State<_ReadyForCollection> createState() => _ReadyForCollectionState();
}

class _ReadyForCollectionState extends State<_ReadyForCollection> {
  final TechnicianDirectoryService _directory = TechnicianDirectoryService();

  TechnicianProfileDetails? _profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final TechnicianProfileDetails profile = await _directory.profile(
        widget.technicianId,
        // No reviews needed - this card only wants the workshop.
        reviewLimit: 1,
      );
      if (!mounted) return;
      setState(() => _profile = profile);
    } catch (_) {
      // Silent: the card below still carries the message that matters.
    }
  }

  @override
  Widget build(BuildContext context) {
    final TechnicianProfileDetails? profile = _profile;
    final bool hasShop = profile?.hasShopLocation ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _collectCard(profile, hasShop),
        const SizedBox(height: AppSizes.md),
        // The trip itself (2026-09-29): tell the technician you are coming,
        // and let them see you on the way.
        SugoCard(child: CollectionTripPanel(tracking: widget.tracking)),
      ],
    );
  }

  Widget _collectCard(TechnicianProfileDetails? profile, bool hasShop) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: AppColors.successSoft,
        borderRadius: BorderRadius.circular(AppSizes.panelRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Icon(
            Icons.store_mall_directory_rounded,
            size: 34,
            color: AppColors.success,
          ),
          const SizedBox(height: AppSizes.md),
          Text(
            'Ready for collection',
            textAlign: TextAlign.center,
            style: AppTextStyles.titleSmall,
          ),
          const SizedBox(height: AppSizes.xs),
          Text(
            hasShop
                ? 'The repair is finished. Here is where to collect it.'
                : 'The repair is finished and your appliance is waiting at the '
                      'workshop. Message the technician to agree a time and '
                      'get the exact address.',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption,
          ),
          if (hasShop) ...<Widget>[
            const SizedBox(height: AppSizes.lg),
            RouteMapCard(
              icon: Icons.storefront_rounded,
              jobId: widget.jobId,
              latitude: profile!.shopLatitude!,
              longitude: profile.shopLongitude!,
              title: profile.shopName?.trim().isNotEmpty ?? false
                  ? profile.shopName!
                  : 'Workshop',
              address: profile.technician.displayName,
            ),
            const SizedBox(height: AppSizes.md),
            SugoButton(
              label: 'Open in maps',
              icon: Icons.directions_rounded,
              variant: SugoButtonVariant.outlined,
              size: SugoButtonSize.medium,
              onPressed: () => ContactLauncher.directions(
                context,
                latitude: profile.shopLatitude!,
                longitude: profile.shopLongitude!,
                label: profile.shopName ?? 'Workshop',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A booking whose technician has not set off yet.
class _NotStarted extends StatelessWidget {
  const _NotStarted({required this.journey});

  final TrackingJourney journey;

  @override
  Widget build(BuildContext context) {
    return SugoCard(
      background: AppColors.primarySofter,
      borderColor: AppColors.primarySoft,
      child: Row(
        children: <Widget>[
          Container(
            width: AppSizes.iconTile,
            height: AppSizes.iconTile,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSizes.radius),
            ),
            child: const Icon(
              Icons.schedule_rounded,
              color: AppColors.primary,
              size: 21,
            ),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Waiting for the technician to set off',
                  style: AppTextStyles.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  journey == TrackingJourney.homeVisit
                      ? 'The map appears here once they start the trip to you.'
                      : 'The map appears here once they head out to collect it.',
                  style: AppTextStyles.micro,
                ),
                const SizedBox(height: AppSizes.sm),
                const SugoStatusBadge(
                  label: 'Booking confirmed',
                  icon: Icons.check_circle_rounded,
                  tone: SugoTone.success,
                  dense: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
