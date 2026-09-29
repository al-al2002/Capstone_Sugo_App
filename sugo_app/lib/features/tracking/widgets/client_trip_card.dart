import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_card.dart';
import '../models/job_tracking.dart';
import 'tracking_map.dart';

/// The technician's view of a client coming to collect their unit
/// (2026-09-29): where they are, when they should arrive, and whether they
/// are running late.
///
/// The mirror of the client's tracking screen. Same row, same ETA and delay
/// columns - on this one leg they describe the client's trip (see
/// `eta_sampler.ts`) - with the client drawn as a person and the shop as the
/// destination.
class ClientTripCard extends StatelessWidget {
  const ClientTripCard({super.key, required this.tracking, this.workshop});

  final JobTracking tracking;

  /// The technician's own shop, where the client is heading. Null when none
  /// is recorded; the map then shows the client alone.
  final LatLng? workshop;

  @override
  Widget build(BuildContext context) {
    final JobTracking t = tracking;

    if (t.clientArrived) {
      return const SugoCard(
        child: _Header(
          icon: Icons.where_to_vote_rounded,
          tint: AppColors.success,
          title: 'The client has arrived',
          detail: 'Hand it over, then mark it collected below.',
        ),
      );
    }

    if (!t.clientOnTheWay) {
      return const SugoCard(
        child: _Header(
          icon: Icons.hourglass_top_rounded,
          tint: AppColors.primary,
          title: 'Waiting for the client to set off',
          detail:
              'When they tap "I\'m on my way" you will see them here on a '
              'map, with an arrival time.',
        ),
      );
    }

    return SugoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Header(
            icon: Icons.directions_walk_rounded,
            tint: t.isDelayed ? AppColors.warning : AppColors.success,
            title: 'The client is on the way',
            detail: _arrivalLabel(t) ?? _freshness(t),
          ),
          if (t.isDelayed) ...<Widget>[
            const SizedBox(height: AppSizes.md),
            _DelayLine(tracking: t),
          ],
          const SizedBox(height: AppSizes.md),
          if (t.hasClientPosition)
            TrackingMap(
              tracking: t.asClientTrip(),
              destination: workshop,
              destinationLabel: 'Your shop',
              destinationIcon: Icons.storefront_rounded,
              height: 220,
              travellerIcon: Icons.person_rounded,
            )
          else
            Text(
              'Waiting for their first position. It appears once their phone '
              'has a fix.',
              style: AppTextStyles.caption,
            ),
        ],
      ),
    );
  }

  static String? _arrivalLabel(JobTracking t) {
    final DateTime? eta = t.projectedArrivalAt;
    if (eta == null) return null;
    final int minutes = eta.difference(DateTime.now()).inMinutes;
    if (minutes <= 0) return 'Arriving now';
    return 'Arriving in about $minutes min';
  }

  /// Like [JobTracking.freshnessLabel], but for the client's own fixes.
  static String _freshness(JobTracking t) {
    final DateTime? at = t.clientPositionAt;
    if (at == null) return 'Set off just now';
    final Duration since = DateTime.now().difference(at);
    if (since.inSeconds < 90) return 'Live';
    if (since.inMinutes < 60) return 'Updated ${since.inMinutes} min ago';
    return 'Position is out of date';
  }
}

class _Header extends StatelessWidget {
  const _Header({
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

/// "Running about 15 minutes behind - heavy traffic", when the data says so.
class _DelayLine extends StatelessWidget {
  const _DelayLine({required this.tracking});

  final JobTracking tracking;

  @override
  Widget build(BuildContext context) {
    final String? cause = tracking.delayReasonLabel;
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.schedule_rounded, size: 18, color: AppColors.warning),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              'Running ${tracking.delayLabel ?? 'late'}'
              '${cause == null ? '' : ' · $cause'}',
              style: AppTextStyles.bodyStrong,
            ),
          ),
        ],
      ),
    );
  }
}
