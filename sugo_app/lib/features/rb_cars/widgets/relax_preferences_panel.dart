import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/primary_button.dart';
import '../models/technician_preferences.dart';

/// "No technician matches your preferences - try relaxing them."
///
/// What the review screen shows instead of an empty list when the engine
/// answers `no_match_relax_preferences`. The brief's edge case: an impossible
/// combination must lead somewhere, not to a blank screen.
///
/// ## Why chips, one per preference
///
/// "Try relaxing them" alone leaves the client guessing which one. Each
/// preference they set is a chip; tapping it removes just that one and runs
/// RB-CARS again. When the engine sent `relax_hints`, each chip also carries
/// how many technicians removing it would bring back, and the most useful one
/// is marked - so the choice is informed, not trial and error.
class RelaxPreferencesPanel extends StatelessWidget {
  const RelaxPreferencesPanel({
    super.key,
    required this.preferences,
    required this.hints,
    required this.onRelax,
    required this.onSearchAgain,
    this.message,
  });

  final TechnicianPreferences preferences;
  final List<RelaxHint> hints;

  /// The engine's own sentence, e.g. which preference to relax first.
  final String? message;

  /// Called with the looser set: one preference removed, or none at all.
  final ValueChanged<TechnicianPreferences> onRelax;

  /// Same preferences, run again - someone may have come back from leave.
  final VoidCallback onSearchAgain;

  @override
  Widget build(BuildContext context) {
    final Map<PreferenceField, int> counts = <PreferenceField, int>{
      for (final RelaxHint hint in hints) hint.field: hint.wouldMatch,
    };
    final int best = counts.values.fold(0, (int a, int b) => a > b ? a : b);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            color: AppColors.accentSoft,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.tune_rounded,
            size: 30,
            color: AppColors.accentDark,
          ),
        ),
        const SizedBox(height: AppSizes.lg),
        Text(
          'No technician matches your preferences',
          textAlign: TextAlign.center,
          style: AppTextStyles.headline,
        ),
        const SizedBox(height: AppSizes.xs),
        Text(
          message ?? 'Try relaxing one of them. Your job is saved.',
          textAlign: TextAlign.center,
          style: AppTextStyles.subtitle,
        ),
        const SizedBox(height: AppSizes.xl),
        Text(
          'Tap a preference to remove it',
          style: AppTextStyles.micro.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSizes.sm),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSizes.sm,
          runSpacing: AppSizes.sm,
          children: <Widget>[
            for (final PreferenceField field in preferences.active)
              _RelaxChip(
                label: preferences.labelFor(field),
                wouldMatch: counts[field],
                highlighted: best > 0 && counts[field] == best,
                onTap: () => onRelax(preferences.without(field)),
              ),
          ],
        ),
        const SizedBox(height: AppSizes.xl),
        PrimaryButton(
          label: 'Clear all and search again',
          icon: Icons.restart_alt_rounded,
          onPressed: () => onRelax(TechnicianPreferences.none),
        ),
        const SizedBox(height: AppSizes.sm),
        TextButton(
          onPressed: onSearchAgain,
          child: const Text('Search again with the same preferences'),
        ),
      ],
    );
  }
}

class _RelaxChip extends StatelessWidget {
  const _RelaxChip({
    required this.label,
    required this.wouldMatch,
    required this.highlighted,
    required this.onTap,
  });

  final String label;

  /// Technicians this removal brings back, or null when the engine did not
  /// say (a decline-cascade run, or reopened from the dashboard).
  final int? wouldMatch;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final int? count = wouldMatch;
    final String consequence = count == null
        ? ''
        : count == 0
        ? ' On its own, removing it brings back nobody.'
        : ' Removing it brings back $count technician${count == 1 ? '' : 's'}.';

    return Semantics(
      button: true,
      label: 'Remove $label.$consequence',
      excludeSemantics: true,
      child: Material(
        color: highlighted ? AppColors.secondarySoft : AppColors.surface,
        shape: StadiumBorder(
          side: BorderSide(
            color: highlighted ? AppColors.secondary : AppColors.border,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSizes.touchTarget),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSizes.md,
                AppSizes.xs,
                AppSizes.sm,
                AppSizes.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (count != null && count > 0) ...<Widget>[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.successSoft,
                        borderRadius: BorderRadius.circular(
                          AppSizes.pillRadius,
                        ),
                      ),
                      child: Text(
                        '+$count',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.success,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: AppSizes.xs),
                  const Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
