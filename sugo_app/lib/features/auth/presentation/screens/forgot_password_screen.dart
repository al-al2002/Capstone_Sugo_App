import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/ui_feedback.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/sugo_app_bar.dart';
import '../../../onboarding/widgets/otp_code_field.dart';
import '../../data/repositories/auth_repository.dart';
import '../controllers/forgot_password_controller.dart';
import '../widgets/password_requirements.dart';

/// Forgot password: email, then a six-digit code from the inbox, then a new
/// password - all on this one screen. See [ForgotPasswordController] for why
/// it is a code and not a link.
class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ForgotPasswordController>(
      create: (BuildContext context) =>
          ForgotPasswordController(context.read<AuthRepository>()),
      child: const _ForgotPasswordView(),
    );
  }
}

class _ForgotPasswordView extends StatefulWidget {
  const _ForgotPasswordView();

  @override
  State<_ForgotPasswordView> createState() => _ForgotPasswordViewState();
}

class _ForgotPasswordViewState extends State<_ForgotPasswordView> {
  final GlobalKey<FormState> _emailForm = GlobalKey<FormState>();
  final GlobalKey<FormState> _passwordForm = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  /// Bumped on every send, so a fresh code gets fresh, empty boxes.
  int _codeGeneration = 0;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  ForgotPasswordController get _controller =>
      context.read<ForgotPasswordController>();

  void _showError() {
    final String? message = _controller.errorMessage;
    if (message == null) return;
    UiFeedback.showError(context, message);
  }

  Future<void> _sendCode() async {
    FocusScope.of(context).unfocus();
    if (!(_emailForm.currentState?.validate() ?? false)) return;
    final bool sent = await _controller.sendCode(_email.text);
    if (!mounted) return;
    if (sent) {
      setState(() => _codeGeneration++);
    } else {
      _showError();
    }
  }

  Future<void> _resend() async {
    final bool sent = await _controller.resend();
    if (!mounted) return;
    if (sent) {
      setState(() => _codeGeneration++);
      UiFeedback.showSuccess(context, 'A new code is on its way.');
    } else {
      _showError();
    }
  }

  Future<bool> _verify(String code) async {
    final bool ok = await _controller.verifyCode(code);
    if (!mounted) return ok;
    if (ok) {
      // Let the boxes show their green tick before the step changes under
      // them - the tick is the confirmation the person is looking for.
      Future<void>.delayed(const Duration(milliseconds: 650), () {
        if (mounted) _controller.codeAccepted();
      });
    } else {
      _showError();
    }
    return ok;
  }

  Future<void> _setPassword() async {
    FocusScope.of(context).unfocus();
    if (!(_passwordForm.currentState?.validate() ?? false)) return;
    final bool ok = await _controller.setPassword(_password.text);
    if (!mounted) return;
    if (!ok) _showError();
  }

