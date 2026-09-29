import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/utils/ui_feedback.dart';
import '../controllers/client_registration_controller.dart';
import '../models/client_onboarding_models.dart';
import '../models/registration_status.dart';
import '../widgets/id_verification_step.dart';
import '../widgets/location_pin_step.dart';
import '../widgets/onboarding_scaffold.dart';
import '../widgets/otp_code_field.dart';

/// The five-step client registration flow.
///
/// account -> ID + selfie -> email code -> location -> review
class ClientRegistrationScreen extends StatelessWidget {
  const ClientRegistrationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ClientRegistrationController>(
      create: (_) => ClientRegistrationController()..load(),
      child: const _ClientRegistrationView(),
    );
  }
}

class _ClientRegistrationView extends StatelessWidget {
  const _ClientRegistrationView();

  @override
  Widget build(BuildContext context) {
    final ClientRegistrationController controller = context
        .watch<ClientRegistrationController>();

    if (controller.isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (controller.status == RegistrationStatus.pendingReview) {
      return const PendingReviewScreen(
        status: RegistrationStatus.pendingReview,
      );
    }

    return OnboardingScaffold(
      controller: controller,
      onSaveAndExit: () async {
        await controller.saveAndExit();
        if (!context.mounted) return;
        Navigator.of(context).maybePop();
      },
      // The footer stays visible on the identity step even while a submission
      // is under review: the panel promises the user can carry on, and hiding
      // the button contradicted that. See the note in the technician screen.
      continueLabel: switch (controller.currentStep) {
        OnboardingStepId.identity when !controller.hasSubmittedIdentity =>
          'Submit ID for verification',
        OnboardingStepId.identity => 'Continue',
        OnboardingStepId.review => 'Submit for review',
        _ => null,
      },
      onContinue: () => _onContinue(context, controller),
      child: _body(controller),
    );
  }

  Future<void> _onContinue(
    BuildContext context,
    ClientRegistrationController controller,
  ) async {
    if (controller.currentStep == OnboardingStepId.identity &&
        !controller.hasSubmittedIdentity) {
      final bool ok = await controller.submitIdentity();
      if (!context.mounted) return;
      if (ok) {
        UiFeedback.showSuccess(context, 'ID submitted. Just two more steps.');
      }
      return;
    }

    if (controller.isLastStep) {
      final bool ok = await controller.submitForReview();
      if (!context.mounted) return;
      if (ok) {
        UiFeedback.showSuccess(context, 'Registration submitted for review.');
      }
      return;
    }

    await controller.next();
  }

  Widget _body(ClientRegistrationController controller) {
    return switch (controller.currentStep) {
      OnboardingStepId.account => const _ClientAccountRecap(),

      OnboardingStepId.identity => IdVerificationStep(
        capture: controller.capture,
        validation: controller.validation,
        onIdPicked: controller.pickIdDocument,
        onSelfiePicked: controller.pickSelfie,
        isUploading: controller.isBusy,
        rejection: controller.rejection,
        submitted: controller.filedSubmission,
      ),

      OnboardingStepId.email => _EmailStep(controller: controller),

      OnboardingStepId.location => _ClientLocationStep(controller: controller),

      OnboardingStepId.review => _ClientReview(controller: controller),

      // Not part of the client flow.
      OnboardingStepId.specialization ||
      OnboardingStepId.assessment ||
      OnboardingStepId.documents => const SizedBox.shrink(),
    };
  }
}

class _ClientAccountRecap extends StatelessWidget {
  const _ClientAccountRecap();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('Welcome to SUGO', style: AppTextStyles.headline),
        const SizedBox(height: AppSizes.sm),
        const Text(
          'Three quick steps before you can book a technician.',
          style: AppTextStyles.subtitle,
        ),
        const SizedBox(height: AppSizes.xl),
        ...<({String title, String blurb, IconData icon})>[
          (
            title: 'Verify your identity',
            blurb:
                'A government ID and a selfie holding it. Technicians are '
                'verified too — this is the same check, both ways.',
            icon: Icons.badge_outlined,
          ),
          (
            title: 'Confirm your mobile number',
            blurb: 'So your technician can reach you on the day.',
            icon: Icons.phone_iphone_rounded,
          ),
          (
            title: 'Set your default address',
            blurb: 'Where most of your bookings will be.',
            icon: Icons.home_outlined,
          ),
        ].map(
          (({String title, String blurb, IconData icon}) item) => Padding(
            padding: const EdgeInsets.only(bottom: AppSizes.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(AppSizes.sm),
                  ),
                  child: Icon(item.icon, size: 18, color: AppColors.primary),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(item.blurb, style: AppTextStyles.caption),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Step 3. Send a code to the account's email, then type it back.
///
/// ## How verification actually works
///
/// **GoTrue mails the code and GoTrue checks it.** `signInWithOtp` issues a
/// six-digit one-time code, and the typed code goes straight back to
/// `verifyOTP`. The app never sees the correct answer, so it cannot be talked
/// into accepting a wrong one.
///
/// **Nothing is stored.** `email_confirmed_at` was already true at signup -
/// this project has Confirm email switched off - so there is no column to set.
/// The result lives in the flow, and `profiles.registration_step` carries it
/// across a resume. A live check, not a stored credential.
///
/// **There is nothing to type but the code.** The address is the one the client
/// signed up with, read from the session. A field to edit it would only invite
/// verifying an address the account does not use.
///
/// One setup step lives outside this file: Supabase's default template mails a
/// magic link, so the six-digit code only appears once the template includes
/// the `{{ .Token }}` placeholder, under Authentication -> Email Templates.
class _EmailStep extends StatefulWidget {
  const _EmailStep({required this.controller});

  final ClientRegistrationController controller;

  @override
  State<_EmailStep> createState() => _EmailStepState();
}

class _EmailStepState extends State<_EmailStep> {
  final TextEditingController _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ClientRegistrationController c = widget.controller;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('Confirm your email', style: AppTextStyles.headline),
        const SizedBox(height: AppSizes.sm),
        const Text(
          'We send a six-digit code to the address you signed up with. It '
          'confirms we can reach you about a booking.',
          style: AppTextStyles.subtitle,
        ),
        const SizedBox(height: AppSizes.xl),

        if (c.isEmailStepSatisfied)
          _verified(c)
        else if (c.emailState == EmailVerificationState.awaitingCode)
          _codeEntry(c)
        else
          _sendPrompt(c),
      ],
    );
  }

