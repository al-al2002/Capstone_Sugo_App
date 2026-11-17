import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_button.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_pill.dart';
import '../../../core/widgets/sugo_route_line.dart';
import '../../bookings/models/booking_route.dart';
import '../../rb_cars/models/job.dart';
import '../../rb_cars/models/job_enums.dart';
import '../../rb_cars/models/job_price.dart';

/// The job this technician is currently on, as a summary with one way in.
///
/// ## Why one button (2026-09-29)
///
/// This card used to carry the whole job: a map, the address twice, the
/// description, and four buttons - trip, complete, take to shop, route - on
/// the dashboard itself. At the user's request it is now a summary, and every
/// action lives on the job's own screen ([JobDetailScreen], via "View job"),
/// where each one has room to explain itself and a stray tap on a crowded
/// home screen cannot close a job.
class ActiveJobCard extends StatelessWidget {
  const ActiveJobCard({super.key, required this.job, required this.onView});

  final Job job;

  /// Opens the job, where the trip, completion and shop actions are.
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    return SugoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              SugoPill.badge(
                label: job.status.label,
                icon: Icons.play_circle_outline_rounded,
                tint: AppColors.primarySoft,
                foreground: AppColors.primaryDark,
              ),
              const Spacer(),
              if (job.urgency == Urgency.needToday)
                const SugoPill.badge(
                  label: 'Needed today',
                  icon: Icons.bolt_rounded,
                  tint: AppColors.accentSoft,
                  foreground: AppColors.accentDark,
                ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primarySofter,
                  borderRadius: BorderRadius.circular(AppSizes.radius),
                ),
                child: Icon(
                  job.deviceType.icon,
                  size: 21,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      job.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      <String>[
                        if (job.servicePath != null) job.servicePath!.label,
                        // The quoted price, not the budget (2026-11-17).
                        JobPrice.forJob(job).headline,
                      ].join('  •  '),
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),

          // The booking's route, the same drawing the client sees on their
          // home card: both sides of a job watch one trip.
          if (BookingRoute.forStatus(job.status)
              case final SugoRoutePosition at) ...<Widget>[
            const SizedBox(height: AppSizes.lg),
            SugoRouteLine(stops: BookingRoute.stops, position: at),
          ],

          if (job.hasLocation) ...<Widget>[
            const SizedBox(height: AppSizes.md),
            Row(
              children: <Widget>[
                const Icon(
                  Icons.place_rounded,
                  size: 16,
                  color: AppColors.accentDark,
                ),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: Text(
                    job.locationLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: AppSizes.lg),
          SugoButton(
            label: 'View job',
            icon: Icons.arrow_forward_rounded,
            onPressed: onView,
          ),
        ],
      ),
    );
  }
}
