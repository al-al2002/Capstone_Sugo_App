import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sugo_app/features/tracking/models/route_result.dart';

/// The in-app route screen spends a TomTom call whenever the user is judged
/// "off route", so that judgement is pinned here with real distances rather
/// than trusted to look right on a map.
void main() {
  group('RouteGeometry.distanceToPolylineMeters', () {
    // A straight east-west street in Davao, ~1.1 km long.
    const List<LatLng> street = <LatLng>[
      LatLng(7.0700, 125.6100),
      LatLng(7.0700, 125.6200),
    ];

    test('a point on the line is ~0 m away', () {
      final double d = RouteGeometry.distanceToPolylineMeters(
        const LatLng(7.0700, 125.6150),
        street,
      );
      expect(d, lessThan(1));
    });

    test('a point 100 m north of the line is ~100 m away', () {
      // 100 m of latitude is 100 / 111195 degrees.
      final double d = RouteGeometry.distanceToPolylineMeters(
        const LatLng(7.0700 + 100 / 111195, 125.6150),
        street,
      );
      expect(d, closeTo(100, 1));
    });

    test('past the end, distance is to the endpoint, not the extended line', () {
      // Due east of the last point, on the line's extension. Measuring to the
      // infinite line would say 0 and never trigger a reroute for someone who
      // has driven straight past the destination street.
      final double d = RouteGeometry.distanceToPolylineMeters(
        const LatLng(7.0700, 125.6200 + 200 / (111195 * 0.9925)),
        street,
      );
      expect(d, closeTo(200, 2));
    });

    test('ordinary GPS jitter does not count as off route', () {
      final double d = RouteGeometry.distanceToPolylineMeters(
        const LatLng(7.0700 + 12 / 111195, 125.6130),
        street,
      );
      expect(d, lessThan(60), reason: 'the screen reroutes beyond 60 m');
    });

    test('no line means always off route', () {
      expect(
        RouteGeometry.distanceToPolylineMeters(
          const LatLng(7.07, 125.61),
          const <LatLng>[],
        ),
        double.infinity,
      );
    });
  });

  group('RouteResult.fromJson', () {
    test('parses points, labels and a meaningful traffic delay', () {
      final RouteResult r = RouteResult.fromJson(<String, dynamic>{
        'available': true,
        'points': <List<double>>[
          <double>[7.07, 125.61],
          <double>[7.08, 125.62],
        ],
        'distance_m': 3420,
        'travel_s': 740,
        'traffic_delay_s': 180,
        'destination': <String, dynamic>{
          'latitude': 7.08,
          'longitude': 125.62,
          'label': 'Workshop',
        },
      });

      expect(r.available, isTrue);
      expect(r.points, hasLength(2));
      expect(r.distanceLabel, '3.4 km');
      expect(r.etaLabel, '12 min');
      expect(r.hasMeaningfulTrafficDelay, isTrue);
      expect(r.trafficDelayLabel, '+3 min traffic');
      expect(r.destinationLabel, 'Workshop');
    });

    test('a small traffic delay is not advertised', () {
      final RouteResult r = RouteResult.fromJson(<String, dynamic>{
        'available': true,
        'points': <List<double>>[
          <double>[7.07, 125.61],
          <double>[7.08, 125.62],
        ],
        'traffic_delay_s': 20,
      });
      expect(r.hasMeaningfulTrafficDelay, isFalse);
    });

    test('an unavailable route carries a readable reason', () {
      final RouteResult r = RouteResult.fromJson(<String, dynamic>{
        'available': false,
        'reason': 'no_route',
      });
      expect(r.available, isFalse);
      expect(r.unavailableMessage, contains('No road route'));
    });

    test('a route with fewer than two points is not drawable', () {
      final RouteResult r = RouteResult.fromJson(<String, dynamic>{
        'available': true,
        'points': <List<double>>[
          <double>[7.07, 125.61],
        ],
      });
      expect(r.available, isFalse);
    });
  });
}