  Widget _sendPrompt(ClientRegistrationController c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _AddressCard(email: c.emailLabel),
        const SizedBox(height: AppSizes.lg),
        PrimaryButton(
          label: 'Send code',
          isLoading: c.isBusy,
          onPressed: c.isBusy ? null : c.sendCode,
        ),

        // A failed first send used to land nowhere. The message was set, the
        // step stayed on this branch, and this branch did not draw it - so the
        // button appeared to do nothing at all, which is the one thing a
        // button must never appear to do.
        if (c.emailError != null) ...<Widget>[
          const SizedBox(height: AppSizes.md),
          _SendError(message: c.emailError!),
        ],
      ],
    );
  }

  Widget _codeEntry(ClientRegistrationController c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(AppSizes.md),
          decoration: BoxDecoration(
            color: AppColors.primarySofter,
            borderRadius: BorderRadius.circular(AppSizes.tileRadius),
          ),
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.mark_email_unread_outlined,
                size: 17,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: Text(
                  'Code sent to ${c.emailLabel}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSizes.lg),

        // No Verify button. Six boxes that submit themselves remove the one
        // step nobody wants: typing a code correctly and then being asked to
        // confirm that they meant it.
        OtpCodeField(
          key: ValueKey<int>(c.resendIn == 0 ? 0 : 1),
          enabled: !c.isBusy,
          onCompleted: (String code) => _verify(c, code),
        ),
        const SizedBox(height: AppSizes.lg),

        Row(
          children: <Widget>[
            TextButton(
              onPressed: c.canResend && !c.isBusy ? c.sendCode : null,
              child: Text(
                c.canResend ? 'Resend code' : 'Resend in ${c.resendIn}s',
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: c.isBusy ? null : c.restartVerification,
              child: const Text('Start over'),
            ),
          ],
        ),

        // Send failures and rate limits land here, beside the button that
        // triggered them, rather than in the scaffold's banner - which sits
        // above the scroll view and is off-screen by the time anyone is
        // looking at the code boxes.
        if (c.emailError != null) ...<Widget>[
          const SizedBox(height: AppSizes.sm),
          _SendError(message: c.emailError!),
        ],
      ],
    );
  }

  /// Verifies, and on success lets the tick land before moving on.
  ///
  /// The 600ms is the whole point of the delay: advancing the instant the
  /// server answers would swap the screen out from under the animation that
  /// exists to tell the user it worked.
  Future<bool> _verify(ClientRegistrationController c, String code) async {
    final bool ok = await c.verifyCode(code);
    if (!ok) return false;

    // Scheduled, not awaited. Returning `true` is what tells the field to turn
    // green and pop its tick, so awaiting the delay here meant advancing the
    // step *before* the field was ever told it had succeeded - and the
    // animation that exists to say "that worked" played to a disposed widget.
    //
    // 600ms is measured from this point rather than from the tap: it is the
    // tick's time on screen, not a guess at how long the request took.
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      if (mounted) c.next();
    });

    return true;
  }

  Widget _verified(ClientRegistrationController c) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: AppColors.successSoft,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.verified_rounded,
            size: 22,
            color: AppColors.success,
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Email confirmed',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(c.emailLabel, style: AppTextStyles.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Why a send failed, drawn wherever the send was triggered from.
///
/// Loud enough to be read. The first version of this was caption-grey text and
/// it disappeared into the layout next to a large blue button, which is how a
/// failing send came to look like an unresponsive one.
class _SendError extends StatelessWidget {
  const _SendError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
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
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The address the code goes to, shown but not editable.
class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: AppColors.fieldFill,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.alternate_email_rounded,
            size: 20,
            color: AppColors.primary,
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Your account email', style: AppTextStyles.caption),
                const SizedBox(height: 2),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Step 4. The map, plus a label for the address.
class _ClientLocationStep extends StatelessWidget {
  const _ClientLocationStep({required this.controller});

