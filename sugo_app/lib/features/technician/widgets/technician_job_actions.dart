import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_loading.dart';
import '../../rb_cars/models/job.dart';
import '../../rb_cars/models/job_enums.dart';
import '../../tracking/widgets/route_map_card.dart';

/// What a technician does with the job they are on, on the job's own screen.
///
/// Moved here from the dashboard card on 2026-09-29, when that card became a
/// summary with a single "View job" (the user's request). Everything the card
/// used to offer is here:
///
/// * the client's address on a map, with "Show route" into in-app routing -
///   home visits only, since a pickup's map lives on the delivery screen;
/// * **Trip to the client** / **Pickup and delivery**, via [onTrip];
/// * **Mark as complete**, which asks the two RB-CARS questions first;
/// * **Cannot fix here - take to shop**, home visits only.
///
/// The screen owns the calls; this widget only draws them and shows which one
/// is running ([isCompleting], [isMovingToShop]) - in its own colour with a
/// spinner, because grey reads as "not allowed" rather than "working on it".
class TechnicianJobActions extends StatelessWidget {
  const TechnicianJobActions({
    super.key,
    required this.job,
    required this.onTrip,
    required this.onComplete,
    required this.onNeedsShop,
    this.isCompleting = false,
    this.isMovingToShop = false,
  });

  final Job job;
  final VoidCallback onTrip;
  final VoidCallback onComplete;
  final VoidCallback onNeedsShop;
  final bool isCompleting;
  final bool isMovingToShop;

  bool get _isHomeVisit => job.servicePath == ServicePath.homeService;
  bool get _isPickup => job.servicePath == ServicePath.pickup;
  bool get _busy => isCompleting || isMovingToShop;

  @override
  Widget build(BuildContext context) {
    return SugoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Your job', style: AppTextStyles.sectionTitle),
          const SizedBox(height: AppSizes.md),

          if (_isHomeVisit && job.hasLocation) ...<Widget>[
            RouteMapCard(
              jobId: job.id,
              latitude: job.latitude!,
              longitude: job.longitude!,
              title: 'Client address',
              address: job.locationLabel,
            ),
            const SizedBox(height: AppSizes.md),
          ],

          if (_isHomeVisit || _isPickup) ...<Widget>[
            SizedBox(
              height: AppSizes.buttonHeight,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : onTrip,
                icon: const Icon(Icons.navigation_rounded, size: 18),
                label: Text(
                  _isHomeVisit ? 'Trip to the client' : 'Pickup and delivery',
                ),
              ),
            ),
            const SizedBox(height: AppSizes.sm),
          ],

          SizedBox(
            height: AppSizes.buttonHeight,
            child: isCompleting
                ? OutlinedButton(
                    onPressed: null,
                    style: OutlinedButton.styleFrom(
                      disabledForegroundColor: AppColors.primary,
                    ),
                    child: const SugoButtonProgress(label: 'Completing…'),
                  )
                : OutlinedButton.icon(
                    onPressed: _busy ? null : onComplete,
                    icon: const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                    ),
                    label: const Text('Mark as complete'),
                  ),
          ),

          // The escape hatch. A technician can only honestly answer "can this
          // be fixed here?" once they are standing in front of it.
          if (_isHomeVisit) ...<Widget>[
            const SizedBox(height: AppSizes.sm),
            SizedBox(
              height: AppSizes.buttonHeight,
              child: isMovingToShop
                  ? OutlinedButton(
                      onPressed: null,
                      style: OutlinedButton.styleFrom(
                        disabledForegroundColor: AppColors.primary,
                      ),
                      child: const SugoButtonProgress(label: 'Switching…'),
                    )
                  : OutlinedButton.icon(
                      onPressed: _busy ? null : onNeedsShop,
                      icon: const Icon(
                        Icons.store_mall_directory_outlined,
                        size: 18,
                      ),
                      label: const Text('Cannot fix here - take to shop'),
                    ),
            ),
          ],

          const SizedBox(height: AppSizes.sm),
          Text(
            _isHomeVisit
                ? 'Start the trip when you set off, so the client can follow '
                      'you and knows if you are running late.'
                : _isPickup
                ? 'Your location is shared from the pickup screen, so the '
                      'client can see where their appliance is.'
                : 'Mark it complete once the diagnosis is settled.',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }
}
