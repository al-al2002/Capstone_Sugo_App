import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/ui_feedback.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/staggered_entrance.dart';
import '../../data/repositories/auth_repository.dart';
import '../controllers/register_controller.dart';
import 'auth_tab.dart';
import 'password_requirements.dart';

/// Account creation: full name, email and password.
class RegisterForm extends StatefulWidget {
  const RegisterForm({super.key, required this.onSwitchTab});

  final ValueChanged<AuthTab> onSwitchTab;

  @override
  State<RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<RegisterForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final RegisterController controller = context.read<RegisterController>();
    final SignUpResult? result = await controller.register(
      fullName: _nameController.text,
      email: _emailController.text,
      phone: _phoneController.text,
      password: _passwordController.text,
    );

    if (!mounted) return;

    if (result == null) {
      final String? message = controller.errorMessage;
      if (message != null) {
        UiFeedback.showError(context, message);
        controller.clearError();
      }
      return;
    }

    if (result.needsEmailVerification) {
      // Supabase created the account but withheld a session until the address
      // is confirmed, so send the user to the login tab with an explanation.
      UiFeedback.showSuccess(context, AppStrings.verifyEmailSent);
      widget.onSwitchTab(AuthTab.login);
      return;
    }
    // Otherwise confirmation is disabled on the project: the session is live
    // and the auth gate swaps in the home screen on its own.
  }

  @override
  Widget build(BuildContext context) {
    final RegisterController controller = context.watch<RegisterController>();

    return Form(
      key: _formKey,
      // Each row carries its own trailing gap so the cascade steps once per
      // field rather than once per spacer.
      child: StaggeredEntrance(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: AppSizes.lg),
            child: AppTextField(
              label: AppStrings.fullName,
              hint: AppStrings.fullNameHint,
              controller: _nameController,
              icon: Icons.person_outline_rounded,
              keyboardType: TextInputType.name,
              textCapitalization: TextCapitalization.words,
              validator: Validators.fullName,
              enabled: !controller.isSubmitting,
              autofillHints: const <String>[AutofillHints.name],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSizes.lg),
            child: AppTextField(
              label: AppStrings.email,
              hint: AppStrings.emailHint,
              controller: _emailController,
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              validator: Validators.email,
              enabled: !controller.isSubmitting,
              autofillHints: const <String>[AutofillHints.email],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSizes.lg),
            child: AppTextField(
              label: AppStrings.phone,
              hint: AppStrings.phoneHint,
              controller: _phoneController,
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              validator: Validators.phone,
              enabled: !controller.isSubmitting,
              autofillHints: const <String>[AutofillHints.telephoneNumber],
              inputFormatters: <TextInputFormatter>[
                // Digits only, capped at the exact length of a Philippine
                // mobile number. The keyboard cannot produce a '+' or a space
                // here, so the validator's other branches only ever fire on a
                // paste - which is exactly when a person needs telling why.
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSizes.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                AppTextField(
                  label: AppStrings.password,
                  hint: AppStrings.createPasswordHint,
                  controller: _passwordController,
                  icon: Icons.lock_outline_rounded,
                  obscure: true,
                  validator: Validators.password,
                  enabled: !controller.isSubmitting,
                  autofillHints: const <String>[AutofillHints.newPassword],
                ),
                const SizedBox(height: AppSizes.sm),
                // Rebuilt on each keystroke, so the rules tick off as they are
                // met rather than being reported after a failed submit.
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _passwordController,
                  builder:
                      (BuildContext context, TextEditingValue value, Widget? _) =>
                          PasswordRequirements(password: value.text),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSizes.xl),
            child: AppTextField(
              label: AppStrings.confirmPassword,
              hint: AppStrings.confirmPasswordHint,
              controller: _confirmController,
              icon: Icons.lock_outline_rounded,
              obscure: true,
              textInputAction: TextInputAction.done,
              enabled: !controller.isSubmitting,
              validator: (String? value) =>
                  Validators.confirmPassword(value, _passwordController.text),
              onSubmitted: (_) => _submit(),
            ),
          ),
          PrimaryButton(
            label: AppStrings.registerCta,
            isLoading: controller.isSubmitting,
            onPressed: controller.isSubmitting ? null : _submit,
          ),
        ],
      ),
    );
  }
}
