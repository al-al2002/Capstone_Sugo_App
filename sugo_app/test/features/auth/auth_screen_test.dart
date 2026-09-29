import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sugo_app/core/errors/auth_failure.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/auth/data/repositories/auth_repository.dart';
import 'package:sugo_app/features/auth/presentation/screens/auth_screen.dart';
import 'package:sugo_app/features/auth/presentation/widgets/auth_header.dart';
import 'package:sugo_app/features/auth/presentation/widgets/auth_tab.dart';

import '../../support/fake_auth_repository.dart';

void main() {
  Widget wrap(AuthRepository repository, {AuthTab tab = AuthTab.login}) {
    return Provider<AuthRepository>.value(
      value: repository,
      child: MaterialApp(
        theme: AppTheme.light,
        home: AuthScreen(initialTab: tab),
      ),
    );
  }

  /// The default 800x600 surface is shorter than a phone, which would leave
  /// the submit button below the fold and make taps miss it.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  FakeAuthRepository newRepository(
    WidgetTester tester, {
    AuthFailure? failure,
    bool needsEmailVerification = false,
  }) {
    useTallSurface(tester);
    final FakeAuthRepository repository = FakeAuthRepository(
      failure: failure,
      needsEmailVerification: needsEmailVerification,
    );
    addTearDown(repository.dispose);
    return repository;
  }

  Future<void> tapButton(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  /// The full-width submit button.
  Future<void> tapSubmit(WidgetTester tester) async {
    await tester.ensureVisible(find.byType(ElevatedButton));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
  }

  /// The footer link that moves to the other form - the only way across,
  /// since the reference design has no tab switcher.
  Future<void> tapFooter(WidgetTester tester, String label) async {
    final Finder link = find.widgetWithText(TextButton, label);
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pumpAndSettle();
  }

  group('layout (2026-09-28 reference)', () {
    testWidgets('brand header on top, one form, no tabs, no social', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository repository = newRepository(tester);
      await tester.pumpWidget(wrap(repository));

      expect(find.byType(AuthHeader), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
      // Email and password only.
      expect(find.textContaining('Google'), findsNothing);
      expect(find.textContaining('Facebook'), findsNothing);
      expect(find.textContaining('continue with'), findsNothing);
    });

    testWidgets('the register link switches the form and the title', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository repository = newRepository(tester);
      await tester.pumpWidget(wrap(repository));

      expect(find.textContaining("Don't have an account?"), findsOneWidget);
      await tapFooter(tester, 'Register');

      expect(find.text('Create your account'), findsOneWidget);
      expect(find.text('Create account'), findsOneWidget);
      expect(find.textContaining('Already have an account?'), findsOneWidget);
    });

    testWidgets('fits a small phone at large text without overflow', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final FakeAuthRepository repository = FakeAuthRepository();
      addTearDown(repository.dispose);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(1.3),
          ),
          child: wrap(repository),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('login', () {
    testWidgets('has its fields, forgot link and CTA', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository repository = newRepository(tester);
      await tester.pumpWidget(wrap(repository));

      expect(find.text('Email address'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Forgot password?'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(2));
    });

    testWidgets('shows an error under each empty field on submit', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository repository = newRepository(tester);
      await tester.pumpWidget(wrap(repository));
      await tapSubmit(tester);

      expect(find.text('Email address is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
      expect(repository.calls, isEmpty);
    });

    testWidgets('sends valid credentials to Supabase', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository repository = newRepository(tester);
      await tester.pumpWidget(wrap(repository));
      await tester.enterText(find.byType(TextFormField).at(0), 'juan@sugo.app');
      await tester.enterText(find.byType(TextFormField).at(1), 'sugo1234');
      await tapSubmit(tester);

      expect(repository.calls, <String>['signInWithEmail:juan@sugo.app']);
    });

    testWidgets('surfaces a rejected sign-in', (WidgetTester tester) async {
      final FakeAuthRepository repository = newRepository(
        tester,
        failure: const AuthFailure(
          'Incorrect email or password.',
          code: 'invalid_credentials',
        ),
      );
      await tester.pumpWidget(wrap(repository));
      await tester.enterText(find.byType(TextFormField).at(0), 'juan@sugo.app');
      await tester.enterText(find.byType(TextFormField).at(1), 'wrong-pass');
      await tapSubmit(tester);

      expect(find.text('Incorrect email or password.'), findsOneWidget);
    });
  });

  group('register', () {
    Future<void> fill(
      WidgetTester tester, {
      String phone = '09171234567',
      String password = 'sugo1234',
      String? confirm,
    }) async {
      final Finder fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Juan Dela Cruz');
      await tester.enterText(fields.at(1), 'juan@sugo.app');
      await tester.enterText(fields.at(2), phone);
      await tester.enterText(fields.at(3), password);
      await tester.enterText(fields.at(4), confirm ?? password);
    }

    testWidgets('has all five fields', (WidgetTester tester) async {
      final FakeAuthRepository repository = newRepository(tester);
      await tester.pumpWidget(wrap(repository, tab: AuthTab.register));

      expect(find.text('Full name'), findsOneWidget);
      expect(find.text('Email address'), findsOneWidget);
      expect(find.text('Phone number'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Confirm password'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(5));
      expect(find.text('Create account'), findsOneWidget);
    });

    testWidgets('shows an error under each empty field on submit', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository repository = newRepository(tester);
      await tester.pumpWidget(wrap(repository, tab: AuthTab.register));
      await tapButton(tester, 'Create account');

      expect(find.text('Full name is required'), findsOneWidget);
      expect(find.text('Email address is required'), findsOneWidget);
      expect(find.text('Mobile number is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
      expect(find.text('Please confirm your password'), findsOneWidget);
      expect(repository.calls, isEmpty);
    });

    // The repository receives the number as typed; `Validators.normalizePhone`
    // converts to E.164 inside the real Supabase implementation, which this
    // fake stands in for.
    testWidgets('forwards the local form to the repository', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository repository = newRepository(
        tester,
        needsEmailVerification: true,
      );
      await tester.pumpWidget(wrap(repository, tab: AuthTab.register));
      await fill(tester, phone: '09171234567');
      await tapButton(tester, 'Create account');

      expect(repository.calls, <String>[
        'signUpWithEmail:juan@sugo.app:Juan Dela Cruz:09171234567',
      ]);
    });

    testWidgets('rejects a short or wrongly prefixed number', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository repository = newRepository(tester);
      await tester.pumpWidget(wrap(repository, tab: AuthTab.register));

      await fill(tester, phone: '0917123456');
      await tapButton(tester, 'Create account');
      expect(
        find.text('That is 10 digits. A mobile number has 11'),
        findsOneWidget,
      );

      await fill(tester, phone: '08171234567');
      await tapButton(tester, 'Create account');
      expect(
        find.text('A Philippine mobile number starts with 09'),
        findsOneWidget,
      );

      expect(repository.calls, isEmpty);
    });

    testWidgets('rejects a mismatched confirmation', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository repository = newRepository(tester);
      await tester.pumpWidget(wrap(repository, tab: AuthTab.register));
      await fill(tester, password: 'sugo1234', confirm: 'sugo4321');
      await tapButton(tester, 'Create account');

      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(repository.calls, isEmpty);
    });

    testWidgets('returns to login when verification is needed', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository repository = newRepository(
        tester,
        needsEmailVerification: true,
      );
      await tester.pumpWidget(wrap(repository, tab: AuthTab.register));
      await fill(tester);
      await tapButton(tester, 'Create account');

      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Forgot password?'), findsOneWidget);
    });
  });

  group('switch animation', () {
    const Key loginForm = ValueKey<String>('login-form');
    const Key registerForm = ValueKey<String>('register-form');

    testWidgets('both forms are on screen mid-transition, then only one', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository repository = newRepository(tester);
      await tester.pumpWidget(wrap(repository));
      expect(find.byKey(loginForm), findsOneWidget);

      final Finder link = find.widgetWithText(TextButton, 'Register');
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pump();
      // Part way through the 280ms transition.
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.byKey(loginForm), findsOneWidget);
      expect(find.byKey(registerForm), findsOneWidget);
      expect(find.byType(SlideTransition), findsWidgets);
      // The header does not change with the form.
      expect(find.byType(AuthHeader), findsOneWidget);

      await tester.pumpAndSettle();

      expect(find.byKey(loginForm), findsNothing);
      expect(find.byKey(registerForm), findsOneWidget);
    });

    testWidgets('the log-in link settles back on the login form', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository repository = newRepository(tester);
      await tester.pumpWidget(wrap(repository, tab: AuthTab.register));

      await tapFooter(tester, 'Log in');

      expect(find.byKey(registerForm), findsNothing);
      expect(find.byKey(loginForm), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
    });
  });
}
