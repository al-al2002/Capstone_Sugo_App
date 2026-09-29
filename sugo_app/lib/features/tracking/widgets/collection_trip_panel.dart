import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/widgets/sugo_button.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../models/job_tracking.dart';
import '../services/tracking_service.dart';

/// The client's side of collecting a repaired unit from the workshop.
///
/// ## What it does (2026-09-29)
///
/// * **I'm on my way** opens the trip (`start_collection_trip`): the
///   technician is told, and from then on sees the client on a map with an
///   arrival time.
/// * While this panel is on screen, each position fix goes to the server
///   (`share_collection_position`) and every couple of minutes the ETA is
///   resampled against live traffic and weather. If the trip slips ten minutes
///   past its first estimate, the technician gets "your client is running
///   late" - the same machinery, pointed the other way.
/// * **I've arrived** ends it (`end_collection_trip`): the position is
///   dropped and no delay can be reported for a trip that is over.
///
/// ## Why the client opts in
///
/// Nobody's location is shared by default. The technician's is shared only
/// while they drive a trip they started; the client's the same. Leaving this
/// screen stops the stream, and the panel says so.
class CollectionTripPanel extends StatefulWidget {
  const CollectionTripPanel({super.key, required this.tracking, this.service});

  /// The live row, rebuilt by the tracking screen on every realtime update.
  final JobTracking tracking;

  /// Tests pass a fake.
  final TrackingService? service;

  @override
  State<CollectionTripPanel> createState() => _CollectionTripPanelState();
}

class _CollectionTripPanelState extends State<CollectionTripPanel> {
  late final TrackingService _service = widget.service ?? TrackingService();

  StreamSubscription<Position>? _positions;
  DateTime? _lastEtaSample;
  bool _isBusy = false;
  int _fixesSent = 0;

  String get _jobId => widget.tracking.jobId;
  bool get _isSharing => _positions != null;

  @override
  void dispose() {
    _positions?.cancel();
    super.dispose();
  }

  Future<bool> _ensureLocation() async {
    final LocationReadiness readiness = await _service.prepareLocation();
    if (!mounted) return false;
    if (!readiness.isReady) {
      UiFeedback.showError(context, readiness.reason!);
      return false;
    }
    return true;
  }

  Future<void> _setOff() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      if (!await _ensureLocation()) return;
      await _service.startCollectionTrip(_jobId);
      if (!mounted) return;
      _startSharing();
      UiFeedback.showSuccess(
        context,
        'Your technician can see you are on the way.',
      );
    } on RbCarsFailure catch (failure) {
      if (mounted) UiFeedback.showError(context, failure.message);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _resume() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      if (await _ensureLocation()) _startSharing();
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _arrive() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      await _service.endCollectionTrip(_jobId);
      if (!mounted) return;
      _stopSharing();
      UiFeedback.showSuccess(context, 'Your technician knows you are here.');
    } on RbCarsFailure catch (failure) {
      if (mounted) UiFeedback.showError(context, failure.message);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _startSharing() {
    if (_isSharing) return;
    setState(() {
      _positions = _service.positionStream().listen(
        (Position position) async {
          await _service.shareCollectionPosition(_jobId, position);
          unawaited(_maybeSampleEta());
          if (mounted) setState(() => _fixesSent += 1);
        },
        onError: (Object _) {
          if (mounted) {
            UiFeedback.showError(context, 'Lost the location signal.');
          }
        },
      );
    });
  }

  /// Not awaited, for the same reason as the technician's trip screen: the
  /// stream stops delivering on cancel.
  void _stopSharing() {
    final StreamSubscription<Position>? open = _positions;
    if (open == null) return;
    setState(() => _positions = null);
    unawaited(open.cancel());
  }

  Future<void> _maybeSampleEta() async {
    final DateTime now = DateTime.now();
    final DateTime? last = _lastEtaSample;
    if (last != null &&
        now.difference(last) < TrackingService.etaSampleInterval) {
      return;
    }
    _lastEtaSample = now;
    await _service.sampleEta(_jobId);
  }

  @override
  Widget build(BuildContext context) {
    final JobTracking t = widget.tracking;

    if (t.clientArrived) {
      return const _Line(
        icon: Icons.where_to_vote_rounded,
        tint: AppColors.success,
        title: "You've arrived",
        detail: 'Your technician knows you are at the shop.',
      );
    }

    if (!t.clientOnTheWay) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _Line(
            icon: Icons.directions_walk_rounded,
            tint: AppColors.primary,
            title: 'Heading over?',
            detail:
                'Let your technician know. They will see you on a map and '
                'be told if traffic or the weather holds you up.',
          ),
          const SizedBox(height: AppSizes.md),
          SugoButton(
            label: "I'm on my way",
            icon: Icons.near_me_rounded,
            isLoading: _isBusy,
            onPressed: _setOff,
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            'Your location is shared only during this trip, and only while '
            'this screen is open.',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Line(
          icon: Icons.directions_walk_rounded,
          tint: _isSharing ? AppColors.success : AppColors.warning,
          title: 'On your way to the shop',
          detail: _isSharing
              ? 'Sharing your location · $_fixesSent '
                    'update${_fixesSent == 1 ? '' : 's'} sent'
              : 'Location is off. Your technician cannot see where you are.',
        ),
        if (_arrivalLabel(t) case final String eta) ...<Widget>[
          const SizedBox(height: AppSizes.sm),
          Text(eta, style: AppTextStyles.bodyStrong),
        ],
        if (t.isDelayed) ...<Widget>[
          const SizedBox(height: AppSizes.xs),
          Text(
            // The client is the one late here, so this informs rather than
            // alarms: the technician has already been told.
            'Running ${t.delayLabel ?? 'late'}'
            '${t.delayReasonLabel == null ? '' : ' (${t.delayReasonLabel})'}'
            '. Your technician has been told.',
            style: AppTextStyles.caption,
          ),
        ],
        const SizedBox(height: AppSizes.md),
        if (!_isSharing) ...<Widget>[
          SugoButton(
            label: 'Share my location again',
            icon: Icons.location_on_rounded,
            variant: SugoButtonVariant.outlined,
            onPressed: _isBusy ? null : _resume,
          ),
          const SizedBox(height: AppSizes.sm),
        ],
        SugoButton(
          label: "I've arrived",
          icon: Icons.where_to_vote_rounded,
          isLoading: _isBusy,
          onPressed: _arrive,
        ),
        const SizedBox(height: AppSizes.sm),
        Text(
          'Leaving this screen stops sharing; your technician then sees your '
          'last position.',
          textAlign: TextAlign.center,
          style: AppTextStyles.caption,
        ),
      ],
    );
  }

  /// "Arriving in about 12 min", from the server's latest estimate.
  static String? _arrivalLabel(JobTracking t) {
    final DateTime? eta = t.projectedArrivalAt;
    if (eta == null) return null;
    final int minutes = eta.difference(DateTime.now()).inMinutes;
    if (minutes <= 0) return 'Arriving now';
    return 'Arriving in about $minutes min';
  }
}

/// An icon tile, a title and a line under it.
class _Line extends StatelessWidget {
  const _Line({
    required this.icon,
    required this.tint,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
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
    );
  }
}
