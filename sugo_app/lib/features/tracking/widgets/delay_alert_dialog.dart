import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/job_tracking.dart';
import '../services/delay_alerts.dart';

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

/// The pop-up itself.
///
/// ## Why the cause is sometimes missing
///
/// `delay_reason` is null unless the sampled traffic or weather actually
/// supported the claim (see `eta_sampler.ts`). A technician who is simply
/// behind gets no excuse invented on their behalf, so this says "behind the
/// original estimate" and stops there.
///
/// ## Why "about 15 minutes"
///
/// The estimate is straight-line distance over a sampled speed, rounded to
/// five minutes by [JobTracking.delayLabel]. A precise-sounding arrival time
/// that slips again reads as a lie; "about" is what the method can support.
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

  IconData get _icon => switch (tracking.delayReason) {
    'weather' || 'both' => Icons.thunderstorm_rounded,
    'traffic' => Icons.traffic_rounded,
    _ => Icons.schedule_rounded,
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
    return AlertDialog(
      // Centred, or the dialog's icon slot stretches the tile edge to edge.
      icon: Center(
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.warningSoft,
            borderRadius: BorderRadius.circular(AppSizes.radius),
          ),
          child: Icon(_icon, size: 28, color: AppColors.warning),
        ),
      ),
      // Short enough for one line at 20: the longer "Your technician is
      // running late" left "late" alone on a second line.
      title: Text(
        'Running late',
        textAlign: TextAlign.center,
        style: AppTextStyles.title,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            _headline,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyStrong,
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            clientTrip
                ? 'Your client is still on the way to the shop, and their '
                      'position on the map is live.'
                : 'Your technician is still on the way, and their position '
                      'on the map is live. You can message them from the '
                      'tracking screen.',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption,
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: offerTracking
          ? <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Close'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.near_me_rounded, size: 18),
                label: const Text('See live map'),
              ),
            ]
          : <Widget>[
              FilledButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('OK'),
              ),
            ],
    );
  }
}
