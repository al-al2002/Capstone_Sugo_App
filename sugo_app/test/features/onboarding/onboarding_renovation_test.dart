import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/session/session_state.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/auth/presentation/screens/role_selection_screen.dart';
import 'package:sugo_app/features/onboarding/controllers/registration_flow_controller.dart';
import 'package:sugo_app/features/onboarding/models/registration_status.dart';
import 'package:sugo_app/features/onboarding/services/identity_verification_service.dart';
import 'package:sugo_app/features/onboarding/widgets/onboarding_scaffold.dart';
import 'package:sugo_app/features/onboarding/widgets/onboarding_step_intro.dart';

/// The renovated registration shell (2026-11-17): the progress band with its
/// completion ring, the step that slides in, and the role choice - on a small
/// phone at large text, settling at full motion.
void main() {
  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery(
      data: const MediaQueryData(
        size: Size(320, 800),
        textScaler: TextScaler.linear(1.3),
      ),
      child: child,
    ),
  );

  void phone(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    addTearDown(tester.view.reset);
  }

  testWidgets('the band names the step, and Continue moves the flow on', (
    WidgetTester tester,
  ) async {
    phone(tester);
    final _TestFlow flow = _TestFlow();
    addTearDown(flow.dispose);

    await tester.pumpWidget(
      host(
        ListenableBuilder(
          listenable: flow,
          builder: (BuildContext context, Widget? _) => OnboardingScaffold(
            controller: flow,
            onContinue: flow.next,
            child: Text('Body: ${flow.currentStep.label}'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Step 1 of 5'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('Body: Account'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // The new step slid in and the old one is gone; the ring moved on.
    expect(find.text('Step 2 of 5'), findsOneWidget);
    expect(find.text('ID check'), findsOneWidget);
    expect(find.text('Body: ID check'), findsOneWidget);
    expect(find.text('Body: Account'), findsNothing);
    expect(find.text('20%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Every step opens with it, so it must fit the smallest case.
  testWidgets('the step intro fits a small phone at large text', (
    WidgetTester tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      host(
        const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: OnboardingStepIntro(
              icon: Icons.workspace_premium_rounded,
              title: 'Clearance and credentials',
              subtitle:
                  'An NBI or police clearance is required - clients are '
                  'letting you into their home.',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Clearance and credentials'), findsOneWidget);
    expect(find.byIcon(Icons.workspace_premium_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the role choice keeps its words and reports the choice', (
    WidgetTester tester,
  ) async {
    phone(tester);
    UserRole? chosen;
    await tester.pumpWidget(
      host(
        Scaffold(
          body: RoleSelectionScreen(onChosen: (UserRole r) => chosen = r),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('How will you use SUGO?'), findsOneWidget);
    expect(find.text('Continue as a client'), findsOneWidget);
    // Below the fold on a small phone at large text: scroll to it, the way
    // a person would. A ListView builds only what is near the screen.
    await tester.scrollUntilVisible(find.text('Continue as a technician'), 200);
    expect(find.text('Continue as a technician'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Continue as a client'), -200);

    await tester.tap(find.text('Continue as a client'));
    await tester.pumpAndSettle();
    expect(chosen, UserRole.client);
  });
}

/// The smallest real flow: the client's five steps, every step before the
/// current one counted as done, and nothing written anywhere.
class _TestFlow extends RegistrationFlowController {
  _TestFlow() : super(identityService: _FakeIdentity());

  @override
  UserRole get role => UserRole.client;

  @override
  Set<OnboardingStepId> get completedSteps => steps.take(stepIndex).toSet();

  @override
  bool get canContinue => true;

  @override
  Future<bool> persistCurrentStep() async => true;

  @override
  Future<void> performSubmit() async {}
}

class _FakeIdentity implements IdentityVerificationService {
  @override
  Future<void> saveStep(OnboardingStepId step) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
