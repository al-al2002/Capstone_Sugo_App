import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../tracking/widgets/route_map_card.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_loading.dart';
import '../../../core/widgets/sugo_pill.dart';
import '../../../core/widgets/sugo_route_line.dart';
import '../../bookings/models/booking_route.dart';
import '../../rb_cars/models/job.dart';
import '../../rb_cars/models/job_enums.dart';

/// The job this technician is currently on, with the completion action.
///
/// Once accepted they *are* assigned, so `jobs_technician_select_assigned`
/// opens up the real row: full description, photos and the exact coordinates
/// they now need to actually get there.
class ActiveJobCard extends StatelessWidget {
  const ActiveJobCard({
    super.key,
    required this.job,
    required this.onComplete,
    required this.onTrack,
    required this.onNeedsShop,
    this.isBusy = false,
    this.isCompleting = false,
  });

  final Job job;
  final VoidCallback onComplete;

  /// Opens the trip screen: the drive to a home visit, or the pickup and
  /// delivery of a rerouted job.
  final VoidCallback onTrack;

  /// The on-site repair cannot be finished here, so the unit goes to the
  /// workshop. Only offered while the job is still a home service - once it is
  /// a pickup there is nothing left to switch.
  final VoidCallback onNeedsShop;

  final bool isBusy;

  /// "Mark as complete" is the action in flight: its button shows a spinner.
  final bool isCompleting;

  /// A pickup job travels twice, so it needs the tracking controls. An on-site
  /// repair never leaves the client's home and has nothing to share.
  bool get _needsTracking => job.servicePath == ServicePath.pickup;

  /// Only a home visit involves the technician travelling to the client.
  ///
  /// Distinct from `!_needsTracking`, which also catches `it_community` - a
  /// group diagnosis posted to the technician community, where nobody goes
  /// anywhere. Showing that a route map to the client's address would invite a
  /// drive nobody agreed to.
  bool get _isHomeVisit => job.servicePath == ServicePath.homeService;

  /// "Mark as complete", filled when it is the card's main action and
  /// outlined when a trip button sits above it.
  ///
  /// While the completion is saving it keeps its own colours with a spinner
  /// and "Completing…": it is disabled either way, but grey would read as
  /// "not allowed" rather than "working on it".
  Widget _completeButton({required bool filled}) {
    const Widget icon = Icon(Icons.check_circle_outline_rounded, size: 18);
    const Widget label = Text('Mark as complete');
    const Widget progress = SugoButtonProgress(label: 'Completing…');
    final VoidCallback? onPressed = isBusy ? null : onComplete;

    if (filled) {
      final ButtonStyle style = ElevatedButton.styleFrom(
        disabledBackgroundColor: isCompleting ? AppColors.primary : null,
        disabledForegroundColor: isCompleting ? Colors.white : null,
      );
      return isCompleting
          ? ElevatedButton(onPressed: null, style: style, child: progress)
          : ElevatedButton.icon(
              onPressed: onPressed,
              style: style,
              icon: icon,
              label: label,
            );
    }

    final ButtonStyle style = OutlinedButton.styleFrom(
      disabledForegroundColor: isCompleting ? AppColors.primary : null,
    );
    return isCompleting
        ? OutlinedButton(onPressed: null, style: style, child: progress)
        : OutlinedButton.icon(
            onPressed: onPressed,
            style: style,
            icon: icon,
            label: label,
          );
  }

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
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      <String>[
                        if (job.servicePath != null) job.servicePath!.label,
                        job.budgetLabel,
                      ].join('  •  '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // The booking's route, the same drawing the client sees on their
          // home card: both sides of a job watch one trip. Placed from
          // `jobs.status` - accepted sits at "Booked", work under way on the
          // leg towards "Fixed".
          if (BookingRoute.forStatus(job.status) case final SugoRoutePosition at)
            ...<Widget>[
              const SizedBox(height: AppSizes.lg),
              SugoRouteLine(stops: BookingRoute.stops, position: at),
            ],

          // A home-service job means the technician has to drive to the client.
          // The address alone is not enough to act on, so the destination gets
          // a map and a handoff to a real navigation app.
          //
          // A pickup job is excluded: it has the full `TrackingMap` on the
          // delivery screen, which shows the live leg rather than a static pin.
          if (job.hasLocation && _isHomeVisit) ...<Widget>[
            const SizedBox(height: AppSizes.md),
            RouteMapCard(
              jobId: job.id,
              latitude: job.latitude!,
              longitude: job.longitude!,
              title: 'Client address',
              address: job.addressText,
            ),
          ],

          if (job.hasLocation) ...<Widget>[
            const SizedBox(height: AppSizes.md),
            Container(
              padding: const EdgeInsets.all(AppSizes.md),
              decoration: BoxDecoration(
                color: AppColors.primarySofter,
                borderRadius: BorderRadius.circular(AppSizes.md),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.place_rounded,
                    size: 16,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(
                    child: Text(
                      job.locationLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (job.description != null) ...<Widget>[
            const SizedBox(height: AppSizes.md),
            Text(
              job.description!,
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ],

          const SizedBox(height: AppSizes.lg),
          if (_needsTracking) ...<Widget>[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isBusy ? null : onTrack,
                icon: const Icon(Icons.navigation_rounded, size: 18),
                label: const Text('Pickup and delivery'),
              ),
            ),
            const SizedBox(height: AppSizes.sm),
            SizedBox(
              width: double.infinity,
              child: _completeButton(filled: false),
            ),
          ] else ...<Widget>[
            // Since 2026-09-29 the drive to a home visit is tracked too: the
            // client follows it on a map and hears if it runs late.
            if (_isHomeVisit) ...<Widget>[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: isBusy ? null : onTrack,
                  icon: const Icon(Icons.navigation_rounded, size: 18),
                  label: const Text('Trip to the client'),
                ),
              ),
              const SizedBox(height: AppSizes.sm),
            ],
            SizedBox(
              width: double.infinity,
              child: _completeButton(filled: !_isHomeVisit),
            ),
            const SizedBox(height: AppSizes.sm),
            // The escape hatch, and the reason the offer screen no longer asks
            // about the shop. A technician can only honestly answer "can this
            // be fixed here?" once they are standing in front of it.
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isBusy ? null : onNeedsShop,
                icon: const Icon(Icons.store_mall_directory_outlined, size: 18),
                label: Text(
                  _isHomeVisit
                      ? 'Cannot fix here - take to shop'
                      : 'Needs shop repair',
                ),
              ),
            ),
          ],

          const SizedBox(height: AppSizes.sm),
          Text(
            _needsTracking
                ? 'Share your location from the pickup screen so the client '
                      'can see where their appliance is.'
                // TODO(evidence): photo evidence at arrival and completion is
                // still outstanding.
                : _isHomeVisit
                ? 'Start the trip when you set off, so the client can follow '
                      'you and knows if you are running late.'
                : 'If it turns out this cannot be repaired on site, switch it '
                      'to a shop pickup and the client gets a live map.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
