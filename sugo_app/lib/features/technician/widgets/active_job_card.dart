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
                        job.budgetLabel,
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
          if (BookingRoute.forStatus(job.status) case final SugoRoutePosition at)
            ...<Widget>[
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

/// Asks the two questions that feed the RB-CARS learning loop.
///
/// `diagnosis_correct` and `rerouted_mid_job` are the only signals Stage 1
/// learns from, so they are asked explicitly rather than defaulted. A silent
/// default of "yes, correct" would quietly inflate every technician's accuracy
/// and make the feedback loop meaningless.
class CompleteJobSheet extends StatefulWidget {
  const CompleteJobSheet({super.key, required this.job});

  final Job job;

  static Future<CompletionAnswers?> show(BuildContext context, Job job) {
    return showModalBottomSheet<CompletionAnswers>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CompleteJobSheet(job: job),
    );
  }

  @override
  State<CompleteJobSheet> createState() => _CompleteJobSheetState();
}

class _CompleteJobSheetState extends State<CompleteJobSheet> {
  bool? _diagnosisCorrect;
  bool _rerouted = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSizes.cardRadius),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSizes.screenPadding,
        AppSizes.lg,
        AppSizes.screenPadding,
        MediaQuery.of(context).viewInsets.bottom + AppSizes.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(AppSizes.pillRadius),
              ),
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          const Text(
            'Close this job',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSizes.xs),
          const Text(
            'Two honest answers. These are the only things the matching '
            'engine learns from, and they affect which jobs you are offered '
            'next.',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSizes.xl),

          const Text(
            'Was the original diagnosis correct?',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSizes.md),
          Row(
            children: <Widget>[
              Expanded(
                child: _Choice(
                  label: 'Yes, as described',
                  icon: Icons.check_circle_outline_rounded,
                  selected: _diagnosisCorrect == true,
                  onTap: () => setState(() => _diagnosisCorrect = true),
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: _Choice(
                  label: 'No, it was something else',
                  icon: Icons.cancel_outlined,
                  selected: _diagnosisCorrect == false,
                  onTap: () => setState(() => _diagnosisCorrect = false),
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSizes.xl),
          SwitchListTile.adaptive(
            value: _rerouted,
            onChanged: (bool value) => setState(() => _rerouted = value),
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Rerouted mid-job',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            subtitle: const Text(
              'It had to move from on-site to the shop, or the other way, '
              'after you started.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),

          const SizedBox(height: AppSizes.lg),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _diagnosisCorrect == null
                  ? null
                  : () => Navigator.of(context).pop(
                      CompletionAnswers(
                        diagnosisCorrect: _diagnosisCorrect!,
                        reroutedMidJob: _rerouted,
                      ),
                    ),
              child: const Text('Complete job'),
            ),
          ),
          const SizedBox(height: AppSizes.sm),
          const Text(
            'The client rates the job separately. You cannot rate yourself.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.tileRadius),
      child: Container(
        padding: const EdgeInsets.all(AppSizes.md),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySofter : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSizes.tileRadius),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          children: <Widget>[
            Icon(
              icon,
              size: 20,
              color: selected ? AppColors.primary : AppColors.hint,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.25,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the completion sheet returns.
class CompletionAnswers {
  const CompletionAnswers({
    required this.diagnosisCorrect,
    required this.reroutedMidJob,
  });

  final bool diagnosisCorrect;
  final bool reroutedMidJob;
}
