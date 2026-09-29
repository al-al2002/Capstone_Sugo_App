import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/utils/ui_feedback.dart';
import '../../../rb_cars/services/rb_cars_service.dart';
import '../../../technician/services/onboarding_service.dart';
import '../controllers/auth_controller.dart';

/// The exit from a half-finished registration.
///
/// Replaces a plain "Sign out" on every pre-dashboard screen. Signing out of an
/// unfinished signup is exactly what used to strand an account: the
/// `auth.users` row survives, holds the email address, and can log back in to
/// the same dead end forever.
///
/// This offers both paths and names the consequence of each:
///
/// * **Finish later** - keeps the account and signs out. Nothing is lost, and
///   they resume at the same step next time, because the router derives that
///   step from database state rather than navigation history.
/// * **Cancel registration** - deletes the account outright, freeing the email.
///
/// Lives in the auth feature rather than in `core/widgets` because it depends
/// on `OnboardingService`, and a core widget reaching into a feature would
/// invert the dependency. All three pre-dashboard screens import it from here.
class RegistrationExitAction extends StatefulWidget {
  const RegistrationExitAction({super.key, this.enabled = true});

  /// False while an upload is in flight, so the account cannot be deleted from
  /// underneath a running request.
  final bool enabled;

  @override
  State<RegistrationExitAction> createState() => _RegistrationExitActionState();
}

class _RegistrationExitActionState extends State<RegistrationExitAction> {
  final OnboardingService _service = OnboardingService();
  bool _isBusy = false;

  Future<void> _openMenu() async {
    final _ExitChoice? choice = await showModalBottomSheet<_ExitChoice>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: AppSizes.md),
            const Text(
              'Leave registration?',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSizes.sm),
            ListTile(
              leading: const Icon(
                Icons.bookmark_outline_rounded,
                color: AppColors.primary,
              ),
              title: const Text('Finish later'),
              subtitle: const Text(
                'Keep your account and sign out. You will resume at this step.',
              ),
              onTap: () => Navigator.of(sheetContext).pop(_ExitChoice.signOut),
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.error,
              ),
              title: const Text(
                'Cancel registration',
                style: TextStyle(color: AppColors.error),
              ),
              subtitle: const Text(
                'Delete this account. Your email becomes free to use again.',
              ),
              onTap: () => Navigator.of(sheetContext).pop(_ExitChoice.delete),
            ),
            const SizedBox(height: AppSizes.md),
          ],
        ),
      ),
    );

    if (choice == null || !mounted) return;

    if (choice == _ExitChoice.signOut) {
      await context.read<AuthController>().signOut();
      return;
    }

    await _confirmDelete();
  }

  Future<void> _confirmDelete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Delete this account?'),
        content: const Text(
          'Your profile, any ID you uploaded and any assessment attempts are '
          'removed permanently. This cannot be undone.\n\n'
          'You can sign up again with the same email afterwards.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep account'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isBusy = true);

    try {
      // The service signs out once the account is gone, so the gate returns to
      // the auth screen without this widget navigating anywhere itself.
      await _service.cancelRegistration();
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      UiFeedback.showError(context, failure.message);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isBusy) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSizes.lg),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
        ),
      );
    }

    return IconButton(
      onPressed: widget.enabled ? _openMenu : null,
      icon: const Icon(Icons.more_vert_rounded, size: 20),
      tooltip: 'Leave registration',
    );
  }
}

enum _ExitChoice { signOut, delete }