  /// Back to wherever the app is now. After a successful reset the person is
  /// signed in, so the auth gate underneath is already showing their home.
  void _finish() => Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);

  @override
  Widget build(BuildContext context) {
    final ForgotPasswordController c = context.watch<ForgotPasswordController>();

    return PopScope(
      // Mid-request, back would abandon a send or a verify halfway.
      canPop: !c.isBusy,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        // No back arrow once the password is changed: there is nothing to go
        // back to, only "Continue".
        appBar: SugoAppBar(
          surface: true,
          automaticallyImplyLeading: c.step != ForgotStep.done,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(
              AppSizes.screenPadding + AppSizes.xs,
              AppSizes.sm,
              AppSizes.screenPadding + AppSizes.xs,
              AppSizes.xxl,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOutCubic,
                  transitionBuilder: (Widget child, Animation<double> a) =>
                      FadeTransition(
                        opacity: a,
                        child: SlideTransition(
                          position: a.drive(
                            Tween<Offset>(
                              begin: const Offset(0.05, 0),
                              end: Offset.zero,
                            ),
                          ),
                          child: child,
                        ),
                      ),
                  child: KeyedSubtree(
                    key: ValueKey<ForgotStep>(c.step),
                    child: switch (c.step) {
                      ForgotStep.email => _emailStep(c),
                      ForgotStep.code => _codeStep(c),
                      ForgotStep.newPassword => _passwordStep(c),
                      ForgotStep.done => _doneStep(),
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ the steps

  Widget _emailStep(ForgotPasswordController c) {
    return Form(
      key: _emailForm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _StepHeader(
            step: 1,
            icon: Icons.lock_reset_rounded,
            title: 'Forgot your password?',
            subtitle:
                'Enter the email you registered with. We will send you a '
                '6-digit code to reset your password.',
          ),
          AppTextField(
            label: AppStrings.email,
            hint: AppStrings.emailHint,
            controller: _email,
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            validator: Validators.email,
            enabled: !c.isBusy,
            autofillHints: const <String>[AutofillHints.email],
            onSubmitted: (_) => _sendCode(),
          ),
          const SizedBox(height: AppSizes.xl),
          PrimaryButton(
            label: 'Send code',
            isLoading: c.isBusy,
            onPressed: c.isBusy ? null : _sendCode,
          ),
        ],
      ),
    );
  }

  Widget _codeStep(ForgotPasswordController c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _StepHeader(
          step: 2,
          icon: Icons.mark_email_read_outlined,
          title: 'Check your email',
          subtitle:
              'We sent a 6-digit code to ${c.email}. Enter it below - it '
              'works once and expires within the hour.',
        ),
        OtpCodeField(
          key: ValueKey<int>(_codeGeneration),
          enabled: !c.isBusy,
          onCompleted: _verify,
        ),
        const SizedBox(height: AppSizes.lg),
        Row(
          children: <Widget>[
            TextButton(
              onPressed: c.resendIn == 0 && !c.isBusy ? _resend : null,
              child: Text(
                c.resendIn == 0 ? 'Resend code' : 'Resend in ${c.resendIn}s',
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: c.isBusy ? null : c.changeEmail,
              child: const Text('Change email'),
            ),
          ],
        ),
        const SizedBox(height: AppSizes.md),
        const _Hint(
          icon: Icons.info_outline_rounded,
          text:
              'No email? Check your spam folder. If this address has no SUGO '
              'account, no code is sent - we do not say which, so nobody can '
              'use this screen to look people up.',
        ),
      ],
    );
  }

  Widget _passwordStep(ForgotPasswordController c) {
    return Form(
      key: _passwordForm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _StepHeader(
            step: 3,
            icon: Icons.password_rounded,
            title: 'Set a new password',
            subtitle: 'Code confirmed. Choose a new password for your account.',
          ),
          AppTextField(
            label: 'New password',
            hint: AppStrings.createPasswordHint,
            controller: _password,
            icon: Icons.lock_outline_rounded,
            obscure: true,
            validator: Validators.password,
            enabled: !c.isBusy,
            autofillHints: const <String>[AutofillHints.newPassword],
          ),
          const SizedBox(height: AppSizes.sm),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _password,
            builder: (BuildContext _, TextEditingValue value, Widget? _) =>
                PasswordRequirements(password: value.text),
          ),
          const SizedBox(height: AppSizes.lg),
          AppTextField(
            label: AppStrings.confirmPassword,
            hint: AppStrings.confirmPasswordHint,
            controller: _confirm,
            icon: Icons.lock_outline_rounded,
            obscure: true,
            textInputAction: TextInputAction.done,
            enabled: !c.isBusy,
            validator: (String? value) =>
                Validators.confirmPassword(value, _password.text),
            onSubmitted: (_) => _setPassword(),
          ),
          const SizedBox(height: AppSizes.xl),
          PrimaryButton(
            label: 'Update password',
            isLoading: c.isBusy,
            onPressed: c.isBusy ? null : _setPassword,
          ),
        ],
      ),
    );
  }

  Widget _doneStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: AppSizes.xl),
        Center(
          child: Container(
            width: 84,
            height: 84,
            decoration: const BoxDecoration(
              color: AppColors.successSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 46,
              color: AppColors.success,
            ),
          ),
        ),
        const SizedBox(height: AppSizes.xl),
        Text(
          'Password updated',
          textAlign: TextAlign.center,
          style: AppTextStyles.headline,
        ),
        const SizedBox(height: AppSizes.sm),
        Text(
          'You are signed in. Next time, log in with your new password.',
          textAlign: TextAlign.center,
          style: AppTextStyles.subtitle,
        ),
        const SizedBox(height: AppSizes.xxl),
        PrimaryButton(label: 'Continue', onPressed: _finish),
      ],
    );
  }
}

/// "Step 2 of 3", an icon, a title and a sentence of explanation.
class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.step,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final int step;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.secondarySoft,
                  borderRadius: BorderRadius.circular(AppSizes.tileRadius),
                ),
                child: Icon(icon, color: AppColors.secondaryDark, size: 26),
              ),
              const Spacer(),
              // Three short bars, the current one long and navy.
              for (int i = 1; i <= 3; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  margin: const EdgeInsets.only(left: 5),
                  width: i == step ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i <= step ? AppColors.primary : AppColors.border,
                    borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          // Sentence case, like every label since the Dispatch redesign.
          Text(
            'Step $step of 3',
            style: AppTextStyles.overline.copyWith(
              color: AppColors.secondaryDark,
            ),
          ),
          const SizedBox(height: AppSizes.xs),
          Text(title, style: AppTextStyles.headline),
          const SizedBox(height: AppSizes.sm),
          Text(subtitle, style: AppTextStyles.subtitle),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.primarySofter,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.caption,
            ),
          ),
        ],
      ),
    );
  }
}
