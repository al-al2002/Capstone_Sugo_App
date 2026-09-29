import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sugo_app/core/config/app_env.dart';
import 'package:sugo_app/core/constants/app_colors.dart';
import 'package:sugo_app/core/widgets/sugo_map.dart';

/// The shared map pieces (2026-09-29): sharp tiles, the route line that
/// shrinks behind the marker, and the pulse that only means "live".
void main() {
  group('the tiles', () {
    test('ask for @2x on a high-density phone', () {
      // `{r}` is what flutter_map fills with "@2x" in retina mode.
      expect(AppEnv.mapTilerTileUrl, contains('{y}{r}.png'));
      expect(AppEnv.mapTilerTileUrl, contains('/maps/dataviz/'));
    });
  });

  group('the route line', () {
    // A straight street, roughly 110 m between points.
    final List<LatLng> route = <LatLng>[
      for (int i = 0; i < 6; i++) LatLng(7.0700 + i * 0.001, 125.6100),
    ];

    test('starts at the marker and drops what is already behind', () {
      const LatLng van = LatLng(7.0721, 125.6100); // near point 2
      final List<LatLng> ahead = routeAhead(van, route);
      expect(ahead.first, van);
      expect(ahead.length, 1 + 4, reason: 'the marker, then points 2..5');
      expect(ahead.last, route.last);
    });

    test('knows when the traveller has left it', () {
      expect(distanceToRoute(const LatLng(7.0720, 125.6100), route), lessThan(5));
      // About 330 m east of the street: past the 200 m re-route threshold.
      expect(
        distanceToRoute(const LatLng(7.0720, 125.6130), route),
        greaterThan(200),
      );
    });
  });

  group('the travelling marker', () {
    Widget host(Widget child) =>
        MaterialApp(home: Scaffold(body: Center(child: child)));

    testWidgets('pulses while live', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          const SugoTravellerMarker(
            icon: Icons.directions_car_rounded,
            color: AppColors.primary,
            isLive: true,
          ),
        ),
      );
      expect(tester.binding.hasScheduledFrame, isTrue);
      // Tear down so the repeating pulse does not outlive the test.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('is still once the position is old', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          const SugoTravellerMarker(
            icon: Icons.directions_car_rounded,
            color: AppColors.primary,
            isLive: false,
          ),
        ),
      );
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('is still under reduced motion, even when live', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: host(
            const SugoTravellerMarker(
              icon: Icons.directions_car_rounded,
              color: AppColors.primary,
              isLive: true,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}
