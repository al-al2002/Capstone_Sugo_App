import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/widgets/sugo_app_bar.dart';
import '../../../core/widgets/sugo_button.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_empty_state.dart';
import '../../../core/widgets/sugo_skeleton.dart';
import '../../../core/widgets/sugo_truck_drive.dart';
import '../../rb_cars/models/job.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../models/job_tracking.dart';
import '../services/tracking_service.dart';
import '../widgets/location_feedback.dart';
import '../widgets/route_map_card.dart';

/// The technician's side of a home visit: the drive to the client's door.
///
/// ## What the client gets from it
///
/// 1. **Start trip** opens the tracking row at `heading_to_pickup` and turns
///    location sharing on. The database trigger pushes "Your technician is on
///    the way" to the client, and their tracking screen becomes a live map.
/// 2. While sharing, each position fix goes to `job_tracking`, and every 90
///    seconds or so the ETA is resampled against live traffic and weather
///    (`tracking-eta`). If it slips ten minutes past the first estimate, the
///    client gets the delay push and the in-app pop-up.
/// 3. **I've arrived** moves the row to `in_repair`. The map closes, sharing
///    stops, and the stage change clears the ETA, so no delay can be reported
///    for a trip that is over.
///
/// ## Why this is not the pickup screen
///
/// `TechnicianDeliveryScreen` opens the tracking row the moment it is shown,
/// which is right for a pickup (the row already exists from the reroute) and
/// wrong here: just opening this screen to look at the address would tell the
/// client their technician had set off. Here nothing is written until the
/// technician says they are leaving. It also has none of the pickup's
/// machinery - no return method, no second leg.
///
/// ## Location
///
/// Switched on for them: "Start trip" asks for permission and, if the phone's
/// location is off, for Android's "Turn on location?" (see
/// `TrackingService.prepareLocation`). Coming back to this screen mid-trip
/// resumes sharing without a tap, so a technician who stepped away cannot
/// leave the client watching a frozen pin.
///
/// Only during the trip, and only while this screen is alive. Opening the
/// route pushes a screen on top, which keeps this one - and sharing - running.
/// Leaving it stops the stream: continuous location is a serious thing to take
/// from someone, and they should always know when it is on.
class HomeVisitTripScreen extends StatefulWidget {
  const HomeVisitTripScreen({super.key, required this.job, this.service});

  final Job job;

  /// Tests pass a fake. The app uses the real service.
  final TrackingService? service;

  @override
  State<HomeVisitTripScreen> createState() => _HomeVisitTripScreenState();
}

class _HomeVisitTripScreenState extends State<HomeVisitTripScreen> {
  late final TrackingService _service = widget.service ?? TrackingService();

  StreamSubscription<Position>? _positions;

  /// When the ETA was last resampled. The server has its own floor too; this
  /// only saves the wasted round trip.
  DateTime? _lastEtaSample;

  JobTracking? _tracking;
  bool _isLoading = true;
  bool _isBusy = false;
  String? _error;
  int _fixesSent = 0;

