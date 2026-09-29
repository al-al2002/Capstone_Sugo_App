import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sugo_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sugo_app/features/onboarding/models/registration_status.dart';
import 'package:sugo_app/features/onboarding/widgets/onboarding_scaffold.dart';

import '../../support/fake_auth_repository.dart';

/// Guards the way out of the waiting screen.
///
/// The bug this exists for: `PendingReviewScreen` only rendered a sign-out
/// button when an `onSignOut` callback was supplied, and all three call sites
/// constructed it without one. A user who submitted their ID landed on a
/// screen with no button at all - no way back to the login page, and nothing
/// to do but force-quit the app.
void main() {
  Widget wrap(Widget child, FakeAuthRepository repository) {
    return ChangeNotifierProvider<AuthController>(
      create: (_) => AuthController(repository),
      child: MaterialApp(home: child),
    );
  }

  testWidgets('offers a way back to login with no callback supplied', (
    WidgetTester tester,
  ) async {
    final FakeAuthRepository repository = FakeAuthRepository();

    await tester.pumpWidget(
      wrap(
        const PendingReviewScreen(status: RegistrationStatus.pendingReview),
        repository,
      ),
    );

    expect(find.text('Back to login'), findsOneWidget);
  });

  testWidgets('the button signs the user out', (WidgetTester tester) async {
    final FakeAuthRepository repository = FakeAuthRepository();

    await tester.pumpWidget(
      wrap(
        const PendingReviewScreen(status: RegistrationStatus.pendingReview),
        repository,
      ),
    );

    await tester.tap(find.text('Back to login'));
    await tester.pump();

    expect(repository.calls, contains('signOut'));
  });

  testWidgets('says the application is not withdrawn by signing out', (
    WidgetTester tester,
  ) async {
    // Without this line "Back to login" reads as "cancel", and someone waiting
    // on review will sit on the screen rather than risk losing their place.
    final FakeAuthRepository repository = FakeAuthRepository();

    await tester.pumpWidget(
      wrap(
        const PendingReviewScreen(status: RegistrationStatus.pendingReview),
        repository,
      ),
    );

    expect(find.textContaining('stays in the queue'), findsOneWidget);
  });

  testWidgets('a rejected account gets both retake and a way out', (
    WidgetTester tester,
  ) async {
    final FakeAuthRepository repository = FakeAuthRepository();
    bool retaken = false;

    await tester.pumpWidget(
      wrap(
        PendingReviewScreen(
          status: RegistrationStatus.rejected,
          rejectionReason: 'The ID in your selfie is not readable.',
          onRetake: () => retaken = true,
        ),
        repository,
      ),
    );

    expect(find.text('Retake my photos'), findsOneWidget);
    expect(find.text('Back to login'), findsOneWidget);
    expect(find.text('The ID in your selfie is not readable.'), findsOneWidget);

    await tester.tap(find.text('Retake my photos'));
    await tester.pump();
    expect(retaken, isTrue);
  });
}
