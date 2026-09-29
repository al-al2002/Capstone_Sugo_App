import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/session/session_state.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/sugo_card.dart';

/// "Continue as a client" or "Continue as a technician".
///
/// Purely presentational: it reports the choice through [onChosen] and writes
/// nothing itself. What the caller does with the answer differs by flow, and
/// both callers are live:
///
/// * `RegistrationEntryScreen` (current) persists it immediately via
///   `OnboardingService.chooseRole`, so the registration can be resumed.
/// * `RegistrationFlowScreen` (legacy) holds it in memory until the whole
///   registration commits at once.
///
/// The second was the original design, and this comment used to describe it as
/// the point of the screen. Migration 20260907000001 reversed that: partial
/// state is now written as the user goes, because "save and continue later"
/// cannot work without it.
///
/// Supplies no Scaffold - each host provides its own app bar and step rail.
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key, required this.onChosen});

  final void Function(UserRole role) onChosen;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPadding,
        AppSizes.lg,
        AppSizes.screenPadding,
        AppSizes.xxl,
      ),
      children: <Widget>[
        Text('How will you use SUGO?', style: AppTextStyles.headline),
        const SizedBox(height: AppSizes.xs),
        Text(
          'This sets up your app. You will not be asked again.',
          style: AppTextStyles.subtitle,
        ),
        const SizedBox(height: AppSizes.xl),

        _RoleCard(
          title: 'Continue as a client',
          blurb:
              'Post a repair job and let RB-CARS rank the three best '
              'technicians near you.',
          icon: Icons.person_search_rounded,
          accent: AppColors.primary,
          tint: AppColors.primarySofter,
          bullets: const <String>[
            'One quick ID check, then start booking',
            'No skills assessment or tier',
            'Track jobs and rate technicians',
          ],
          onTap: () => onChosen(UserRole.client),
        ),
        const SizedBox(height: AppSizes.lg),

        _RoleCard(
          title: 'Continue as a technician',
          blurb:
              'Receive matched repair jobs. Requires a valid ID and a short '
              'skills assessment.',
          icon: Icons.engineering_rounded,
          // The text orange: the bright one is 2.1:1 on white, too faint for
          // an icon that carries meaning.
          accent: AppColors.accentDark,
          tint: AppColors.accentSofter,
          bullets: const <String>[
            'Upload a government ID',
            'Pass a 10-question assessment',
            'Your score sets your starting tier',
          ],
          onTap: () => onChosen(UserRole.technician),
        ),

        const SizedBox(height: AppSizes.xl),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(
              Icons.info_outline_rounded,
              size: 15,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: Text(
                'Choose carefully. Switching roles later needs support, '
                'because a technician account carries verification and a work '
                'history that a client account does not.',
                style: AppTextStyles.caption,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.title,
    required this.blurb,
    required this.icon,
    required this.accent,
    required this.tint,
    required this.bullets,
    required this.onTap,
  });

  final String title;
  final String blurb;
  final IconData icon;
  final Color accent;
  final Color tint;
  final List<String> bullets;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // A SugoCard since the Dispatch redesign: flat with the hairline edge
    // and the shared press response, instead of a hand-built shadowed box.
    return SugoCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: AppSizes.iconTile,
                height: AppSizes.iconTile,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(AppSizes.radius),
                ),
                child: Icon(icon, size: 24, color: accent),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(child: Text(title, style: AppTextStyles.sectionTitle)),
              Icon(Icons.arrow_forward_rounded, size: 20, color: accent),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          Text(blurb, style: AppTextStyles.caption),
          const SizedBox(height: AppSizes.md),
          ...bullets.map(
            (String bullet) => Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.xs + 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(
                    child: Text(
                      bullet,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
