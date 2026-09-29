import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../services/technician_service.dart';

/// Horizontally scrolling ratings from completed jobs.
///
/// Ratings only, no review text. `job_outcomes` stores `final_rating` as a
/// number and has no comment column, so writing quotes here would mean
/// inventing them. Each card shows what the row actually contains: the score,
/// whether the diagnosis held up, and whether it had to be rerouted.
class RecentReviewsStrip extends StatelessWidget {
  const RecentReviewsStrip({super.key, required this.outcomes});

  final List<TechnicianOutcome> outcomes;

  @override
  Widget build(BuildContext context) {
    if (outcomes.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: AppSizes.screenPadding),
        padding: const EdgeInsets.all(AppSizes.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSizes.tileRadius),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          children: <Widget>[
            Icon(Icons.reviews_outlined, size: 22, color: AppColors.hint),
            SizedBox(width: AppSizes.md),
            Expanded(
              child: Text(
                'No ratings yet. Complete a job and the client can rate it, '
                'which also improves how you rank on future matches.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.screenPadding),
        itemCount: outcomes.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSizes.md),
        itemBuilder: (BuildContext context, int index) =>
            _ReviewCard(outcome: outcomes[index]),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.outcome});

  final TechnicianOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final double rating = outcome.finalRating ?? 0;
    final DateTime? at = outcome.createdAt;

    return Container(
      width: 190,
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              ...List<Widget>.generate(5, (int index) {
                final bool filled = index < rating.round();
                return Icon(
                  filled ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 15,
                  color: AppColors.accent,
                );
              }),
              const Spacer(),
              Text(
                rating > 0 ? rating.toStringAsFixed(1) : '-',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),

          _Flag(
            ok: outcome.diagnosisCorrect ?? true,
            label: outcome.diagnosisCorrect == false
                ? 'Diagnosis was wrong'
                : 'Diagnosis held up',
          ),
          const SizedBox(height: 4),
          if (outcome.reroutedMidJob)
            const _Flag(ok: false, label: 'Rerouted mid-job')
          else
            const _Flag(ok: true, label: 'No reroute needed'),

          const Spacer(),
          Text(
            at == null ? '' : DateFormat('d MMM y').format(at),
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Flag extends StatelessWidget {
  const _Flag({required this.ok, required this.label});

  final bool ok;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(
          ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
          size: 13,
          color: ok ? AppColors.success : AppColors.warning,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
