import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/constants/app_colors.dart';
import 'package:sugo_app/core/constants/app_sizes.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/client/widgets/home_header.dart';
import 'package:sugo_app/features/client/widgets/service_category_row.dart';

/// The client home as a client with no booking under way sees it (the
/// 2026-11-16 renovation): the navy illustrated header carrying the greeting,
/// the invitation to book and the floating search, then the service grid.
/// For design review; regenerate after intentional changes with
/// `flutter test --update-goldens`.
void main() {
  Widget page({double width = 390, double scale = 1, VoidCallback? onBookNow}) {
    return MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 1300),
          textScaler: TextScaler.linear(scale),
          padding: const EdgeInsets.only(top: 32),
        ),
        child: Scaffold(
          backgroundColor: AppColors.background,
          // Explicit zero padding, as in the dashboard: without it a ListView
          // adds the status-bar inset itself, and the header would start
          // below a strip instead of running under the status bar.
          body: ListView(
            padding: EdgeInsets.zero,
            children: <Widget>[
              HomeHeader(
                name: 'Albert Santos',
                unreadNotifications: 3,
                unreadMessages: 0,
                onOpenNotifications: () {},
                onOpenMessages: () {},
                onSearch: () {},
                onBookNow: onBookNow,
                topInset: 32,
                // A fixed morning, so the greeting - and the golden - do not
                // depend on when the suite runs.
                now: DateTime(2026, 9, 29, 9),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSizes.screenPadding),
                child: ServiceCategoryGrid(onSelect: (_) {}),
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('home top at phone width', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(780, 2600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    int booked = 0;
    await tester.pumpWidget(page(onBookNow: () => booked++));
    await tester.pumpAndSettle();

    expect(find.textContaining(', Albert'), findsOneWidget);
    expect(find.text('Book a technician'), findsOneWidget);
    expect(find.text('Search a service or device'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Book a technician'));
    expect(booked, 1);

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('../../goldens/home_top.png'),
    );
  });

  testWidgets('with a booking under way there is no invitation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    expect(find.text('Book a technician'), findsNothing);
    expect(find.text('What needs fixing today?'), findsOneWidget);
  });

  testWidgets('a small phone at large text does not overflow', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(640, 2600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(page(width: 320, scale: 1.3, onBookNow: () {}));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