  final ClientRegistrationController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        LocationPinStep(
          place: controller.place,
          onPlaceChanged: controller.setPlace,
          title: 'Where should we send technicians?',
          subtitle:
              'Set your usual address. You can add more later and change it '
              'per booking.',
        ),
        const SizedBox(height: AppSizes.xl),

        const Text(
          'Label this address',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppSizes.sm),
        Wrap(
          spacing: AppSizes.sm,
          children: SavedAddress.suggestedLabels
              .map((String label) {
                final bool selected = controller.addressLabel == label;
                return ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) => controller.setAddressLabel(label),
                  selectedColor: AppColors.primarySoft,
                  labelStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                );
              })
              .toList(growable: false),
        ),
      ],
    );
  }
}

/// Step 5. Summary before submitting.
class _ClientReview extends StatelessWidget {
  const _ClientReview({required this.controller});

  final ClientRegistrationController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('Check and submit', style: AppTextStyles.headline),
        const SizedBox(height: AppSizes.sm),
        const Text(
          'A SUGO reviewer checks your ID before your account goes live. '
          'This usually takes under a day.',
          style: AppTextStyles.subtitle,
        ),
        const SizedBox(height: AppSizes.xl),

        _row(
          icon: Icons.badge_outlined,
          title: 'Identity',
          value: controller.hasSubmittedIdentity
              ? 'ID and selfie submitted'
              : 'Not submitted',
          isComplete: controller.hasSubmittedIdentity,
        ),
        // Shown as account information, not as a verified claim. With email
        // confirmation switched off in the project, GoTrue marks every user
        // confirmed at signup - so a tick here would assert something nobody
        // actually proved.
        _row(
          icon: Icons.alternate_email_rounded,
          title: 'Email',
          value: controller.emailLabel,
          isComplete: true,
        ),
        _row(
          icon: Icons.home_outlined,
          title: controller.addressLabel,
          value: controller.place?.displayText ?? 'Not set',
          isComplete: controller.hasAddress,
        ),

        const SizedBox(height: AppSizes.lg),
        Container(
          padding: const EdgeInsets.all(AppSizes.md),
          decoration: BoxDecoration(
            color: AppColors.primarySofter,
            borderRadius: BorderRadius.circular(AppSizes.tileRadius),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.shield_outlined, size: 16, color: AppColors.primary),
              SizedBox(width: AppSizes.sm),
              Expanded(
                child: Text(
                  'You will start as a New client. Once your ID is approved '
                  'you become Verified, which technicians can see when they '
                  'accept your bookings.',
                  style: AppTextStyles.caption,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row({
    required IconData icon,
    required String title,
    required String value,
    required bool isComplete,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.md),
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(value, style: AppTextStyles.caption),
              ],
            ),
          ),
          Icon(
            isComplete
                ? Icons.check_circle_rounded
                : Icons.error_outline_rounded,
            size: 17,
            color: isComplete ? AppColors.success : AppColors.error,
          ),
        ],
      ),
    );
  }
}
