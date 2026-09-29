import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/sugo_card.dart';
import '../models/job_dispute.dart';

/// The booking screen's reports: any that exist, and the way to open one.
///
/// ## Placement
///
/// On the booking, not on the home screen: a report is always about one
/// specific job, and everything the admin weighs - the chat, the photos, the
/// timeline, the price - is on this screen already. It sits at the bottom, a
/// quiet outlined action, because most bookings never need it and it should
/// not compete with the actions that do.
///
/// Both sides see every report on the job, including the one about them. A
/// process the accused cannot read is not a fair one.
class DisputeSection extends StatelessWidget {
  const DisputeSection({
    super.key,
    required this.disputes,
    required this.isClient,
    required this.canReport,
    required this.onReport,
  });

  final List<JobDispute> disputes;

  /// Which side is reading - decides "You reported" versus "The technician
  /// reported".
  final bool isClient;

  /// The booking is in a state a report can be opened on.
  final bool canReport;
  final VoidCallback onReport;

  bool get _hasOpenReportOfMine => disputes.any(
    (JobDispute d) => d.isOpen && d.raisedByClient == isClient,
  );

  @override
  Widget build(BuildContext context) {
    final bool offer = canReport && !_hasOpenReportOfMine;
    if (disputes.isEmpty && !offer) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final JobDispute dispute in disputes.take(2)) ...<Widget>[
          _DisputeCard(dispute: dispute, isClient: isClient),
          const SizedBox(height: AppSizes.md),
        ],
        if (offer)
          OutlinedButton.icon(
            onPressed: onReport,
            icon: const Icon(Icons.report_problem_outlined, size: 19),
            label: const Text('Report a problem with this booking'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
      ],
    );
  }
}

class _DisputeCard extends StatelessWidget {
  const _DisputeCard({required this.dispute, required this.isClient});

  final JobDispute dispute;
  final bool isClient;

  @override
  Widget build(BuildContext context) {
    final bool mine = dispute.raisedByClient == isClient;
    final String who = mine
        ? 'You reported'
        : dispute.raisedByClient
        ? 'The client reported'
        : 'The technician reported';

    final (Color tint, Color ink, IconData icon) = switch (dispute.status) {
      DisputeStatus.open => (
        AppColors.warningSoft,
        AppColors.warning,
        Icons.hourglass_top_rounded,
      ),
      DisputeStatus.resolved => (
        AppColors.successSoft,
        AppColors.success,
        Icons.check_circle_rounded,
      ),
      DisputeStatus.dismissed => (
        AppColors.divider,
        AppColors.textSecondary,
        Icons.do_not_disturb_on_outlined,
      ),
    };

    return SugoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.sm + 2,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(icon, size: 14, color: ink),
                    const SizedBox(width: 4),
                    Text(
                      dispute.status.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (dispute.createdAt != null)
                Text(
                  Fmt.date(dispute.createdAt!.toLocal()),
                  style: AppTextStyles.micro,
                ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          Text(
            '$who: ${dispute.reason.label.toLowerCase()}',
            style: AppTextStyles.titleSmall,
          ),
          const SizedBox(height: AppSizes.xs),
          Text(
            dispute.details,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.subtitle.copyWith(fontSize: 13),
          ),
          if (dispute.photoPaths.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSizes.xs),
            Text(
              '${dispute.photoPaths.length} photo'
              '${dispute.photoPaths.length == 1 ? '' : 's'} attached',
              style: AppTextStyles.micro,
            ),
          ],
          const SizedBox(height: AppSizes.md),
          if (dispute.isOpen)
            Text(
              'A SUGO admin is reviewing this. Their decision will appear '
              'here, for both of you.',
              style: AppTextStyles.caption,
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSizes.md),
              decoration: BoxDecoration(
                color: AppColors.primarySofter,
                borderRadius: BorderRadius.circular(AppSizes.tileRadius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    "SUGO's decision",
                    style: AppTextStyles.micro.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dispute.resolutionNote ?? '',
                    style: AppTextStyles.subtitle.copyWith(fontSize: 13),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
