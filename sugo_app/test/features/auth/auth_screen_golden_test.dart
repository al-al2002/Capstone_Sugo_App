import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sugo_app/core/constants/app_assets.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/auth/data/repositories/auth_repository.dart';
import 'package:sugo_app/features/auth/presentation/screens/auth_screen.dart';
import 'package:sugo_app/features/auth/presentation/widgets/auth_tab.dart';

import '../../support/fake_auth_repository.dart';

/// Renders both tabs for design review. Regenerate after intentional changes:
///
///   flutter test --update-goldens
///
/// Goldens are platform-specific; regenerate if they fail on another machine.
void main() {
  Future<void> pump(WidgetTester tester, AuthTab tab) async {
    // physicalSize is in physical px, so this is 390x900 logical.
    tester.view.physicalSize = const Size(780, 1800);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final FakeAuthRepository repository = FakeAuthRepository();
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      Provider<AuthRepository>.value(
        value: repository,
        child: MaterialApp(
          theme: AppTheme.light,
          home: AuthScreen(initialTab: tab),
        ),
      ),
    );

    // Image decoding is genuinely async, so it has to run outside the
    // fake-async zone or the banner captures blank.
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage(AppAssets.brandHeader),
        tester.binding.rootElement!,
      );
    });
    await tester.pumpAndSettle();
  }

  testWidgets('login tab', (WidgetTester tester) async {
    await pump(tester, AuthTab.login);
    await expectLater(
      find.byType(AuthScreen),
      matchesGoldenFile('../../goldens/auth_login.png'),
    );
  });

  testWidgets('register tab', (WidgetTester tester) async {
    await pump(tester, AuthTab.register);
    await expectLater(
      find.byType(AuthScreen),
      matchesGoldenFile('../../goldens/auth_register.png'),
    );
  });
}
