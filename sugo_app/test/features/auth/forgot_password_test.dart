import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/auth/data/repositories/auth_repository.dart';
import 'package:sugo_app/features/auth/presentation/screens/forgot_password_screen.dart';

import '../../support/fake_auth_repository.dart';

/// Forgot password, end to end against the fake: email -> six-digit code ->
/// new password -> done.
void main() {
  Future<FakeAuthRepository> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final FakeAuthRepository repository = FakeAuthRepository();
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      Provider<AuthRepository>.value(
        value: repository,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const ForgotPasswordScreen(),
        ),
      ),
    );
    return repository;
  }

  Future<void> sendTo(WidgetTester tester, String email) async {
    await tester.enterText(find.byType(TextFormField), email);
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
  }

  /// Types a code into the boxes the way a paste arrives: all six at once in
  /// the first box, which the field spreads across the rest.
  Future<void> typeCode(WidgetTester tester, String code) async {
    await tester.enterText(find.byType(TextField).first, code);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
  }

  testWidgets('the whole flow: email, code, new password, done', (
    WidgetTester tester,
  ) async {
    final FakeAuthRepository repository = await open(tester);
    expect(find.text('Forgot your password?'), findsOneWidget);

    await sendTo(tester, 'juan@sugo.app');
    expect(repository.calls.last, 'sendPasswordResetCode:juan@sugo.app');
    expect(find.text('Check your email'), findsOneWidget);
    expect(find.textContaining('juan@sugo.app'), findsOneWidget);
    // The resend waits out the server's one-minute limit.
    expect(find.textContaining('Resend in'), findsOneWidget);

    await typeCode(tester, FakeAuthRepository.validResetCode);
    expect(
      repository.calls,
      contains('verifyPasswordResetCode:juan@sugo.app:123456'),
    );
    expect(find.text('Set a new password'), findsOneWidget);

    final Finder fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'newPass123');
    await tester.enterText(fields.at(1), 'newPass123');
    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();

    expect(repository.calls.last, 'updatePassword');
    expect(find.text('Password updated'), findsOneWidget);
  });

  testWidgets('a wrong code is refused and the flow stays on the code step', (
    WidgetTester tester,
  ) async {
    final FakeAuthRepository repository = await open(tester);
    await sendTo(tester, 'juan@sugo.app');

    await typeCode(tester, '000000');

    expect(
      repository.calls,
      contains('verifyPasswordResetCode:juan@sugo.app:000000'),
    );
    expect(find.text('Check your email'), findsOneWidget);
    expect(find.text('Set a new password'), findsNothing);
    expect(repository.calls, isNot(contains('updatePassword')));

    // Let the refusal play out - the boxes shake, then clear themselves on a
    // timer, and the error snackbar has its own - before the tree is torn down.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('an invalid email never reaches the server', (
    WidgetTester tester,
  ) async {
    final FakeAuthRepository repository = await open(tester);
    await sendTo(tester, 'not-an-email');

    expect(repository.calls, isEmpty);
    expect(find.text('Forgot your password?'), findsOneWidget);
  });

  testWidgets('change email goes back to the first step', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await sendTo(tester, 'juan@sugo.app');

    await tester.tap(find.text('Change email'));
    await tester.pumpAndSettle();
    expect(find.text('Forgot your password?'), findsOneWidget);
  });
}
