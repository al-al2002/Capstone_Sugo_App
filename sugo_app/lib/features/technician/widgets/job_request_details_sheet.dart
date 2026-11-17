import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/sugo_button.dart';
import '../../../core/widgets/sugo_image_viewer.dart';
import '../../../core/widgets/sugo_sheet.dart';
import '../../rb_cars/models/job.dart';
import '../../rb_cars/models/job_price.dart';
import '../../rb_cars/models/match_result.dart';
import '../../rb_cars/widgets/explainability_chip.dart';
import 'accept_job_dialog.dart';

/// Everything the client said about the job, before the technician answers.
///
/// ## Why this is a sheet and not more card
///
/// The offer card has to stay scannable - a technician with five requests is
/// triaging, not reading. So the card carries the four things that decide
/// whether to look closer (urgency, device, distance, budget) and this sheet
/// carries the rest: the exact machine, the make, what the client says is
/// wrong, the damage flag, when they want it, the full budget range and their
/// own photos.
///
/// ## What is not here, and why
///
/// No name, no address, no phone number. `jobs_technician_select_assigned`
/// hides the job row itself until this technician accepts, so everything below
/// comes from `score_breakdown.job` - the matcher's snapshot, which never
/// carried an identity. The distance is a distance, not a place. That is the
/// deliberate trade: enough to price the work, not enough to turn up at
/// somebody's door before they have agreed.
Future<void> showJobRequestDetails(
  BuildContext context, {
  required MatchResult match,
  required VoidCallback onAccept,
  required VoidCallback onDecline,
  required VoidCallback onMessage,
  bool isBusy = false,
}) {
  return showSugoBottomSheet<void>(
    context: context,
    title: 'The client’s task',
    subtitle: 'What they told us when they posted this job.',
    builder: (BuildContext sheetContext) => _JobRequestDetails(
      match: match,
      isBusy: isBusy,
      onAccept: onAccept,
      onDecline: onDecline,
      onMessage: onMessage,
    ),
  );
}

class _JobRequestDetails extends StatelessWidget {
  const _JobRequestDetails({
    required this.match,
    required this.isBusy,
    required this.onAccept,
    required this.onDecline,
    required this.onMessage,
  });

  final MatchResult match;
  final bool isBusy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final JobSnapshot? job = match.job;

    if (job == null) {
      // The snapshot is written by the matcher at ranking time, so a missing
      // one means an old row from before that field existed. Saying so is
      // better than a sheet of "—".
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSizes.xl),
        child: Text(
          'The details for this request are not available. Accepting it will '
          'still show you the full job.',
          style: AppTextStyles.subtitle,
        ),
      );
    }

    final String? distance = match.breakdown.context.distanceLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // The price leads (2026-11-17): labor for the symptom, the travel or
        // delivery fee for the distance, and the total - the number that
        // decides whether this job is worth taking. It replaced the client's
        // budget range, which was a guess made before anyone was matched.
        _PricePanel(
          job: job,
          price: JobPrice.forSnapshot(
            job,
            distanceKm: match.breakdown.context.distanceKm,
          ),
        ),
        const SizedBox(height: AppSizes.lg),

        _SectionLabel('The device'),
        const SizedBox(height: AppSizes.sm),
        _DetailRow(
          icon: job.deviceType.icon,
          label: 'Type',
          value: job.deviceType.label,
        ),
        if ((job.brand ?? '').trim().isNotEmpty)
          _DetailRow(
            icon: Icons.sell_outlined,
            label: 'Brand',
            value: job.brand!.trim(),
          ),
        if ((job.deviceDetail ?? '').trim().isNotEmpty)
          _DetailRow(
            icon: Icons.memory_rounded,
            label: 'Model',
            value: job.deviceDetail!.trim(),
          ),

        const SizedBox(height: AppSizes.lg),
        _SectionLabel('The problem'),
        const SizedBox(height: AppSizes.sm),
        _DetailRow(
          icon: Icons.build_circle_outlined,
          label: 'Symptom',
          value: job.symptomLabel,
        ),
        _DetailRow(
          icon: job.hasPhysicalDamage
              ? Icons.warning_amber_rounded
              : Icons.check_circle_outline_rounded,
          label: 'Physical damage',
          value: job.hasPhysicalDamage
              ? 'Yes — the client reports visible damage'
              : 'None reported',
          tone: job.hasPhysicalDamage ? AppColors.warning : null,
        ),
        if (job.servicePath != null)
          _DetailRow(
            icon: job.servicePath!.icon,
            label: 'Service needed',
            value: job.servicePath!.label,
          ),

        if ((job.description ?? '').trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSizes.md),
          // In their own words, unclipped. The card truncates this to three
          // lines; the one place it should be readable in full is the screen
          // where the decision is made.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSizes.md),
            decoration: BoxDecoration(
              color: AppColors.fieldFill,
              borderRadius: BorderRadius.circular(AppSizes.cardRadius),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'In their words',
                  style: AppTextStyles.overline.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 5),
                Text(job.description!.trim(), style: AppTextStyles.body),
              ],
            ),
          ),
        ],

        if (job.photoUrls.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSizes.lg),
          _SectionLabel('Their photos'),
          const SizedBox(height: AppSizes.sm),
          _PhotoStrip(urls: job.photoUrls),
        ],

        const SizedBox(height: AppSizes.lg),
        _SectionLabel('When and where'),
        const SizedBox(height: AppSizes.sm),
        _DetailRow(
          icon: job.isUrgent ? Icons.bolt_rounded : Icons.schedule_rounded,
          label: 'Urgency',
          value: job.isUrgent ? 'Needed today' : 'Can wait',
          tone: job.isUrgent ? AppColors.accentDark : null,
        ),
        if (job.preferredSchedule != null)
          _DetailRow(
            icon: Icons.event_rounded,
            label: 'Preferred time',
            value: Fmt.dateTime(job.preferredSchedule!),
          ),
        _DetailRow(
          icon: Icons.place_outlined,
          label: 'Distance from you',
          // A distance, not a place: the exact address only unlocks on
          // acceptance. `distanceLabel` already reads "3.4 km away".
          value: distance ?? 'Not available',
        ),

        const SizedBox(height: AppSizes.lg),
        _SectionLabel('Why you were matched'),
        const SizedBox(height: AppSizes.sm),
        ExplainabilityLine(breakdown: match.breakdown, maxParts: 4),

        const SizedBox(height: AppSizes.xl),
        SugoButton(
          label: 'Accept this job',
          icon: Icons.check_rounded,
          onPressed: isBusy
              ? null
              : () async {
                  // "Ready to take this job?" - earnings, weather, traffic and
                  // tips, in one place, right before they commit.
                  final bool? proceed = await showAcceptJobDialog(
                    context,
                    match: match,
                  );

                  if (proceed != true) return;
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                  onAccept();
                },
        ),
        const SizedBox(height: AppSizes.sm),
        SugoButton(
          label: 'Message the client',
          icon: Icons.chat_bubble_outline_rounded,
          variant: SugoButtonVariant.tonal,
          onPressed: isBusy
              ? null
              : () {
                  Navigator.of(context).pop();
                  onMessage();
                },
        ),
        const SizedBox(height: AppSizes.sm),
        SugoButton(
          label: 'Decline',
          variant: SugoButtonVariant.ghost,
          onPressed: isBusy
              ? null
              : () {
                  Navigator.of(context).pop();
                  onDecline();
                },
        ),
      ],
    );
  }
}

