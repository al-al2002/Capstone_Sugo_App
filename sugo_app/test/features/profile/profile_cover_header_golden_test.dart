import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/constants/app_sizes.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/profile/widgets/profile_cover_header.dart';

/// Renders the Profile tab's cover header for design review. Regenerate after
/// intentional changes:
///
///   flutter test --update-goldens
///
/// Goldens are platform-specific; regenerate if they fail on another machine.
void main() {
  Future<void> pump(WidgetTester tester, {required double width}) async {
    tester.view.physicalSize = Size(width * 2, 900);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSizes.screenPadding),
            child: ProfileCoverHeader(
              name: 'Maria Santos',
              verified: true,
              badges: <Widget>[
                for (final String label in <String>['Technician', 'ID verified'])
                  Chip(label: Text(label)),
              ],
            ),
          ),
        ),
      ),
    );

    // The cover is drawn in code since 2026-09-29, so there is no image to
    // wait for.
    await tester.pumpAndSettle();
  }

  testWidgets('phone width', (WidgetTester tester) async {
    await pump(tester, width: 390);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(ProfileCoverHeader),
      matchesGoldenFile('../../goldens/profile_cover_header.png'),
    );
  });

  testWidgets('a narrow phone lays out without overflow', (
    WidgetTester tester,
  ) async {
    await pump(tester, width: 320);
    expect(tester.takeException(), isNull);
  });
}
