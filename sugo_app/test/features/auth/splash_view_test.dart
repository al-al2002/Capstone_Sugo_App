import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/auth/presentation/screens/splash_view.dart';
import 'package:sugo_app/features/auth/presentation/widgets/splash_loader.dart';

/// The 2026-09-29 splash: the poster, a loading animation, then "Get started"
/// for someone signed out - and straight through for someone signed in.
void main() {
  setUp(SplashView.debugReset);

  Widget host({
    required bool ready,
    required bool signedIn,
    VoidCallback? onFinished,
    bool reduceMotion = false,
  }) {
    return MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          disableAnimations: reduceMotion,
        ),
        child: SplashView(
          ready: ready,
          signedIn: signedIn,
          onFinished: onFinished,
        ),
      ),
    );
  }

  /// Steps past the minimum in slices, so the switcher's transition runs.
  Future<void> pastTheFloor(WidgetTester tester) async {
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('signed out: the loader, then "Get started", which hands over', (
    WidgetTester tester,
  ) async {
    int finished = 0;
    await tester.pumpWidget(
      host(ready: true, signedIn: false, onFinished: () => finished++),
    );

    expect(find.byType(SplashLoader), findsOneWidget);
    expect(find.text('Get started'), findsNothing);

    await pastTheFloor(tester);
    expect(find.byType(SplashLoader), findsNothing);
    expect(find.text('Get started'), findsOneWidget);
    expect(finished, 0, reason: 'a signed-out user decides when to go on');

    await tester.tap(find.text('Get started'));
    await tester.pump();
    expect(finished, 1);
    expect(SplashView.hasPlayed, isTrue);
  });

  testWidgets('the loader stays while the session is still restoring', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(ready: false, signedIn: false, onFinished: () {}),
    );
    await pastTheFloor(tester);

    expect(find.byType(SplashLoader), findsOneWidget);
    expect(find.text('Get started'), findsNothing);
  });

  testWidgets('signed in: straight through, no button to press', (
    WidgetTester tester,
  ) async {
    int finished = 0;
    await tester.pumpWidget(
      host(ready: true, signedIn: true, onFinished: () => finished++),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(finished, 0, reason: 'the loading animation is seen first');

    await pastTheFloor(tester);
    expect(finished, 1);
    expect(find.text('Get started'), findsNothing);
  });

  testWidgets('with nobody waiting, it only ever shows the loader', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(ready: true, signedIn: false));
    await pastTheFloor(tester);

    expect(find.byType(SplashLoader), findsOneWidget);
    expect(find.text('Get started'), findsNothing);
  });

  testWidgets('under "remove animations" the van is parked', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(ready: false, signedIn: false, onFinished: () {}, reduceMotion: true),
    );
    await tester.pump();
    // The only thing still ticking is the 1.5s floor timer, not an
    // animation: a looping van would never let the tree settle.
    expect(tester.hasRunningAnimations, isFalse);
    await pastTheFloor(tester);
  });
}
