import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sugo_app/core/services/local_prefs.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/rb_cars/models/job.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';
import 'package:sugo_app/features/rb_cars/models/technician.dart';
import 'package:sugo_app/features/rb_cars/models/technician_profile_details.dart';
import 'package:sugo_app/features/rb_cars/services/technician_directory_service.dart';
import 'package:sugo_app/features/tracking/models/job_tracking.dart';
import 'package:sugo_app/features/tracking/models/route_result.dart';
import 'package:sugo_app/features/tracking/models/trip_conditions.dart';
import 'package:sugo_app/features/tracking/screens/technician_delivery_screen.dart';
import 'package:sugo_app/features/tracking/services/delay_alerts.dart';
import 'package:sugo_app/features/tracking/services/tracking_service.dart';
import 'package:sugo_app/features/tracking/widgets/drop_off_route_card.dart';

/// The client's drop-off trip (2026-11-17, migration 20261117000006): the
/// client can call the technician and shares their trip in; the technician
/// follows them with an arrival time; both see the traffic and weather on
/// the way, and the technician is told - with the cause - if they run late.
void main() {
  const Job dropOff = Job(
    id: 'job-1',
    clientId: 'client-1',
    deviceType: DeviceType.laptop,
    problemSymptom: 'laptop_screen_broken',
    hasPhysicalDamage: true,
    status: JobStatus.confirmed,
    servicePath: ServicePath.pickup,
    deliveryOption: DeliveryOption.self,
    assignedTechnicianId: 'tech-1',
  );

  /// The client's trip in. [onTheWay] with "light traffic, good weather,
  /// two minutes out" unless told otherwise.
  JobTracking trip({
    bool onTheWay = true,
    bool arrived = false,
    double? delay,
    String? reason,
    String traffic = 'light traffic',
    double congestion = 0.1,
  }) {
    final DateTime now = DateTime.now();
    return JobTracking(
      id: 'track-1',
      jobId: 'job-1',
      technicianId: 'tech-1',
      stage: TrackingStage.droppingOff,
      clientTripStartedAt: onTheWay || arrived
          ? now.subtract(const Duration(minutes: 9))
          : null,
      clientArrivedAt: arrived ? now : null,
      expectedArrivalAt: now.add(const Duration(minutes: 2)),
      projectedArrivalAt: now.add(Duration(minutes: 2 + (delay ?? 0).round())),
      delayMinutes: delay,
      delayReason: reason,
      etaSampledAt: now,
      trafficLabel: traffic,
      trafficCongestion: congestion,
      weatherLabel: reason == 'weather' ? 'heavy rain' : 'clear sky',
      weatherSeverity: reason == 'weather' ? 0.7 : 0,
    );
  }

  group('the stage', () {
    test('is read from the wire, and is a client trip', () {
      final TrackingStage stage = TrackingStage.fromWire('dropping_off');
      expect(stage, TrackingStage.droppingOff);
      expect(stage.isClientTrip, isTrue);
      expect(TrackingStage.readyForCollection.isClientTrip, isTrue);
      expect(TrackingStage.headingToPickup.isClientTrip, isFalse);
      // The technician is not travelling: no technician map.
      expect(stage.showsMap, isFalse);
    });

    test('"Unit received" is the one move from it', () {
      expect(TrackingStage.droppingOff.nextOptions, <TrackingStage>[
        TrackingStage.inRepair,
      ]);
    });

    test('a drop-off timeline has no pickup legs', () {
      final List<TrackingStage> route = TrackingStage.timelineFor(
        TrackingStage.inRepair,
        dropOff: true,
      );
      expect(route, <TrackingStage>[
        TrackingStage.droppingOff,
        TrackingStage.inRepair,
        TrackingStage.readyForCollection,
        TrackingStage.delivered,
      ]);
      expect(route, isNot(contains(TrackingStage.headingToPickup)));
    });

    test('the client is on the way between the two taps', () {
      expect(trip().clientOnTheWay, isTrue);
      expect(trip(onTheWay: false).clientOnTheWay, isFalse);
      expect(trip(arrived: true).clientArrived, isTrue);
      expect(trip(arrived: true).clientOnTheWay, isFalse);
    });

    test('a late client alerts the technician, never the client', () {
      final JobTracking late = trip(delay: 12, reason: 'traffic');
      expect(DelayAlerts.isClientTripAlertable(late), isTrue);
      expect(DelayAlerts.isAlertable(late), isFalse);
    });
  });

  group('the words flip: the client is the traveller', () {
    test('the client reads "you", the technician reads "your client"', () {
      final TripConditions c = TripConditions.of(trip());
      expect(c.clientTravels, isTrue);
      expect(c.arrivalTitle(TripViewer.client), 'You arrive in');
      expect(c.arrivalTitle(TripViewer.technician), 'Your client arrives in');
      expect(c.destinationFor(TripViewer.client), 'to the shop');
      expect(c.destinationFor(TripViewer.technician), 'to your shop');
      expect(c.isTravelling(TripViewer.client), isTrue);
      expect(c.summary, 'Weather is good and traffic is light.');
    });
  });

  group("the client's card", () {
    Future<_FakeTracking> show(
      WidgetTester tester, {
      JobTracking? row,
      bool unlocked = true,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 2600);
      addTearDown(tester.view.reset);
      final _FakeTracking tracking = _FakeTracking(row: row);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(400, 2600),
              disableAnimations: true,
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: DropOffRouteCard(
                  jobId: 'job-1',
                  technicianId: 'tech-1',
                  trip: row,
                  directory: _FakeDirectory(unlocked: unlocked),
                  tracking: tracking,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return tracking;
    }

    // Stops the conditions card's countdown ticker.
    Future<void> close(WidgetTester tester) =>
        tester.pumpWidget(const SizedBox());

    testWidgets('shows the technician\'s number, with a Call button', (
      WidgetTester tester,
    ) async {
      await show(tester);
      expect(find.text('Call Ryan Santos when you arrive'), findsOneWidget);
      expect(find.text('0917 123 4567'), findsOneWidget);
      expect(find.text('Call'), findsOneWidget);
      await close(tester);
    });

    testWidgets('no number before the booking releases it', (
      WidgetTester tester,
    ) async {
      await show(tester, unlocked: false);
      expect(find.text('0917 123 4567'), findsNothing);
      expect(find.text('Call'), findsNothing);
      await close(tester);
    });

    testWidgets('"I\'m on my way" opens the trip in and shares it', (
      WidgetTester tester,
    ) async {
      final _FakeTracking tracking = await show(tester);
      expect(find.text('Setting off with it?'), findsOneWidget);

      await tester.tap(find.text("I'm on my way"));
      await tester.pump();
      await tester.pump();

      expect(tracking.calls, contains('start'));
      expect(tracking.listening, isTrue);
      // Moves on at once - the live row catches up after.
      expect(find.text('On your way to the shop'), findsOneWidget);
      expect(find.text("I've arrived"), findsOneWidget);
      await close(tester);
    });

    testWidgets('on the way: weather good, traffic light, 2 min away', (
      WidgetTester tester,
    ) async {
      await show(tester, row: trip());
      expect(find.text('YOU ARRIVE IN'), findsOneWidget);
      expect(find.text('2 min'), findsOneWidget);
      expect(
        find.textContaining('Weather is good and traffic is light'),
        findsOneWidget,
      );
      expect(find.text('Good'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await close(tester);
    });

    testWidgets('running late in traffic: told why, and that they know', (
      WidgetTester tester,
    ) async {
      await show(
        tester,
        row: trip(
          delay: 12,
          reason: 'traffic',
          traffic: 'heavy traffic',
          congestion: 0.7,
        ),
      );
      expect(find.text('Running about 10 minutes behind'), findsOneWidget);
      expect(
        find.text('Slowed by heavy traffic. Your technician can see why.'),
        findsOneWidget,
      );
      await close(tester);
    });
  });

  group("the technician's screen", () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      LocalPrefs.instance.debugReset();
      DelayAlerts.debugReset();
    });

    Future<_FakeTracking> open(WidgetTester tester, JobTracking? row) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(420, 2600);
      addTearDown(tester.view.reset);
      final _FakeTracking service = _FakeTracking(row: row);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: TechnicianDeliveryScreen(job: dropOff, service: service),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
      return service;
    }

    Future<void> close(WidgetTester tester) =>
        tester.pumpWidget(const SizedBox());

    testWidgets('before the client sets off: waiting, and Unit received', (
      WidgetTester tester,
    ) async {
      await open(tester, null);
      expect(find.text('Waiting for the client to set off'), findsOneWidget);
      expect(find.text('Unit received'), findsOneWidget);
      await close(tester);
    });

    testWidgets('the client on the way: who, when, and the conditions', (
      WidgetTester tester,
    ) async {
      await open(tester, trip());
      expect(find.text('The client is bringing it in'), findsOneWidget);
      expect(find.text('YOUR CLIENT ARRIVES IN'), findsOneWidget);
      expect(find.text('2 min'), findsOneWidget);
      expect(find.textContaining('to your shop'), findsWidgets);
      expect(
        find.textContaining('Weather is good and traffic is light'),
        findsOneWidget,
      );
      expect(find.text('Unit received'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await close(tester);
    });

    testWidgets('a late client: the cause, and a pop-up', (
      WidgetTester tester,
    ) async {
      final _FakeTracking service = await open(
        tester,
        trip(delay: 12, reason: 'weather'),
      );
      // The live feed delivers the late row, which raises the alert.
      service.emit(trip(delay: 12, reason: 'weather'));
      await tester.pumpAndSettle();

      expect(find.text('Running late'), findsOneWidget);
      expect(
        find.text('About 10 minutes behind because of bad weather.'),
        findsOneWidget,
      );
      expect(
        find.text('Delayed by bad weather. Their position is still live.'),
        findsWidgets,
      );
      await close(tester);
    });

    testWidgets('"Unit received" ends the trip in and starts the bench', (
      WidgetTester tester,
    ) async {
      final _FakeTracking service = await open(tester, trip(arrived: true));
      expect(
        find.text('Take the unit, then tap "Unit received" below.'),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('Unit received'));
      await tester.tap(find.text('Unit received'));
      await tester.pump();
      await tester.pump();

      expect(service.startedAt, TrackingStage.inRepair);
      expect(find.text('The client is bringing it in'), findsNothing);
      await close(tester);
    });
  });
}

class _FakeDirectory implements TechnicianDirectoryService {
  _FakeDirectory({this.unlocked = true});

  final bool unlocked;

  @override
  Future<TechnicianProfileDetails> profile(
    String technicianId, {
    double? latitude,
    double? longitude,
    int reviewLimit = 20,
  }) async => TechnicianProfileDetails(
    technician: const Technician(id: 'tech-1', fullName: 'Ryan Santos'),
    contactUnlocked: unlocked,
    phone: unlocked ? '0917 123 4567' : null,
    shopName: 'Santos Repair Hub',
    shopLatitude: 7.0731,
    shopLongitude: 125.6128,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTracking implements TrackingService {
  _FakeTracking({this.row});

  JobTracking? row;
  final List<String> calls = <String>[];
  TrackingStage? startedAt;

  final StreamController<Position> _positions =
      StreamController<Position>.broadcast();
  final StreamController<JobTracking?> _live =
      StreamController<JobTracking?>.broadcast();

  bool get listening => _positions.hasListener;

  void emit(JobTracking next) {
    row = next;
    _live.add(next);
  }

  // ------------------------------------------------ the technician's reads
  @override
  Future<JobTracking?> fetch(String jobId) async => row;

  @override
  Stream<JobTracking?> watch(String jobId) => _live.stream;

  @override
  Future<ReturnMethod?> returnChoice(String jobId) async =>
      ReturnMethod.clientPickup;

  @override
  Future<LatLng?> myWorkshop() async => const LatLng(7.0731, 125.6128);

  @override
  Future<JobTracking> start(String jobId, {TrackingStage? stage}) async {
    startedAt = stage;
    return JobTracking(
      id: 'track-1',
      jobId: jobId,
      technicianId: 'tech-1',
      stage: stage ?? TrackingStage.headingToPickup,
    );
  }

  // --------------------------------------------------- the client's trip
  @override
  Future<bool> locationAllowed() async => false;

  @override
  Future<LocationReadiness> prepareLocation() async =>
      const LocationReadiness.ready();

  @override
  Future<void> startCollectionTrip(String jobId) async => calls.add('start');

  @override
  Future<void> endCollectionTrip(String jobId) async => calls.add('end');

  @override
  Stream<Position> positionStream() => _positions.stream;

  @override
  Future<RouteResult> routeFor(
    String jobId, {
    required double originLatitude,
    required double originLongitude,
  }) async => const RouteResult.unavailable('no_location');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
