import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../providers/job_posting_provider.dart';
import '../theme/posting_text.dart';
import '../widgets/budget_range_field.dart';
import '../widgets/location_picker_map.dart';
import '../widgets/posting_field.dart';
import '../widgets/posting_scaffold.dart';
import '../widgets/schedule_selector.dart';
import 'review_and_post_screen.dart';
import '../../../core/constants/app_colors.dart';

/// Step 4 of 5: where the job is, how soon it is needed, what it is worth.
///
/// Every field here is a scoring input, and the captions say so. Location
/// drives proximity and the traffic and weather lookups; the schedule choice
/// flips the urgency-path table; budget feeds the Stage 2 fit score. A client
/// who understands why a field matters fills it in properly, which is worth
/// more to the matcher than a field they filled in to get past it.
///
/// The map pin is the one required answer in the whole flow - without
/// coordinates there is no distance, no travel time and no ranking.
class WhereAndWhenScreen extends StatelessWidget {
  const WhereAndWhenScreen({super.key, required this.posting});

  final JobPostingProvider posting;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: posting,
      builder: (BuildContext context, Widget? _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    return PostingScaffold(
      step: 4,
      title: 'Where and when?',
      subtitle: 'Your location decides who is close enough to reach you.',
      stepName: 'Where & when',
      ctaLabel: 'Continue',
      ctaHint: 'Search, use your location, or tap the map to continue.',
      onCta: posting.canLeaveWhereAndWhen
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ReviewAndPostScreen(posting: posting),
              ),
            )
          : null,
      children: <Widget>[
        const PostingLabel('Job location'),
        const SizedBox(height: AppSizes.xs),
        const Text(
          'Your location decides who is close enough, and lets us check live '
          'traffic and weather before ranking anyone.',
          style: PostingText.caption,
        ),
        const SizedBox(height: AppSizes.md),
        LocationPickerMap(
          latitude: posting.draft.latitude,
          longitude: posting.draft.longitude,
          onChanged: (double lat, double lon, String? address) =>
              posting.setLocation(
                latitude: lat,
                longitude: lon,
                label: address,
              ),
        ),
        const SizedBox(height: AppSizes.sm),
        _LocationReadout(posting: posting),

        const SizedBox(height: AppSizes.xl),
        const PostingLabel('Urgency'),
        const SizedBox(height: AppSizes.md),
        ScheduleSelector(
          value: posting.schedulePreference,
          onChanged: posting.setSchedulePreference,
        ),

        const SizedBox(height: AppSizes.xl),
        const PostingLabel('Budget range'),
        const SizedBox(height: AppSizes.md),
        BudgetRangeField(
          min: posting.draft.budgetMin,
          max: posting.draft.budgetMax,
          onChanged: (double? min, double? max) =>
              posting.setBudget(min: min, max: max),
        ),
      ],
    );
  }
}

class _LocationReadout extends StatelessWidget {
  const _LocationReadout({required this.posting});

  final JobPostingProvider posting;

  @override
  Widget build(BuildContext context) {
    final double? lat = posting.draft.latitude;
    final double? lon = posting.draft.longitude;

    return Row(
      children: <Widget>[
        Icon(
          lat == null ? Icons.location_off_outlined : Icons.place_rounded,
          size: 15,
          color: lat == null ? AppColors.hint : AppColors.primary,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            lat == null
                ? 'No location set yet'
                : (posting.draft.locationLabel?.trim().isNotEmpty ?? false)
                ? posting.draft.locationLabel!
                : '${lat.toStringAsFixed(5)}, ${lon!.toStringAsFixed(5)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: lat == null
                  ? AppColors.textSecondary
                  : AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
