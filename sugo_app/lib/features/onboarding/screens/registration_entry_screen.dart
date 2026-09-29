import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/session/session_state.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/widgets/sugo_app_bar.dart';
import '../../auth/presentation/screens/role_selection_screen.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../../technician/services/onboarding_service.dart';
import 'client_registration_screen.dart';
import 'technician_registration_screen.dart';

/// Asks which kind of account this is, then hands off to that role's flow.
///
/// ## Why role selection is a separate screen from the steppers
///
/// Sign-up does not capture a role - the register form collects an email, a
/// password and a name, and `profiles.role` defaults to `client`. Both
/// registration flows, however, need to know the role before their first step:
/// it decides the step list, and it is written onto every
/// `identity_verifications` row.
///
/// So the choice has to be settled first. It cannot be inferred, because the
/// default is indistinguishable from a deliberate choice of Client - which is
/// exactly why `profiles.role_chosen_at` exists (migration 20260906000001).
class RegistrationEntryScreen extends StatefulWidget {
  const RegistrationEntryScreen({super.key});

  @override
  State<RegistrationEntryScreen> createState() =>
      _RegistrationEntryScreenState();
}

class _RegistrationEntryScreenState extends State<RegistrationEntryScreen> {
  final OnboardingService _service = OnboardingService();

  UserRole? _chosen;
  bool _isSaving = false;

  Future<void> _choose(UserRole role) async {
    setState(() => _isSaving = true);

    try {
      // Writes `role` and `role_chosen_at`, and creates the `technicians` row
      // when relevant. Reused rather than reimplemented: it already handles
      // both, and a second copy would be one more thing to keep in step.
      await _service.chooseRole(role);

      if (!mounted) return;
      setState(() => _chosen = role);

      // Recompute the landing destination, so a later relaunch resumes into
      // the right flow rather than asking again.
      await context.read<SessionController>().refresh();
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      UiFeedback.showError(context, failure.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The session may already carry a chosen role - a resumed registration, or
    // a rejection being retaken - in which case the question is settled and
    // this screen just forwards.
    final SessionProfile? profile = context.watch<SessionController>().profile;
    final UserRole? role =
        _chosen ?? (profile?.hasChosenRole ?? false ? profile!.role : null);

    if (role == UserRole.technician) {
      return const TechnicianRegistrationScreen();
    }
    if (role == UserRole.client) {
      return const ClientRegistrationScreen();
    }

    if (_isSaving) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // `RoleSelectionScreen` is presentational and supplies no Scaffold - the
    // legacy `RegistrationFlowScreen` wrapped it. This flow provides its own.
    return Scaffold(
      backgroundColor: AppColors.background,
      // Not "Get started": that is the splash button, which leads to sign-in.
      // One action, one name - this screen is the start of the account.
      appBar: const SugoAppBar(title: 'Create your account'),
      body: SafeArea(child: RoleSelectionScreen(onChosen: _choose)),
    );
  }
}
