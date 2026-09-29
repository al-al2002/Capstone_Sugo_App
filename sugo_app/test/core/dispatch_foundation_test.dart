import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/constants/app_colors.dart';
import 'package:sugo_app/core/constants/app_sizes.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/core/widgets/sugo_button.dart';
import 'package:sugo_app/core/widgets/sugo_card.dart';
import 'package:sugo_app/core/widgets/sugo_route_line.dart';
import 'package:sugo_app/core/widgets/sugo_skeleton.dart';

/// The shared pieces the Dispatch redesign (2026-09-29) rebuilt: the route
/// line, the card's hairline edge, the small button's 48dp tap area, and the
/// "remove animations" setting.
void main() {
  Widget host(Widget child, {double width = 390, double scale = 1}) {
    return MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSizes.screenPadding),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  const List<String> stops = <String>['Posted', 'Matched', 'Booked', 'Fixed'];

  group('route line', () {
    testWidgets('names every stop and says where the job is', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          const SugoRouteLine(
            stops: stops,
            position: SugoRoutePosition.at(1),
          ),
        ),
      );

      for (final String stop in stops) {
        expect(find.text(stop), findsOneWidget);
      }
      expect(
        find.bySemanticsLabel(RegExp('Progress: Matched. Stop 2 of 4')),
        findsOneWidget,
      );
      // The current stop is the only bold label.
      final Text current = tester.widget<Text>(find.text('Matched'));
      final Text ahead = tester.widget<Text>(find.text('Booked'));
      expect(current.style?.fontWeight, FontWeight.w800);
      expect(ahead.style?.fontWeight, isNot(FontWeight.w800));
      semantics.dispose();
    });

    testWidgets('a moving job shows the van; an arrived one a tick', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          const SugoRouteLine(
            stops: stops,
            position: SugoRoutePosition.leaving(2),
          ),
        ),
      );
      expect(find.byIcon(Icons.local_shipping_rounded), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsNothing);

      await tester.pumpWidget(
        host(
          const SugoRouteLine(
            stops: stops,
            position: SugoRoutePosition.at(3),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byIcon(Icons.local_shipping_rounded), findsNothing);
    });

    testWidgets('a stage past the end is clamped onto the last stop', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          const SugoRouteLine(
            stops: stops,
            position: SugoRoutePosition.leaving(9),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        find.bySemanticsLabel(RegExp('Progress: Fixed. Stop 4 of 4')),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('fits a 320dp phone at 1.3x text', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(
          const SugoRouteLine(
            stops: stops,
            position: SugoRoutePosition.leaving(1),
          ),
          width: 320,
          scale: 1.3,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    test('positions compare by value', () {
      expect(
        const SugoRoutePosition.at(1),
        equals(const SugoRoutePosition.at(1)),
      );
      expect(
        const SugoRoutePosition.at(1),
        isNot(equals(const SugoRoutePosition.leaving(1))),
      );
      expect(const SugoRoutePosition.leaving(1).progress, 1.5);
    });
  });

  testWidgets('a resting card is flat, with a hairline edge', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(const SugoCard(child: Text('Card'))));

    final BoxDecoration decoration = tester
        .widget<AnimatedContainer>(
          find.descendant(
            of: find.byType(SugoCard),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .decoration! as BoxDecoration;
    expect(decoration.boxShadow, isEmpty);
    expect((decoration.border! as Border).top.color, AppColors.border);
    expect(
      decoration.borderRadius,
      BorderRadius.circular(AppSizes.radius),
    );
  });

  testWidgets('a small button answers a tap anywhere in its 48dp band', (
    WidgetTester tester,
  ) async {
    int taps = 0;
    await tester.pumpWidget(
      host(
        SugoButton(
          label: 'Track',
          size: SugoButtonSize.small,
          expand: false,
          onPressed: () => taps++,
        ),
      ),
    );

    final Rect band = tester.getRect(find.byType(SugoButton));
    expect(band.height, AppSizes.touchTarget);

    // 2px inside the top of the band: outside the 40px visible button.
    await tester.tapAt(Offset(band.center.dx, band.top + 2));
    // And the middle, which the button's own ink handles.
    await tester.tapAt(band.center);
    await tester.pumpAndSettle();
    expect(taps, 2);
  });

  testWidgets('skeletons hold still under "remove animations"', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: SugoSkeleton(width: 120)),
        ),
      ),
    );
    // A looping shimmer never settles; a still one does at once.
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });
}
