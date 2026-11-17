import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../models/technician_preferences.dart';
import '../providers/job_posting_provider.dart';
import '../widgets/posting_scaffold.dart';
import '../widgets/preference_controls.dart';
import 'symptom_screen.dart';

/// Step 2 of 6: does the client have any must-haves for their technician?
///
/// The client preference pre-filter (2026-11-15). Four optional hard gates -
/// specialisation, distance, rating, trust badge - each a fixed set of
/// options defaulting to "No preference". The engine removes anyone who fails
/// one before RB-CARS scores the rest; see `scoring/preferences.ts`.
///
/// ## Why there is no "Availability" question (removed 2026-11-17)
///
/// It used to be a fifth gate: "No preference / Available now / Pick a date".
/// The user had it removed. Availability is already handled without asking:
/// a technician on time off cannot be booked, and the matcher scores
/// workload. Matching runs straight after posting, so the "date" option was a
/// promise about a day the booking was not for. The `pref_availability` and
/// `pref_available_on` columns and the engine's check are left in place, so
/// jobs posted before the removal still match the way they were posted, and a
/// new job writes null there, which filters nobody.
///
/// ## Why it comes this early
///
/// The brief asks for the preferences before the problem is described. It
/// also reads better: "who do you want?" is a question about the client, and
/// asking it before the details keeps the later steps about the device. The
/// distance is measured to the pin the client drops on step 5, which the
/// caption says, so nothing here depends on an answer not given yet.
///
/// ## Why it never blocks
///
/// Every field is optional and the button always works. Its label says what
/// will happen - "Continue without preferences" or "Continue with 2
/// preferences" - so skipping is a visible choice, not a missed field.
class TechnicianPreferencesScreen extends StatelessWidget {
  const TechnicianPreferencesScreen({super.key, required this.posting});

  final JobPostingProvider posting;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: posting,
      builder: (BuildContext context, Widget? _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final TechnicianPreferences prefs = posting.preferences;
    final int count = prefs.active.length;

    return PostingScaffold(
      step: 2,
      title: 'Any must-haves?',
      subtitle: 'All optional. Skip this and SUGO ranks everyone nearby.',
      stepName: 'Your technician',
      ctaLabel: count == 0
          ? 'Continue without preferences'
          : 'Continue with $count preference${count == 1 ? '' : 's'}',
      onCta: posting.canLeavePreferences
          ? () => Navigator.of(context).push(
              PostingRoute<void>(
                builder: (_) => SymptomScreen(posting: posting),
              ),
            )
          : null,
      children: <Widget>[
        const PreferencesExplainer(),
        const SizedBox(height: AppSizes.xl),

        PreferenceDropdown<PreferredSpecialization>(
          label: 'Specialization',
          icon: Icons.handyman_rounded,
          value: prefs.specialization,
          options: PreferredSpecialization.forCategory(posting.deviceCategory),
          optionLabel: (PreferredSpecialization s) => s.label,
          optionBlurb: (PreferredSpecialization s) => s.blurb,
          caption: 'Only technicians who list this skill.',
          onChanged: (PreferredSpecialization? value) => posting.setPreferences(
            prefs.copyWith(specialization: () => value),
          ),
        ),
        const SizedBox(height: AppSizes.xl),

        PreferenceDropdown<MaxDistance>(
          label: 'Maximum distance',
          icon: Icons.near_me_rounded,
          value: prefs.maxDistance,
          options: MaxDistance.values,
          optionLabel: (MaxDistance d) => d.label,
          caption:
              "Straight line from the technician's base to the pin you drop "
              'later.',
          onChanged: (MaxDistance? value) =>
              posting.setPreferences(prefs.copyWith(maxDistance: () => value)),
        ),
        const SizedBox(height: AppSizes.xl),

        PreferenceDropdown<MinRating>(
          label: 'Minimum rating',
          icon: Icons.star_outline_rounded,
          value: prefs.minRating,
          options: MinRating.values,
          optionLabel: (MinRating r) => r.label,
          optionLeading: (MinRating r) =>
              const Icon(Icons.star_rounded, size: 16, color: AppColors.accent),
          // The one surprising consequence, said before it happens.
          caption: 'Technicians with no reviews yet are left out.',
          onChanged: (MinRating? value) =>
              posting.setPreferences(prefs.copyWith(minRating: () => value)),
        ),
        const SizedBox(height: AppSizes.xl),

        PreferenceDropdown<TrustBadge>(
          label: 'Trust badge',
          icon: Icons.verified_user_outlined,
          value: prefs.minTrust,
          options: TrustBadge.values,
          optionLabel: (TrustBadge t) => t.label,
          optionBlurb: trustPreferenceBlurb,
          caption: 'Each level includes the ones above it.',
          onChanged: (TrustBadge? value) =>
              posting.setPreferences(prefs.copyWith(minTrust: () => value)),
        ),

        if (prefs.hasAny) ...<Widget>[
          const SizedBox(height: AppSizes.md),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: posting.resetPreferences,
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('Reset all'),
            ),
          ),
        ],
      ],
    );
  }
}
