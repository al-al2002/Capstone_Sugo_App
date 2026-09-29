import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sugo_app/core/services/local_prefs.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/tracking/models/job_tracking.dart';
import 'package:sugo_app/features/tracking/services/delay_alerts.dart';
import 'package:sugo_app/features/tracking/services/tracking_service.dart';
import 'package:sugo_app/features/tracking/widgets/client_trip_card.dart';
import 'package:sugo_app/features/tracking/widgets/collection_trip_panel.dart';
import 'package:sugo_app/features/tracking/widgets/delay_alert_dialog.dart';

/// The client's trip to the workshop to collect their unit (2026-09-29): the
/// technician sees it, and hears if it runs late.
void main() {
  final DateTime promise = DateTime.utc(2026, 9, 29, 15);

  JobTracking row({
    TrackingStage stage = TrackingStage.readyForCollection,
    DateTime? started,
    DateTime? arrived,
    double? clientLat,
    double? delay,
    String? reason,
  }) => JobTracking(
    id: 'track-1',
    jobId: 'job-1',
    technicianId: 'tech-1',
    stage: stage,
    // The technician's last position, from the previous leg. Must never be
    // mistaken for the client's.
    latitude: 7.1,
    longitude: 125.6,
    expectedArrivalAt: started == null ? null : promise,
    delayMinutes: delay,
    delayReason: reason,
    clientTripStartedAt: started,
    clientArrivedAt: arrived,
    clientLatitude: clientLat,
    clientLongitude: clientLat == null ? null : 125.4,
  );

  final DateTime setOff = DateTime(2026, 9, 29, 14, 40);

  group('the model', () {
    test('reads the client columns', () {
      final JobTracking t = JobTracking.fromJson(<String, dynamic>{
        'id': 't',
        'job_id': 'j',
        'technician_id': 'tech',
        'stage': 'ready_for_collection',
        'client_latitude': 7.05,
        'client_longitude': 125.5,
        'client_trip_started_at': '2026-09-29T06:40:00Z',
      });
      expect(t.clientOnTheWay, isTrue);
      expect(t.hasClientPosition, isTrue);
    });

    test('the trip exists only between "on my way" and "arrived"', () {
      expect(row().clientOnTheWay, isFalse);
      expect(row(started: setOff).clientOnTheWay, isTrue);
      expect(
        row(started: setOff, arrived: setOff).clientOnTheWay,
        isFalse,
      );
      expect(row(started: setOff, arrived: setOff).clientArrived, isTrue);
      // Only ever on the collection leg.
      expect(
        row(stage: TrackingStage.outForDelivery, started: setOff).clientOnTheWay,
        isFalse,
      );
    });

    test('on the map, the client is the one drawn - not the technician', () {
      final JobTracking map = row(started: setOff, clientLat: 7.02)
          .asClientTrip();
      expect(map.latitude, 7.02);
      expect(map.longitude, 125.4);
    });
  });

  group('who is told it is late', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      LocalPrefs.instance.debugReset();
      DelayAlerts.debugReset();
    });

    test('a late client alerts the technician', () async {
      final JobTracking late = row(started: setOff, delay: 15);
      expect(DelayAlerts.isClientTripAlertable(late), isTrue);
      expect(await DelayAlerts.claim(late, clientTrip: true), isTrue);
      expect(await DelayAlerts.claim(late, clientTrip: true), isFalse);
    });

    test('and never tells the client their technician is late', () {
      // The client's own screen asks `isAlertable`; on their trip it must say
      // no, or they would be told about themselves.
      expect(DelayAlerts.isAlertable(row(started: setOff, delay: 15)), isFalse);
    });

    test('no alert before they set off, or after they arrive', () {
      expect(DelayAlerts.isClientTripAlertable(row(delay: 15)), isFalse);
      expect(
        DelayAlerts.isClientTripAlertable(
          row(started: setOff, arrived: setOff, delay: 15),
        ),
        isFalse,
      );
    });

    testWidgets('the technician\'s pop-up is about the client', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: TextButton(
                onPressed: () => maybeShowDelayAlert(
                  context,
                  row(started: setOff, delay: 15, reason: 'weather'),
                  clientTrip: true,
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('Running late'), findsOneWidget);
      expect(
        find.text('About 15 minutes behind because of bad weather.'),
        findsOneWidget,
      );
      expect(find.textContaining('Your client is still on the way'), findsOneWidget);
    });
  });

  group("the client's panel", () {
    Widget host(JobTracking tracking, TrackingService service) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: CollectionTripPanel(tracking: tracking, service: service),
        ),
      ),
    );

    testWidgets('"I\'m on my way" opens the trip and starts sharing', (
      WidgetTester tester,
    ) async {
      final _FakeTracking service = _FakeTracking();
      await tester.pumpWidget(host(row(), service));

      expect(find.text('Heading over?'), findsOneWidget);
      await tester.tap(find.text("I'm on my way"));
      await tester.pumpAndSettle();

      expect(service.calls, <String>['start']);
      expect(service.listening, isTrue);
    });

    testWidgets('nothing is shared without location permission', (
      WidgetTester tester,
    ) async {
      final _FakeTracking service = _FakeTracking(
        readiness: const LocationReadiness.blocked('Location is off.'),
      );
      await tester.pumpWidget(host(row(), service));

      await tester.tap(find.text("I'm on my way"));
      await tester.pumpAndSettle();

      expect(service.calls, isEmpty);
      expect(service.listening, isFalse);
      expect(find.text('Location is off.'), findsOneWidget);
    });

    testWidgets('back mid-trip shares again by itself; arriving stops it', (
      WidgetTester tester,
    ) async {
      final _FakeTracking service = _FakeTracking();
      await tester.pumpWidget(host(row(started: setOff), service));
      await tester.pumpAndSettle();

      expect(find.text('On your way to the shop'), findsOneWidget);
      // No tap: a client who forgot is still on the map.
      expect(service.listening, isTrue);
      expect(find.text('Share my location again'), findsNothing);

      await tester.tap(find.text("I've arrived"));
      await tester.pumpAndSettle();

      expect(service.calls, <String>['end']);
      expect(service.listening, isFalse);
    });
  });

  group("the technician's card", () {
    Widget host(JobTracking tracking) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: ClientTripCard(tracking: tracking)),
    );

    testWidgets('waits for the client to set off', (WidgetTester tester) async {
      await tester.pumpWidget(host(row()));
      expect(find.text('Waiting for the client to set off'), findsOneWidget);
    });

    testWidgets('shows the delay, and its cause, while they travel', (
      WidgetTester tester,
    ) async {
      // No position yet, so no network map in the test.
      await tester.pumpWidget(
        host(row(started: setOff, delay: 15, reason: 'traffic')),
      );
      expect(find.text('The client is on the way'), findsOneWidget);
      expect(
        find.text('Running about 15 minutes behind · heavy traffic'),
        findsOneWidget,
      );
      expect(find.textContaining('Waiting for their first position'), findsOneWidget);
    });

    testWidgets('says when they have arrived', (WidgetTester tester) async {
      await tester.pumpWidget(host(row(started: setOff, arrived: setOff)));
      expect(find.text('The client has arrived'), findsOneWidget);
    });
  });
}

class _FakeTracking implements TrackingService {
  _FakeTracking({this.readiness = const LocationReadiness.ready()});

  final LocationReadiness readiness;
  final List<String> calls = <String>[];
  final StreamController<Position> _positions =
      StreamController<Position>.broadcast();

  bool get listening => _positions.hasListener;

  @override
  Future<LocationReadiness> prepareLocation() async => readiness;

  @override
  Future<void> startCollectionTrip(String jobId) async => calls.add('start');

  @override
  Future<void> endCollectionTrip(String jobId) async => calls.add('end');

  @override
  Stream<Position> positionStream() => _positions.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
