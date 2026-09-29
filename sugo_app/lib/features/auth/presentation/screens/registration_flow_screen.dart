import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/session/session_controller.dart';
import '../../../../core/session/session_state.dart';
import '../../../../core/utils/ui_feedback.dart';
import '../../../../core/widgets/sugo_app_bar.dart';
import '../../../client/screens/client_id_verification_screen.dart';
import '../../../technician/screens/assessment_result_screen.dart';
import '../../../technician/screens/quiz_screen.dart';
import '../../../technician/screens/specialization_select_screen.dart';
import '../controllers/registration_controller.dart';
import '../widgets/registration_exit_action.dart';
import 'role_selection_screen.dart';

/// Hosts the whole registration flow, start to finish, in memory.
///
/// ## Why one host instead of the router deciding each step
///
/// The step used to be derived from the database - a technician with an ID but
/// no verification was "on the quiz". With nothing written until the end, there
/// is no database state to read, so the step lives in
/// [RegistrationController] and this screen renders it.
///
/// `AuthGate` still owns the single routing decision: it sends anyone with no
/// `profiles` row here, and everyone else to a dashboard. This screen owns only
/// what happens inside registration.
class RegistrationFlowScreen extends StatelessWidget {
  const RegistrationFlowScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RegistrationController>(
      create: (_) => RegistrationController(),
      child: const _RegistrationFlowView(),
    );
  }
}

class _RegistrationFlowView extends StatelessWidget {
  const _RegistrationFlowView();

  Future<void> _submit(BuildContext context) async {
    final RegistrationController registration = context
        .read<RegistrationController>();
    final SessionController session = context.read<SessionController>();

    final SessionProfile? existing = session.profile;

    final bool done = await registration.submit(
      // Carried from sign-up metadata: the profile row does not exist yet, so
      // there is nowhere else for the name to come from.
      fullName: existing?.fullName ?? session.authFullName,
      phone: existing?.phone ?? session.authPhone,
    );

    if (!context.mounted) return;

    if (done) {
      // The account now exists, so refreshing the session makes the gate
      // re-evaluate and open the right dashboard.
      await session.refresh();
      return;
    }

    final String? error = registration.error;
    if (error != null) {
      UiFeedback.showError(context, error);
      registration.clearError();
    }
  }

  @override
  Widget build(BuildContext context) {
    final RegistrationController registration = context
        .watch<RegistrationController>();

    final Widget body = switch (registration.step) {
      RegistrationStep.role => RoleSelectionScreen(
        onChosen: registration.chooseRole,
      ),
      RegistrationStep.identity => ClientIdVerificationScreen(
        file: registration.idFile,
        validationError: registration.idValidationError,
        isSubmitting: registration.isSubmitting,
        isTechnician: registration.isTechnician,
        // pickIdFile is async; the callback signature is void, so the
        // future is intentionally not awaited here - the controller
        // notifies listeners when validation lands.
        onPicked: (XFile picked) => registration.pickIdFile(picked),
        onContinue: registration.isTechnician
            ? registration.continueFromIdentity
            : () => _submit(context),
      ),
      RegistrationStep.specialization => SpecializationSelectScreen(
        selected: registration.specialization,
        onChosen: registration.chooseSpecialization,
      ),
      RegistrationStep.quiz => QuizScreen(
        specialization: registration.specialization!,
        answers: registration.answers,
        isSubmitting: registration.isSubmitting,
        onAnswer: registration.setAnswer,
        onSubmit: () => _submit(context),
      ),
      RegistrationStep.failedResult => AssessmentResultScreen(
        result: registration.failedResult!,
        onContinue: () {},
        onRetry: registration.retryQuiz,
      ),
    };

    return PopScope(
      // Back should walk the flow, not drop out of it and strand the draft.
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (didPop) return;
        if (registration.canGoBack) registration.back();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: SugoAppBar(
          onBack: registration.canGoBack ? registration.back : null,
          title:
              'Step ${registration.stepIndex + 1} of ${registration.totalSteps}',
          actions: <Widget>[
            RegistrationExitAction(enabled: !registration.isSubmitting),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSizes.screenPadding,
                0,
                AppSizes.screenPadding,
                AppSizes.sm,
              ),
              child: _StepRail(
                current: registration.stepIndex,
                total: registration.totalSteps,
              ),
            ),
          ),
        ),
        body: SafeArea(child: body),
      ),
    );
  }
}

class _StepRail extends StatelessWidget {
  const _StepRail({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List<Widget>.generate(total, (int index) {
        final bool done = index <= current;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == total - 1 ? 0 : 6),
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: done ? AppColors.primary : AppColors.divider,
                borderRadius: BorderRadius.circular(AppSizes.pillRadius),
              ),
            ),
          ),
        );
      }),
    );
  }
}
