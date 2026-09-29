import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_avatar.dart';
import '../models/technician_profile_details.dart';

/// One review, headed by the repair it was about.
///
/// ## Why the job comes first
///
/// A review on its own answers "was this person good?", and that is the wrong
/// question for someone about to book them. The right one is "were they good
/// *at the thing I need*?" - a glowing review of an aircon job says almost
/// nothing about a cracked phone screen.
///
/// So the card leads with the repair on a tinted strip - device, brand,
/// symptom - and the verdict sits underneath it. Read top to bottom it says
/// "they fixed a Samsung phone that would not power on, and here is how that
/// went", which is the sentence the client is actually looking for.
///
/// Used by both profile screens, so a review looks the same whichever way the
/// client arrived at it.
class ReviewCard extends StatelessWidget {
  const ReviewCard({super.key, required this.review});

  final TechnicianReview review;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(color: AppColors.border),
      ),
      // Clips the tinted job strip to the card's rounded top corners.
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (review.hasJob) _JobStrip(review: review),
          Padding(
            padding: const EdgeInsets.all(AppSizes.md + 2),
            child: _Verdict(review: review),
          ),
        ],
      ),
    );
  }
}

/// The repair: device glyph, device and brand, symptom, and how it was done.
class _JobStrip extends StatelessWidget {
  const _JobStrip({required this.review});

  final TechnicianReview review;

  @override
  Widget build(BuildContext context) {
    final String? device = review.jobDeviceLabel;
    final String? symptom = review.jobSymptomLabel;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.md + 2,
        AppSizes.md,
        AppSizes.md + 2,
        AppSizes.md,
      ),
      color: AppColors.primarySofter,
      child: Row(
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSizes.radius),
              border: Border.all(color: AppColors.primarySoft),
            ),
            child: Icon(
              review.jobDeviceType?.icon ?? Icons.build_rounded,
              size: 17,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: AppSizes.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (symptom != null)
                  Text(
                    symptom,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.titleSmall.copyWith(fontSize: 13),
                  ),
                if (device != null)
                  Text(
                    device,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.micro,
                  ),
              ],
            ),
          ),
          if (review.jobServicePath != null) ...<Widget>[
            const SizedBox(width: AppSizes.sm),
            // Flexible so that on a narrow screen the chip ellipsises instead
            // of pushing the row past its edge.
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                  border: Border.all(color: AppColors.primarySoft),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      review.jobServicePath!.icon,
                      size: 11,
                      color: AppColors.primaryDark,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        review.jobServicePath!.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Who reviewed, the stars, when, and what they wrote.
class _Verdict extends StatelessWidget {
  const _Verdict({required this.review});

  final TechnicianReview review;

  @override
  Widget build(BuildContext context) {
    final DateTime? date = review.createdAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            SugoAvatar(
              name: review.reviewerLabel,
              imageUrl: review.reviewerAvatarUrl,
              size: 30,
            ),
            const SizedBox(width: AppSizes.sm + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    review.reviewerLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.titleSmall.copyWith(fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  StarRow(rating: review.stars.toDouble(), size: 12),
                ],
              ),
            ),
            if (date != null)
              Text(
                DateFormat('d MMM yyyy').format(date),
                style: AppTextStyles.micro.copyWith(
                  fontSize: 12,
                  color: AppColors.hint,
                ),
              ),
          ],
        ),
        if (review.hasComment) ...<Widget>[
          const SizedBox(height: AppSizes.sm + 2),
          Text(
            review.comment!.trim(),
            style: AppTextStyles.body.copyWith(fontSize: 13, height: 1.5),
          ),
        ] else ...<Widget>[
          const SizedBox(height: AppSizes.sm),
          // A rating without words is common and legitimate; saying so keeps
          // the card from looking like its text failed to load.
          Text(
            'Rated without a written review.',
            style: AppTextStyles.micro.copyWith(
              fontStyle: FontStyle.italic,
              color: AppColors.hint,
            ),
          ),
        ],
      ],
    );
  }
}

/// Five stars, filled to [rating]. Whole stars only - `job_reviews.stars` is an
/// integer, so there is no half-star to draw for a single review; averages
/// round to the nearest star.
class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.rating, this.size = 14});

  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    final int filled = rating.round().clamp(0, 5);
    // Scales down rather than overflowing. Five stars have a fixed width, and
    // on a narrow phone with large text the date beside them grows while the
    // icons do not - which squeezed this row 1.2px past its column. Shrinking
    // the stars a hair is invisible; an overflow stripe is not.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List<Widget>.generate(5, (int index) {
          return Icon(
            index < filled ? Icons.star_rounded : Icons.star_border_rounded,
            size: size,
            color: AppColors.accent,
          );
        }),
      ),
    );
  }
}

/// What the technician has fixed, counted by device.
///
/// ## Why this exists alongside the reviews
///
/// Reviews are a sample: plenty of finished jobs are never reviewed. A client
/// who sees six reviews could reasonably conclude that is the whole record.
/// This counts every completed job, so the shape of the technician's actual
/// experience is visible - "mostly laptops, some phones" - even where nobody
/// wrote anything.
///
/// It is aggregate by design. It counts jobs that were never reviewed, and a
/// device plus a number cannot identify the client behind any of them.
class PastWorkSummary extends StatelessWidget {
  const PastWorkSummary({super.key, required this.entries});

  final List<WorkHistoryEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();

    final int total = entries.fold<int>(0, (int sum, WorkHistoryEntry e) {
      return sum + e.jobs;
    });
    // The busiest device fills the bar; the rest are scaled against it, so the
    // chart reads as proportions rather than as tiny slivers of a total.
    final int busiest = entries.first.jobs;

    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
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
              const Icon(
                Icons.handyman_rounded,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              // Both flexible. With a Spacer between two fixed texts this row
              // overflowed by 35px under a wide font - and a large
              // accessibility text scale does the same thing on a real phone.
              Flexible(
                child: Text(
                  'Past work',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.sectionTitle,
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: Text(
                  '$total completed ${total == 1 ? 'job' : 'jobs'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: AppTextStyles.micro.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          for (final WorkHistoryEntry entry in entries)
            _WorkRow(entry: entry, busiest: busiest),
        ],
      ),
    );
  }
}

class _WorkRow extends StatelessWidget {
  const _WorkRow({required this.entry, required this.busiest});

  final WorkHistoryEntry entry;
  final int busiest;

  @override
  Widget build(BuildContext context) {
    final double share = busiest == 0 ? 0 : entry.jobs / busiest;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm + 2),
      child: Row(
        children: <Widget>[
          Icon(
            entry.deviceType?.icon ?? Icons.devices_other_rounded,
            size: 15,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: AppSizes.sm),
          SizedBox(
            width: 108,
            child: Text(
              entry.deviceType?.label ?? 'Other',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.micro.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSizes.pillRadius),
              child: Stack(
                children: <Widget>[
                  Container(height: 7, color: AppColors.divider),
                  // Grows in on first build, so the proportions register as a
                  // comparison rather than as a static graphic.
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: share),
                    duration: AppMotion.slow,
                    curve: AppMotion.emphasized,
                    builder: (BuildContext context, double value, Widget? _) {
                      return FractionallySizedBox(
                        widthFactor: value,
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: 7,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(
                              AppSizes.pillRadius,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          SizedBox(
            width: 32,
            // Scaled down, not wrapped: a veteran's "112" in a fixed cell
            // would otherwise break onto three lines, one digit each.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                '${entry.jobs}',
                maxLines: 1,
                style: AppTextStyles.micro.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
