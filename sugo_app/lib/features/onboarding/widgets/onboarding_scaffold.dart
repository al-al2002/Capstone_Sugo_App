import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_elevation.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/sugo_app_bar.dart';
import '../../auth/presentation/controllers/auth_controller.dart';
import '../controllers/registration_flow_controller.dart';
import '../models/registration_status.dart';
import 'onboarding_stepper.dart';

/// The shell both registration flows render inside.
///
/// Holds the app bar, the progress rail, the error banner and the footer
/// buttons, so the two flow screens contain only their step bodies. Anything
/// that should look and behave identically for a technician and a client
/// belongs here by construction.
class OnboardingScaffold extends StatelessWidget {
  const OnboardingScaffold({
    super.key,
    required this.controller,
    required this.child,
    required this.onContinue,
    this.continueLabel,
    this.onSaveAndExit,
    this.showFooter = true,
  });

  final RegistrationFlowController controller;
  final Widget child;
  final Future<void> Function() onContinue;

  /// Overrides the footer button label. Steps that submit rather than advance
  /// pass their own.
  final String? continueLabel;

  final Future<void> Function()? onSaveAndExit;

  /// Steps that own their own actions - the assessment list, a queued
  /// identity submission - hide the footer entirely.
  final bool showFooter;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: SugoAppBar(
        // Back steps through the flow; while a step is saving it does
        // nothing, so a half-sent step is never abandoned mid-write.
        onBack: controller.isFirstStep
            ? null
            : () {
                if (!controller.isBusy) controller.back();
              },
        title: controller.role.wire == 'technician'
            ? 'Technician registration'
            : 'Create your account',
        actions: <Widget>[
          if (onSaveAndExit != null)
            SaveAndExitAction(
              step: controller.currentStep,
              onSaveAndExit: onSaveAndExit!,
              isBusy: controller.isBusy,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSizes.screenPadding,
                0,
                AppSizes.screenPadding,
                AppSizes.lg,
              ),
              child: OnboardingStepper(
                steps: controller.steps,
                currentIndex: controller.stepIndex,
                completedSteps: controller.completedSteps,
                onStepTapped: controller.isBusy ? null : controller.goToStep,
              ),
            ),

            if (controller.error != null)
              _ErrorBanner(
                message: controller.error!,
                onDismiss: controller.clearError,
              ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.screenPadding,
                  0,
                  AppSizes.screenPadding,
                  AppSizes.xxl,
                ),
                child: child,
              ),
            ),

            if (showFooter) _footer(context),
          ],
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.screenPadding),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        // Elevated rather than hairlined, matching the posting flow's CTA bar
        // so both of the app's multi-step flows end in the same footer.
        boxShadow: AppElevation.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // The blocked-progress reason, stated rather than left to a greyed
          // button. A disabled Continue with no explanation is the single
          // most common way a user concludes an app is broken.
          if (!controller.canContinue && !controller.isBusy)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.sm + 2),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _blockedReason(controller),
                      style: AppTextStyles.caption,
                    ),
                  ),
                ],
              ),
            ),
          PrimaryButton(
            label:
                continueLabel ??
                (controller.isLastStep ? 'Submit for review' : 'Continue'),
            isLoading: controller.isBusy,
            onPressed: controller.canContinue && !controller.isBusy
                ? () => onContinue()
                : null,
          ),
        ],
      ),
    );
  }

  /// Why the Continue button is disabled, phrased as the next action.
  String _blockedReason(RegistrationFlowController controller) {
    return switch (controller.currentStep) {
      OnboardingStepId.identity =>
        controller.capture.missingLabel ??
            'Both photos are required before you can continue.',
      OnboardingStepId.specialization =>
        'Select at least one device and brand.',
      OnboardingStepId.assessment =>
        'Pass at least one assessment to continue.',
      OnboardingStepId.documents =>
        'Upload an NBI or police clearance to continue.',
      OnboardingStepId.email => 'Enter the code we emailed you to continue.',
      OnboardingStepId.location => 'Set your location to continue.',
      _ => 'Finish this step to continue.',
    };
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        AppSizes.screenPadding,
        0,
        AppSizes.screenPadding,
        AppSizes.md,
      ),
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.errorSoft,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.error_outline_rounded,
            size: 17,
            color: AppColors.error,
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          InkWell(
            onTap: onDismiss,
            child: const Icon(
              Icons.close_rounded,
              size: 16,
              color: AppColors.error,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown once a registration has been filed and there is nothing left to do.
///
/// Always offers a way out. An earlier version made the sign-out button
/// conditional on an `onSignOut` callback, and all three call sites
/// constructed the screen without one - so a user who submitted their ID
/// landed on a screen with no button at all and no way back to the login
/// page. Defaulting to [AuthController.signOut] means a new call site cannot
/// reintroduce that.
class PendingReviewScreen extends StatelessWidget {
  const PendingReviewScreen({
    super.key,
    required this.status,
    this.onSignOut,
    this.onRetake,
    this.rejectionReason,
  });

  final RegistrationStatus status;

  /// Overrides the default sign-out. Null uses [AuthController.signOut], which
  /// is what returns the user to the login screen.
  final VoidCallback? onSignOut;

  final VoidCallback? onRetake;
  final String? rejectionReason;

  @override
  Widget build(BuildContext context) {
    final bool rejected = status == RegistrationStatus.rejected;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.screenPadding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // A haloed glyph, matching `SugoEmptyState`. This screen is the
              // last thing a technician sees before a wait of hours, so it
              // gets the same care as any other terminal state in the app.
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.8, end: 1),
                duration: AppMotion.slow,
                curve: AppMotion.playful,
                builder:
                    (BuildContext context, double scale, Widget? child) =>
                        Transform.scale(scale: scale, child: child),
                child: Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    color:
                        (rejected
                                ? AppColors.errorSoft
                                : AppColors.warningSoft)
                            .withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: rejected
                          ? AppColors.errorSoft
                          : AppColors.warningSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(status.icon, size: 36, color: status.tone),
                  ),
                ),
              ),
              const SizedBox(height: AppSizes.xl),
              Text(
                rejected
                    ? 'We could not verify your ID'
                    : 'Thanks — you are all set',
                textAlign: TextAlign.center,
                style: AppTextStyles.headline,
              ),
              const SizedBox(height: AppSizes.md),
              Text(
                rejectionReason ?? status.blurb,
                textAlign: TextAlign.center,
                style: AppTextStyles.subtitle,
              ),
              const SizedBox(height: AppSizes.xxl),

              if (rejected && onRetake != null)
                PrimaryButton(label: 'Retake my photos', onPressed: onRetake)
              else
                Container(
                  padding: const EdgeInsets.all(AppSizes.lg),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppSizes.tileRadius),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Row(
                    children: <Widget>[
                      Icon(
                        Icons.notifications_active_outlined,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: AppSizes.md),
                      Expanded(
                        child: Text(
                          'We will notify you as soon as your account is '
                          'approved. You can close the app in the meantime.',
                          style: AppTextStyles.caption,
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: AppSizes.lg),

              // Signing out does not withdraw the application, and saying so
              // matters: without it, "back to login" reads as "cancel", and
              // someone waiting on review will sit on this screen rather than
              // risk losing their place.
              const Text(
                'Your application stays in the queue while you are signed out.',
                textAlign: TextAlign.center,
                style: AppTextStyles.caption,
              ),
              const SizedBox(height: AppSizes.md),

              OutlinedButton.icon(
                onPressed:
                    onSignOut ?? () => context.read<AuthController>().signOut(),
                icon: const Icon(Icons.logout_rounded, size: 17),
                label: const Text('Back to login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