/// The budget, given the space it deserves.
/// The price of this job, at the top of the sheet (2026-11-17).
class _PricePanel extends StatelessWidget {
  const _PricePanel({required this.job, required this.price});

  final JobSnapshot job;
  final JobPrice price;

  @override
  Widget build(BuildContext context) {
    final bool hasRange = job.budgetMin != null || job.budgetMax != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSizes.md + 2),
      decoration: BoxDecoration(
        color: AppColors.primarySofter,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.primarySoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.payments_outlined,
                size: 15,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'Price',
                style: AppTextStyles.overline.copyWith(
                  color: AppColors.primaryDark,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          if (price.labor != null) ...<Widget>[
            Text(
              price.labor!.symptom,
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSizes.sm),
          ],
          _PriceLine(
            label: 'Labor fee',
            value: price.labor?.fee ?? 'To be confirmed',
          ),
          // Urgent jobs: 20% of the labor on top (2026-11-17).
          if (price.hasUrgentFee)
            _PriceLine(
              label: JobPrice.urgentFeeLabel,
              value: price.urgentFeeText!,
            ),
          // Pickup and delivery prints as its two trips (2026-11-17).
          if (price.distanceFeeLines
              case final List<({String label, int amount})> lines)
            for (final ({String label, int amount}) line in lines)
              _PriceLine(label: line.label, value: '₱${line.amount}')
          else if (price.feeLabel != null)
            _PriceLine(
              label: price.distanceFeeLabel!,
              value: 'Agree with the client',
            ),
          if (price.total != null) ...<Widget>[
            const Divider(height: AppSizes.lg, color: AppColors.primarySoft),
            _PriceLine(
              label: 'Estimated total',
              value: price.total!,
              bold: true,
            ),
          ],
          // The client's own range, kept as a footnote when they set one: it
          // tells the technician how far a higher diagnosis can go.
          if (hasRange) ...<Widget>[
            const SizedBox(height: AppSizes.sm),
            Text(
              "Client's budget: ${job.budgetLabel}. If the repair costs more, "
              'message them before you accept.',
              style: AppTextStyles.caption,
            ),
          ],
        ],
      ),
    );
  }
}

class _PriceLine extends StatelessWidget {
  const _PriceLine({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(flex: 3, child: Text(label, style: AppTextStyles.caption)),
          const SizedBox(width: AppSizes.sm),
          Flexible(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: bold ? 16 : 13,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
                color: AppColors.primaryDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.overline.copyWith(
        color: AppColors.textSecondary,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.tone,
  });

  final IconData icon;
  final String label;
  final String value;

  /// Overrides the value's ink, for the two rows where the answer itself is
  /// a warning.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16, color: tone ?? AppColors.textSecondary),
          const SizedBox(width: AppSizes.sm + 2),
          SizedBox(
            width: 108,
            child: Text(label, style: AppTextStyles.caption),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodyStrong.copyWith(color: tone),
            ),
          ),
        ],
      ),
    );
  }
}

/// The client's photos, zoomable.
class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSizes.sm),
        itemBuilder: (BuildContext context, int index) {
          return GestureDetector(
            onTap: () =>
                openSugoImageViewer(context, urls: urls, initialIndex: index),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSizes.sm + 2),
              child: Image.network(
                urls[index],
                width: 86,
                height: 86,
                fit: BoxFit.cover,
                errorBuilder:
                    (BuildContext context, Object error, StackTrace? stack) {
                      return Container(
                        width: 86,
                        height: 86,
                        color: AppColors.fieldFill,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.broken_image_outlined,
                          size: 20,
                          color: AppColors.hint,
                        ),
                      );
                    },
              ),
            ),
          );
        },
      ),
    );
  }
}
