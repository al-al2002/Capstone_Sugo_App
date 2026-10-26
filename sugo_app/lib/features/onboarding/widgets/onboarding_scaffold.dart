import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_elevation.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/sugo_app_bar.dart';
import '../../../core/widgets/sugo_timeline.dart';
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
///
/// ## The redesign (2026-09-29)
///
/// It was a glyph, two lines and a note, floating in the middle of an empty
/// page - fine as an error state, thin as the last screen of a registration
/// someone has just put ten minutes into. Now it shows what happens next the
/// way the rest of the app shows a booking's progress: three honest steps,
/// the current one lit, with the notification promise where it belongs, on
/// the last step. The whole page scrolls, so a small phone or large text
/// never pushes "Back to login" off the screen.
class PendingReviewScreen extends StatefulWidget {
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
  State<PendingReviewScreen> createState() => _PendingReviewScreenState();
}

class _PendingReviewScreenState extends State<PendingReviewScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );
  bool _isLeaving = false;

  Future<void> _backToLogin() async {
    if (_isLeaving) return;
    setState(() => _isLeaving = true);
    final Future<void> signOut = widget.onSignOut != null
        ? Future<void>.sync(widget.onSignOut!)
        : context.read<AuthController>().signOut();
    await _exit.forward();
    await signOut;
  }

  @override
  void dispose() {
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool rejected = widget.status == RegistrationStatus.rejected;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            final Widget content = SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSizes.screenPadding,
                AppSizes.screenPadding,
                AppSizes.screenPadding,
                AppSizes.screenPadding,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: box.maxHeight - AppSizes.screenPadding * 2,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Center(child: _StatusHalo(status: widget.status)),
                    const SizedBox(height: AppSizes.xl),
                    Text(
                      rejected
                          ? 'We could not verify your ID'
                          : 'Thanks — you are all set',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.headline,
                    ),
                    const SizedBox(height: AppSizes.sm),
                    Text(
                      widget.rejectionReason ?? widget.status.blurb,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.subtitle,
                    ),
                    const SizedBox(height: AppSizes.xl),

                    if (rejected && widget.onRetake != null)
                      PrimaryButton(
                        label: 'Retake my photos',
                        onPressed: _isLeaving ? null : widget.onRetake,
                      )
                    else if (!rejected)
                      const _WhatHappensNext(),

                    const SizedBox(height: AppSizes.xl),
                    SizedBox(
                      height: AppSizes.buttonHeight,
                      child: OutlinedButton.icon(
                        onPressed: _isLeaving ? null : _backToLogin,
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: _isLeaving
                              ? const SizedBox(
                                  key: ValueKey<String>('leaving'),
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.arrow_back_rounded,
                                  key: ValueKey<String>('back'),
                                  size: 18,
                                ),
                        ),
                        label: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: Text(
                            _isLeaving
                                ? 'Returning to login...'
                                : 'Back to login',
                            key: ValueKey<bool>(_isLeaving),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSizes.sm),
                    // Signing out does not withdraw the application, and
                    // saying so matters: without it, "back to login" reads as
                    // "cancel", and someone waiting on review will sit on this
                    // screen rather than risk losing their place.
                    const Text(
                      'Your application stays in the queue while you are '
                      'signed out.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
            );

            return AnimatedBuilder(
              animation: _exit,
              child: content,
              builder: (BuildContext context, Widget? child) {
                final double scale = 1 - (_exit.value * 0.035);
                return Opacity(
                  opacity: 1 - _exit.value,
                  child: Transform.scale(scale: scale, child: child),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// The status glyph in two soft rings. Scales in once, and the outer ring
/// breathes out a single time behind it - an arrival, not a loop, because
/// the wait that follows can be hours and a spinner would say "stuck".
class _StatusHalo extends StatelessWidget {
  const _StatusHalo({required this.status});

  final RegistrationStatus status;

  @override
  Widget build(BuildContext context) {
    final bool rejected = status == RegistrationStatus.rejected;
    final Color wash = rejected ? AppColors.errorSoft : AppColors.warningSoft;
    final bool still = AppMotion.reduced(context);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: still ? 1 : 0, end: 1),
      duration: still ? Duration.zero : const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double t, Widget? glyph) {
        // The glyph lands in the first half; the ring widens after it.
        final double pop = AppMotion.playful.transform((t * 2).clamp(0, 1));
        final double ring = ((t - 0.3) / 0.7).clamp(0, 1);
        return SizedBox(
          width: 128,
          height: 128,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Container(
                width: 88 + 40 * ring,
                height: 88 + 40 * ring,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: wash.withValues(alpha: 0.55 * ring),
                ),
              ),
              Transform.scale(scale: 0.6 + 0.4 * pop, child: glyph),
            ],
          ),
        );
      },
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          color: wash,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.surface, width: 4),
          boxShadow: AppElevation.sm,
        ),
        child: Icon(status.icon, size: 38, color: status.tone),
      ),
    );
  }
}

/// Registered, being reviewed, live - with the promise to notify on the step
/// it belongs to.
class _WhatHappensNext extends StatelessWidget {
  const _WhatHappensNext();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('What happens next', style: AppTextStyles.sectionTitle),
          const SizedBox(height: AppSizes.md),
          // Not compact: compact hides every subtitle but the current one,
          // and the last step's "we will notify you" is the promise people
          // need before they close the app.
          const SugoTimeline(
            steps: <SugoTimelineStep>[
              SugoTimelineStep(
                title: 'Registration sent',
                subtitle: 'Your details and ID photos are in.',
                icon: Icons.assignment_turned_in_rounded,
                state: SugoStepState.done,
              ),
              SugoTimelineStep(
                title: 'ID review',
                subtitle:
                    'A member of the SUGO team checks your ID. This usually '
                    'takes under a day.',
                icon: Icons.fact_check_rounded,
                state: SugoStepState.current,
              ),
              SugoTimelineStep(
                title: 'Account goes live',
                subtitle:
                    'We will notify you as soon as it is approved. You can '
                    'close the app in the meantime.',
                icon: Icons.notifications_active_rounded,
                state: SugoStepState.upcoming,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