  bool get _isSharing => _positions != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // The guarantee that sharing cannot outlive the screen.
    _positions?.cancel();
    super.dispose();
  }

  /// Reads the trip if one has started. Never creates it - see the class note.
  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final JobTracking? tracking = await _service.fetch(widget.job.id);
      if (!mounted) return;
      setState(() {
        _tracking = tracking;
        _isLoading = false;
      });
      // Back on the screen mid-trip: share again straight away.
      if (tracking?.stage == TrackingStage.headingToPickup) {
        unawaited(_resumeSharing());
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load this trip. Check your connection.';
        _isLoading = false;
      });
    }
  }

  /// Location first, then the row. The other way round, the client would be
  /// told "on the way" and shown a map with nothing on it.
  Future<void> _startTrip() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      if (!await _ensureLocation()) return;
      // `start` inserts at `heading_to_pickup` when there is no row, and
      // returns an existing one untouched.
      final JobTracking tracking = await _service.start(widget.job.id);
      if (!mounted) return;
      setState(() => _tracking = tracking);
      _startSharing();
      UiFeedback.showSuccess(
        context,
        'Trip started. The client can follow you on the map.',
      );
    } on RbCarsFailure catch (failure) {
      if (mounted) UiFeedback.showError(context, failure.message);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  /// For a technician who left the screen mid-trip and came back.
  Future<void> _resumeSharing() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      if (await _ensureLocation()) _startSharing();
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<bool> _ensureLocation() async {
    final LocationReadiness readiness = await _service.prepareLocation();
    if (!mounted) return false;
    if (!readiness.isReady) {
      showLocationBlocked(context, readiness);
      return false;
    }
    return true;
  }

  void _startSharing() {
    if (_isSharing) return;
    setState(() {
      _positions = _service.positionStream().listen(
        (Position position) async {
          await _service.pushPosition(widget.job.id, position);
          unawaited(_maybeSampleEta());
          if (!mounted) return;
          setState(() => _fixesSent += 1);
        },
        onError: (Object _) {
          if (!mounted) return;
          UiFeedback.showError(context, 'Lost the location signal.');
        },
      );
    });
  }

  /// Not awaited: the stream stops delivering the moment it is cancelled, and
  /// whatever the platform does to wind down afterwards is no reason to keep
  /// the technician's button spinning.
  void _stopSharing() {
    final StreamSubscription<Position>? open = _positions;
    if (open == null) return;
    setState(() => _positions = null);
    unawaited(open.cancel());
  }

  /// Rides on the position stream rather than a timer: a technician who has
  /// not moved sends no fixes, and `tracking-eta-sweep` covers them from the
  /// last known position.
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

  Future<void> _arrive() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      final JobTracking updated = await _service.setStage(
        widget.job.id,
        TrackingStage.inRepair,
      );
      if (!mounted) return;
      _stopSharing();
      setState(() => _tracking = updated);
      UiFeedback.showSuccess(
        context,
        'Marked as arrived. Location sharing is off.',
      );
    } on RbCarsFailure catch (failure) {
      if (mounted) UiFeedback.showError(context, failure.message);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const SugoAppBar(title: 'Trip to the client'),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(AppSizes.screenPadding),
        child: SugoSkeletonList(count: 3, showAvatar: false),
      );
    }

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(AppSizes.screenPadding),
        children: <Widget>[
          const SizedBox(height: AppSizes.xxl),
          SugoEmptyState.error(
            title: 'Could not load the trip',
            message: _error!,
            onAction: _load,
          ),
        ],
      );
    }

    final TrackingStage? stage = _tracking?.stage;
    final bool onTheWay = stage == TrackingStage.headingToPickup;
    final bool arrived = stage != null && !onTheWay;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPadding,
        AppSizes.lg,
        AppSizes.screenPadding,
        AppSizes.xxl,
      ),
      children: <Widget>[
        _TripStatusCard(
          stage: stage,
          isSharing: _isSharing,
          fixesSent: _fixesSent,
        ),
        // On the road: the truck drives while the client can see it.
        if (onTheWay) ...<Widget>[
          const SizedBox(height: AppSizes.md),
          SugoTruckDrive(
            moving: _isSharing,
            destinationIcon: Icons.home_rounded,
          ),
        ],
        const SizedBox(height: AppSizes.lg),
        if (widget.job.hasLocation)
          RouteMapCard(
            jobId: widget.job.id,
            latitude: widget.job.latitude!,
            longitude: widget.job.longitude!,
            title: 'Client address',
            address: widget.job.locationLabel,
          )
        else
          Text(
            'This job has no pinned address, so there is no route to draw. '
            'Message the client to agree where to meet.',
            style: AppTextStyles.caption,
          ),
        const SizedBox(height: AppSizes.xl),
        if (stage == null)
          SugoButton(
            label: 'Start trip',
            icon: Icons.navigation_rounded,
            isLoading: _isBusy,
            onPressed: _startTrip,
          )
        else if (onTheWay) ...<Widget>[
          if (!_isSharing) ...<Widget>[
            SugoButton(
              label: 'Share my location again',
              icon: Icons.location_on_rounded,
              variant: SugoButtonVariant.outlined,
              onPressed: _isBusy ? null : _resumeSharing,
            ),
            const SizedBox(height: AppSizes.sm),
          ],
          SugoButton(
            label: "I've arrived",
            icon: Icons.where_to_vote_rounded,
            isLoading: _isBusy,
            onPressed: _arrive,
          ),
        ],
        const SizedBox(height: AppSizes.md),
        Text(
          arrived
              ? 'Mark the job complete from your dashboard when the repair is '
                    'done.'
              : _isSharing
              ? 'Keep this screen open while you drive. Opening the route keeps '
                    'sharing on; leaving this screen stops it, and the client '
                    'then sees your last position.'
              : 'Your location is shared only during the trip. It stops when '
                    'you arrive or leave this screen.',
          textAlign: TextAlign.center,
          style: AppTextStyles.caption,
        ),
      ],
    );
  }
}

/// Where the trip stands, and whether the client can see it.
class _TripStatusCard extends StatelessWidget {
  const _TripStatusCard({
    required this.stage,
    required this.isSharing,
    required this.fixesSent,
  });

  final TrackingStage? stage;
  final bool isSharing;
  final int fixesSent;

  @override
  Widget build(BuildContext context) {
    final (
      IconData icon,
      Color tint,
      String title,
      String detail,
    ) = switch (stage) {
      null => (
        Icons.home_repair_service_rounded,
        AppColors.primary,
        'Not on the way yet',
        'Start the trip when you set off. The client is notified and can '
            'follow you on a map.',
      ),
      TrackingStage.headingToPickup => (
        Icons.directions_car_rounded,
        isSharing ? AppColors.success : AppColors.warning,
        'On the way to the client',
        isSharing
            ? 'Sharing your location · $fixesSent '
                  'update${fixesSent == 1 ? '' : 's'} sent'
            : 'Location is off. The client cannot see where you are.',
      ),
      _ => (
        Icons.handyman_rounded,
        AppColors.accentDark,
        'You have arrived',
        'The client has been told. Location sharing is off.',
      ),
    };

    return SugoCard(
      child: Row(
        children: <Widget>[
          Container(
            width: AppSizes.iconTile,
            height: AppSizes.iconTile,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSizes.radius),
            ),
            child: Icon(icon, size: 22, color: tint),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: AppTextStyles.titleSmall),
                const SizedBox(height: 2),
                Text(detail, style: AppTextStyles.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
