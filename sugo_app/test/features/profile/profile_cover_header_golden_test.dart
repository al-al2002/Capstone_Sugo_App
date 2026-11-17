import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/constants/app_sizes.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/core/widgets/sugo_brand_cover.dart';
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
              style: SugoCoverStyle.technician,
              roleLabel: 'Technician',
              onEdit: () {},
              badges: const <Widget>[
                ProfileBadge(
                  icon: Icons.verified_rounded,
                  label: 'ID verified',
                ),
              ],
              stats: const <ProfileStat>[
                ProfileStat(label: 'Rating', value: '4.8'),
                ProfileStat(label: 'Jobs done', value: '42', count: 42),
                ProfileStat(label: 'Points', value: '130', count: 130),
              ],
            ),
          ),
        ),
      ),
    );

    // The cover is drawn in code, so there is no image to wait for; settling
    // finishes the route drawing in and the figures rolling up.
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

  testWidgets('the role, the edit button and the figures (2026-11-16)', (
    WidgetTester tester,
  ) async {
    int edits = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfileCoverHeader(
              name: 'quiza',
              style: SugoCoverStyle.client,
              roleLabel: 'Client',
              onEdit: () => edits++,
              stats: const <ProfileStat>[
                ProfileStat(label: 'Bookings', value: '7', count: 7),
              ],
            ),
          ),
        ),
      ),
    );

    // Mid-animation the count is still rolling up...
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('7'), findsNothing);
    // ...and lands on the real figure.
    await tester.pumpAndSettle();
    expect(find.text('7'), findsOneWidget);
    expect(find.text('Bookings'), findsOneWidget);
    expect(find.text('Client'), findsOneWidget);

    await tester.tap(find.text('Edit'));
    expect(edits, 1);
  });

  testWidgets('no edit button on a profile that is not yours', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: ProfileCoverHeader(name: 'A client', roleLabel: 'Client'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('reduce motion: everything is there on the first frame', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: ProfileCoverHeader(
              name: 'quiza',
              stats: <ProfileStat>[
                ProfileStat(label: 'Bookings', value: '7', count: 7),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('7'), findsOneWidget);
  });
}
