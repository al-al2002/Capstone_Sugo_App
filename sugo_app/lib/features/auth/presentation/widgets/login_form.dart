import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/utils/ui_feedback.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/staggered_entrance.dart';
import '../controllers/login_controller.dart';
import 'auth_tab.dart';

/// Email and password sign-in.
///
/// The Google and Facebook buttons were removed from this form; the OAuth
/// methods are still on [LoginController] if they are ever brought back.
class LoginForm extends StatefulWidget {
  const LoginForm({super.key, required this.onSwitchTab});

  final ValueChanged<AuthTab> onSwitchTab;

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Dismiss the keyboard so any result message is not hidden behind it.
    FocusScope.of(context).unfocus();

    // Empty or malformed fields surface their own message under the field.
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final LoginController controller = context.read<LoginController>();
    final bool success = await controller.login(
      email: _emailController.text,
      password: _passwordController.text,
    );

    // On success the auth gate swaps in the home screen, so there is nothing
    // to navigate here.
    if (!mounted || success) return;
    _showError(controller);
  }

  void _showError(LoginController controller) {
    final String? message = controller.errorMessage;
    if (message == null) return;
    UiFeedback.showError(context, message);
    controller.clearError();
  }

  @override
  Widget build(BuildContext context) {
    final LoginController controller = context.watch<LoginController>();

    return Form(
      key: _formKey,
      // Each row carries its own trailing gap so the cascade steps once per
      // visible element rather than once per spacer.
      child: StaggeredEntrance(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: AppSizes.lg),
            child: AppTextField(
              label: AppStrings.email,
              hint: AppStrings.emailHint,
              controller: _emailController,
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              validator: Validators.email,
              enabled: !controller.isBusy,
              autofillHints: const <String>[AutofillHints.email],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSizes.md),
            child: AppTextField(
              label: AppStrings.password,
              hint: AppStrings.passwordHint,
              controller: _passwordController,
              icon: Icons.lock_outline_rounded,
              obscure: true,
              textInputAction: TextInputAction.done,
              validator: Validators.loginPassword,
              enabled: !controller.isBusy,
              autofillHints: const <String>[AutofillHints.password],
              onSubmitted: (_) => _submit(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSizes.xl),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: controller.isBusy
                    ? null
                    : () => Navigator.of(
                        context,
                      ).pushNamed(AppRoutes.forgotPassword),
                child: const Text(AppStrings.forgotPassword),
              ),
            ),
          ),
          PrimaryButton(
            label: AppStrings.loginCta,
            isLoading: controller.isSubmitting,
            onPressed: controller.isBusy ? null : _submit,
          ),
        ],
      ),
    );
  }
}
