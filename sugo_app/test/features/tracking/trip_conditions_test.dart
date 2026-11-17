import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/tracking/models/job_tracking.dart';
import 'package:sugo_app/features/tracking/models/trip_conditions.dart';
import 'package:sugo_app/features/tracking/widgets/trip_conditions_card.dart';

/// The trip card on home-service and shop-pickup legs (2026-11-17):
/// "Arriving in 20 min · Weather is good and traffic is light".
void main() {
  final DateTime now = DateTime(2026, 11, 17, 15);

  JobTracking trip({
    TrackingStage stage = TrackingStage.headingToPickup,
    int? etaMinutes = 20,
    String? traffic = 'light traffic',
    double? congestion = 0.2,
    String? weather = 'clear weather',
    double? severity = 0,
    double? delay,
    String? reason,
    bool sampled = true,
  }) => JobTracking(
    id: 't1',
    jobId: 'j1',
    technicianId: 'tech',
    stage: stage,
    latitude: 7.07,
    longitude: 125.61,
    // The real clock, not [now]: "LIVE" is `JobTracking.isLive`, which reads
    // DateTime.now(). Pinned to the fixed clock, this test passed only until
    // 15:01 each day.
    updatedAt: DateTime.now(),
    projectedArrivalAt: etaMinutes == null
        ? null
        : now.add(Duration(minutes: etaMinutes)),
    etaSampledAt: sampled ? now.subtract(const Duration(seconds: 20)) : null,
    delayMinutes: delay,
    delayReason: reason,
    trafficLabel: traffic,
    trafficCongestion: congestion,
    weatherLabel: weather,
    weatherSeverity: severity,
  );

  group('reading the row', () {
    test('the server columns are parsed and survive asClientTrip', () {
      final JobTracking row = JobTracking.fromJson(<String, dynamic>{
        'id': 't1',
        'job_id': 'j1',
        'technician_id': 'tech',
        'stage': 'heading_to_pickup',
        'traffic_label': 'heavy traffic',
        'traffic_congestion': '0.720',
        'weather_label': 'light rain',
        'weather_severity': 0.55,
      });
      expect(row.trafficLabel, 'heavy traffic');
      expect(row.trafficCongestion, 0.72);
      expect(row.weatherLabel, 'light rain');
      expect(row.weatherSeverity, 0.55);
      expect(row.asClientTrip().trafficLabel, 'heavy traffic');
      expect(row.asClientTrip().weatherSeverity, 0.55);
    });
  });

  group('levels, on the server\'s own lines', () {
    test('traffic follows describe() in tomtom.ts', () {
      expect(TrafficLevel.from(label: 'clear roads'), TrafficLevel.clear);
      expect(TrafficLevel.from(label: 'Light traffic'), TrafficLevel.light);
      expect(
        TrafficLevel.from(label: 'road closure nearby'),
        TrafficLevel.closed,
      );
      // No label: the same cut-offs from the number.
      expect(TrafficLevel.from(congestion: 0.14), TrafficLevel.clear);
      expect(TrafficLevel.from(congestion: 0.15), TrafficLevel.light);
      expect(TrafficLevel.from(congestion: 0.35), TrafficLevel.moderate);
      expect(TrafficLevel.from(congestion: 0.6), TrafficLevel.heavy);
      expect(TrafficLevel.from(), isNull);
    });

    test('weather turns bad at 0.4, the delay-attribution line', () {
      expect(WeatherLevel.fromSeverity(0), WeatherLevel.good); // clear
      expect(WeatherLevel.fromSeverity(0.1), WeatherLevel.good); // clouds
      expect(WeatherLevel.fromSeverity(0.3), WeatherLevel.fair); // mist
      expect(WeatherLevel.fromSeverity(0.35), WeatherLevel.fair); // drizzle
      expect(WeatherLevel.fromSeverity(0.4), WeatherLevel.bad);
      expect(WeatherLevel.fromSeverity(0.55), WeatherLevel.bad); // rain
      expect(WeatherLevel.fromSeverity(null), isNull);
    });
  });

  group('what it says', () {
    test('the user\'s example sentence', () {
      final TripConditions c = TripConditions.of(trip(), now: now);
      expect(c.summary, 'Weather is good and traffic is light.');
      expect(c.etaLabel, '20 min');
      expect(c.looksClear, isTrue);
      expect(c.freshness, 'Updated just now');
    });

    test('bad weather is named in the provider\'s words', () {
      final TripConditions c = TripConditions.of(
        trip(
          weather: 'heavy intensity rain',
          severity: 0.85,
          traffic: 'heavy traffic',
          congestion: 0.7,
        ),
        now: now,
      );
      expect(c.summary, 'Heavy intensity rain and traffic is heavy.');
      expect(c.looksClear, isFalse);
    });

    test('only what was measured', () {
      expect(
        TripConditions.of(
          trip(weather: null, severity: null),
          now: now,
        ).summary,
        'Traffic is light.',
      );
      expect(
        TripConditions.of(
          trip(traffic: null, congestion: null),
          now: now,
        ).summary,
        'Weather is good.',
      );
      expect(
        TripConditions.of(
          trip(traffic: null, congestion: null, weather: null, severity: null),
          now: now,
        ).summary,
        isNull,
      );
    });

    test('the countdown', () {
      expect(TripConditions.of(trip(etaMinutes: 0), now: now).etaLabel, 'Now');
      expect(
        TripConditions.of(trip(etaMinutes: 65), now: now).etaLabel,
        '1 h 5 min',
      );
      expect(
        TripConditions.of(trip(etaMinutes: 120), now: now).etaLabel,
        '2 h',
      );
      expect(
        TripConditions.of(trip(etaMinutes: null), now: now).etaLabel,
        isNull,
      );
    });

    test('worded for whoever is looking, and where the leg ends', () {
      final TripConditions home = TripConditions.of(trip(), now: now);
      expect(
        home.arrivalTitle(TripViewer.client),
        'Your technician arrives in',
      );
      expect(home.arrivalTitle(TripViewer.technician), 'You arrive in');
      expect(home.destinationFor(TripViewer.client), 'to your home');
      expect(home.destinationFor(TripViewer.technician), 'to the client');

      final TripConditions shop = TripConditions.of(
        trip(stage: TrackingStage.returningToShop),
        now: now,
      );
      expect(shop.arrivalTitle(TripViewer.client), 'At the workshop in');
      expect(shop.destinationFor(TripViewer.client), 'to the workshop');
    });
  });

  group('the card', () {
    // Reduced motion: the pictures hold still, so frames settle.
    Future<void> show(
      WidgetTester tester,
      JobTracking tracking, {
      TripViewer viewer = TripViewer.client,
      Size size = const Size(400, 900),
      double textScale = 1,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              disableAnimations: true,
              textScaler: TextScaler.linear(textScale),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: TripConditionsCard(
                  tracking: tracking,
                  viewer: viewer,
                  distanceKm: 4.2,
                  clock: () => now,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Future<void> close(WidgetTester tester) =>
        tester.pumpWidget(const SizedBox()); // stops the countdown ticker

    testWidgets('client, clear trip: countdown, both tiles, the sentence', (
      WidgetTester tester,
    ) async {
      await show(tester, trip());

      expect(find.text('YOUR TECHNICIAN ARRIVES IN'), findsOneWidget);
      expect(find.text('20 min'), findsOneWidget);
      expect(find.textContaining('to your home'), findsOneWidget);
      expect(find.textContaining('4.2 km'), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('Good'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(
        find.text('Weather is good and traffic is light. On schedule.'),
        findsOneWidget,
      );
      expect(find.textContaining('Running'), findsNothing);
      await close(tester);
    });

    testWidgets('client, late in traffic: the strip says how late and why', (
      WidgetTester tester,
    ) async {
      await show(
        tester,
        trip(
          traffic: 'heavy traffic',
          congestion: 0.72,
          delay: 15,
          reason: 'traffic',
          etaMinutes: 35,
        ),
      );

      expect(find.text('35 min'), findsOneWidget);
      expect(find.text('Heavy'), findsOneWidget);
      expect(find.text('Running about 15 minutes behind'), findsOneWidget);
      expect(
        find.text('Delayed by heavy traffic. Their position is still live.'),
        findsOneWidget,
      );
      // The summary steps aside for the strip rather than repeating it.
      expect(find.textContaining('On schedule'), findsNothing);
      await close(tester);
    });

    testWidgets('technician, late: worded for the driver, no excuse invented', (
      WidgetTester tester,
    ) async {
      await show(tester, trip(delay: 12), viewer: TripViewer.technician);

      expect(find.text('YOU ARRIVE IN'), findsOneWidget);
      expect(find.textContaining('to the client'), findsOneWidget);
      expect(
        find.text('Behind your first estimate. Your client can see this.'),
        findsOneWidget,
      );
      await close(tester);
    });

    testWidgets('before the first sample: "Calculating" and "Checking"', (
      WidgetTester tester,
    ) async {
      await show(
        tester,
        trip(
          etaMinutes: null,
          sampled: false,
          traffic: null,
          congestion: null,
          weather: null,
          severity: null,
        ),
      );

      expect(find.text('Calculating…'), findsOneWidget);
      expect(find.text('Checking…'), findsNWidgets(2));
      await close(tester);
    });

    testWidgets('a provider down after sampling reads "Not available"', (
      WidgetTester tester,
    ) async {
      await show(tester, trip(weather: null, severity: null));

      expect(find.text('Not available'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      await close(tester);
    });

    testWidgets('fits a small phone at large text, late and in the rain', (
      WidgetTester tester,
    ) async {
      await show(
        tester,
        trip(
          weather: 'heavy intensity rain',
          severity: 0.85,
          traffic: 'road closure nearby',
          congestion: 0.9,
          delay: 25,
          reason: 'both',
          etaMinutes: 75,
        ),
        size: const Size(320, 900),
        textScale: 1.3,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Road closure'), findsOneWidget);
      await close(tester);
    });
  });
}
