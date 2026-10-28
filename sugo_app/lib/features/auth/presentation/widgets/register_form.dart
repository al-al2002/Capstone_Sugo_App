import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/session/session_state.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/ui_feedback.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/staggered_entrance.dart';
import '../../data/repositories/auth_repository.dart';
import '../controllers/register_controller.dart';
import 'auth_tab.dart';
import 'password_requirements.dart';
import 'terms_agreement.dart';

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
  UserRole _role = UserRole.client;

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
    final RegisterController controller = context.read<RegisterController>();

    if (!controller.acceptedTerms) {
      UiFeedback.showError(
        context,
        'Please accept the Terms of Service and Privacy Policy to continue.',
      );
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) return;

    final SignUpResult? result = await controller.register(
      fullName: _nameController.text,
      email: _emailController.text,
      phone: _phoneController.text,
      password: _passwordController.text,
      role: _role.wire,
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
          _RoleChoice(
            role: _role,
            enabled: !controller.isSubmitting,
            onChanged: (UserRole role) => setState(() => _role = role),
          ),
          const SizedBox(height: AppSizes.lg),
          TermsAgreement(
            value: controller.acceptedTerms,
            onChanged: controller.setAcceptedTerms,
          ),
          const SizedBox(height: AppSizes.lg),
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

class _RoleChoice extends StatelessWidget {
  const _RoleChoice({
    required this.role,
    required this.enabled,
    required this.onChanged,
  });

  final UserRole role;
  final bool enabled;
  final ValueChanged<UserRole> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('I want to register as', style: AppTextStyles.label),
        const SizedBox(height: AppSizes.sm),
        Row(
          children: <Widget>[
            Expanded(
              child: _RoleTile(
                title: 'Client',
                description: 'Book services and get help',
                icon: Icons.person_rounded,
                selected: role == UserRole.client,
                enabled: enabled,
                onTap: () => onChanged(UserRole.client),
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: _RoleTile(
                title: 'Service Provider',
                description: 'Offer your skills and earn',
                icon: Icons.engineering_rounded,
                selected: role == UserRole.technician,
                enabled: enabled,
                onTap: () => onChanged(UserRole.technician),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RoleTile extends StatelessWidget {
  const _RoleTile({
    required this.title,
    required this.description,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color border = selected
        ? AppColors.secondary
        : AppColors.border;
    final Color foreground = selected
        ? AppColors.secondaryDark
        : AppColors.textSecondary;

    return Semantics(
      button: true,
      selected: selected,
      label: title,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 82),
          padding: const EdgeInsets.all(AppSizes.sm),
          decoration: BoxDecoration(
            color: selected ? AppColors.secondarySoft : AppColors.fieldFill,
            border: Border.all(
              color: border,
              width: selected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(AppSizes.radius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 22, color: foreground),
              const SizedBox(height: AppSizes.xs),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.label.copyWith(color: foreground),
              ),
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.micro,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
