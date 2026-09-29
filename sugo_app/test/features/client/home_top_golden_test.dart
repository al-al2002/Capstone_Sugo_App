import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/constants/app_assets.dart';
import 'package:sugo_app/core/constants/app_colors.dart';
import 'package:sugo_app/core/constants/app_sizes.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/client/widgets/home_header.dart';
import 'package:sugo_app/features/client/widgets/home_hero_banner.dart';
import 'package:sugo_app/features/client/widgets/home_hero_slot.dart';
import 'package:sugo_app/features/client/widgets/service_category_row.dart';

/// The client home as a client with no booking under way sees it: the light
/// Dispatch header with greeting and search, the "Need a tech fix?" card, the
/// service grid.
/// For design review; regenerate after intentional changes with
/// `flutter test --update-goldens`.
void main() {
  Widget page({double width = 390, double scale = 1}) {
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
          // adds the status-bar inset itself, and the navy header would start
          // below a white strip instead of running under the status bar.
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
                topInset: 32,
                // A fixed morning, so the greeting - and the golden - do not
                // depend on when the suite runs.
                now: DateTime(2026, 9, 29, 9),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSizes.screenPadding),
                // Stretched and inside the slot, exactly as the dashboard
                // lays it out - the banner shrank to a narrow box once, in a
                // bare AnimatedSwitcher, and a test that placed it directly
                // in a column could not see it.
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    HomeHeroSlot(
                      child: HomeHeroBanner(
                        key: const ValueKey<String>('hero-banner'),
                        onBookNow: () {},
                      ),
                    ),
                    const SizedBox(height: AppSizes.xxl),
                    ServiceCategoryGrid(onSelect: (_) {}),
                  ],
                ),
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

    await tester.pumpWidget(page());
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage(AppAssets.bannerTechnician),
        tester.binding.rootElement!,
      );
    });
    await tester.pumpAndSettle();

    expect(find.textContaining(', Albert'), findsOneWidget);
    expect(find.text('Need a tech fix?'), findsOneWidget);
    // Full width, checked on the constraint the banner is given - not only on
    // its size, which the wide test font fills out even when the banner is
    // only offered a loose width (the 2026-09-28 bug).
    final RenderBox banner = tester.renderObject<RenderBox>(
      find.byType(HomeHeroBanner),
    );
    expect(banner.constraints.hasTightWidth, isTrue);
    expect(
      banner.size.width,
      moreOrLessEquals(390 - 2 * AppSizes.screenPadding, epsilon: 0.5),
    );
    expect(find.text('Book now'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('../../goldens/home_top.png'),
    );
  });

  testWidgets('a small phone at large text does not overflow', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(640, 2600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(page(width: 320, scale: 1.3));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
