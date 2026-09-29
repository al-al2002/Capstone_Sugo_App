import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_app_bar.dart';
import '../../auth/presentation/controllers/auth_controller.dart';

/// Shown to a technician whose account exists but is not verified.
///
/// ## Why this is no longer the onboarding flow
///
/// It used to host the ID, specialisation and quiz steps. Those moved to
/// `RegistrationFlowScreen`, because registration now writes nothing until it
/// completes - and a technician row can only be created by passing the
/// assessment.
///
/// So reaching this screen means something specific: the account was created
/// verified, and verification was **later removed** by an administrator. It is
/// not a step in a flow, it is a suspended account. Re-running onboarding
/// would be wrong; there is nothing left for the technician to submit.
class TechnicianOnboardingScreen extends StatelessWidget {
  const TechnicianOnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final SessionController session = context.watch<SessionController>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: SugoAppBar(
        automaticallyImplyLeading: false,
        title: 'Account under review',
        actions: <Widget>[
          IconButton(
            onPressed: () => context.read<AuthController>().signOut(),
            icon: const Icon(Icons.logout_rounded, size: 20),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSizes.screenPadding,
            AppSizes.xl,
            AppSizes.screenPadding,
            AppSizes.xxl,
          ),
          children: <Widget>[
            Center(
              child: Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  color: AppColors.warningSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.pause_circle_outline_rounded,
                  size: 42,
                  color: AppColors.warning,
                ),
              ),
            ),
            const SizedBox(height: AppSizes.lg),
            Text(
              'Verification paused',
              textAlign: TextAlign.center,
              style: AppTextStyles.headline,
            ),
            const SizedBox(height: AppSizes.xs),
            Text(
              'Your technician account is active but not currently verified, '
              'so the matcher will not offer you jobs. This usually means an '
              'administrator has paused it for review.',
              textAlign: TextAlign.center,
              style: AppTextStyles.subtitle,
            ),
            const SizedBox(height: AppSizes.xl),

            SugoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 17,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: AppSizes.sm),
                      Text('What you can do', style: AppTextStyles.label),
                    ],
                  ),
                  const SizedBox(height: AppSizes.sm),
                  Text(
                    'Nothing is required from you - your ID and assessment are '
                    'already on file. Contact SUGO support to have the review '
                    'completed. Your rating and job history are untouched.',
                    style: AppTextStyles.caption,
                  ),
                  const SizedBox(height: AppSizes.lg),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: session.isLoading
                          ? null
                          : () => _recheck(context, session),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(
                        session.isLoading ? 'Checking...' : 'Check again',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _recheck(BuildContext context, SessionController session) async {
    await session.refresh();
    if (!context.mounted) return;
    // The gate reacts on its own when verification returns; this only reports
    // the unchanged case so a tap never looks like it did nothing.
    UiFeedback.showInfo(
      context,
      'Still paused. We will move you across as soon as it clears.',
    );
  }
}
