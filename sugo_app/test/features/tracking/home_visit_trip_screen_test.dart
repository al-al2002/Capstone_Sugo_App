import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/rb_cars/models/job.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';
import 'package:sugo_app/features/tracking/models/job_tracking.dart';
import 'package:sugo_app/features/tracking/screens/home_visit_trip_screen.dart';
import 'package:sugo_app/features/tracking/services/tracking_service.dart';

/// The technician's drive to a home visit (2026-09-29).
///
/// What matters most is what the screen does NOT do: opening it writes
/// nothing, so looking up the address never tells the client "on the way".
void main() {
  // No pinned address, so no network map in the test.
  const Job job = Job(
    id: 'job-1',
    clientId: 'client-1',
    deviceType: DeviceType.laptop,
    problemSymptom: 'laptop_wont_power_on',
    hasPhysicalDamage: false,
    status: JobStatus.confirmed,
    assignedTechnicianId: 'tech-1',
    servicePath: ServicePath.homeService,
  );

  Widget host(TrackingService service) => MaterialApp(
    theme: AppTheme.light,
    // Reduced motion: the trip's truck drives forever while sharing, which
    // `pumpAndSettle` would wait on for good. Its motion has its own test.
    builder: (BuildContext context, Widget? child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: child!,
    ),
    home: HomeVisitTripScreen(job: job, service: service),
  );

  testWidgets('opening it starts nothing; Start trip does', (
    WidgetTester tester,
  ) async {
    final _FakeTracking service = _FakeTracking();
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();

    expect(find.text('Not on the way yet'), findsOneWidget);
    expect(service.started, isFalse, reason: 'looking is not leaving');

    await tester.tap(find.text('Start trip'));
    await tester.pumpAndSettle();

    expect(service.started, isTrue);
    expect(service.listening, isTrue, reason: 'sharing turns on with the trip');
    expect(find.text('On the way to the client'), findsOneWidget);
    expect(find.text("I've arrived"), findsOneWidget);
  });

  testWidgets('no trip without location: the client would get an empty map', (
    WidgetTester tester,
  ) async {
    final _FakeTracking service = _FakeTracking(
      readiness: const LocationReadiness.blocked('Location is off.'),
    );
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start trip'));
    await tester.pumpAndSettle();

    expect(service.started, isFalse);
    expect(find.text('Location is off.'), findsOneWidget);
    expect(find.text('Not on the way yet'), findsOneWidget);
  });

  testWidgets('arriving closes the trip and stops sharing', (
    WidgetTester tester,
  ) async {
    final _FakeTracking service = _FakeTracking();
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start trip'));
    await tester.pumpAndSettle();

    await tester.tap(find.text("I've arrived"));
    await tester.pumpAndSettle();

    expect(service.stages, <TrackingStage>[TrackingStage.inRepair]);
    expect(service.listening, isFalse);
    expect(find.text('You have arrived'), findsOneWidget);
    expect(find.text("I've arrived"), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('coming back mid-trip shares again without a tap', (
    WidgetTester tester,
  ) async {
    // The user's ask (2026-09-29): a technician who forgets to switch it back
    // on must not leave the client watching a frozen pin.
    final _FakeTracking service = _FakeTracking(
      existing: TrackingStage.headingToPickup,
    );
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();

    expect(find.text('On the way to the client'), findsOneWidget);
    expect(service.listening, isTrue);
    expect(find.text('Share my location again'), findsNothing);
  });

  testWidgets('location switched off: a way to the setting, not a dead end', (
    WidgetTester tester,
  ) async {
    final _FakeTracking service = _FakeTracking(
      readiness: const LocationReadiness.blocked(
        'Location is switched off on this phone.',
        fix: LocationFix.locationSettings,
      ),
    );
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start trip'));
    await tester.pumpAndSettle();

    expect(service.started, isFalse);
    expect(find.text('Location is switched off on this phone.'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}

class _FakeTracking implements TrackingService {
  _FakeTracking({
    this.readiness = const LocationReadiness.ready(),
    TrackingStage? existing,
  }) : _row = existing == null ? null : _tracking(existing);

  final LocationReadiness readiness;
  JobTracking? _row;

  bool started = false;
  final List<TrackingStage> stages = <TrackingStage>[];
  final StreamController<Position> _positions =
      StreamController<Position>.broadcast();

  bool get listening => _positions.hasListener;

  static JobTracking _tracking(TrackingStage stage) => JobTracking(
    id: 'track-1',
    jobId: 'job-1',
    technicianId: 'tech-1',
    stage: stage,
  );

  @override
  Future<JobTracking?> fetch(String jobId) async => _row;

  @override
  Future<LocationReadiness> prepareLocation() async => readiness;

  @override
  Future<JobTracking> start(String jobId, {TrackingStage? stage}) async {
    started = true;
    return _row ??= _tracking(stage ?? TrackingStage.headingToPickup);
  }

  @override
  Future<JobTracking> setStage(String jobId, TrackingStage stage) async {
    stages.add(stage);
    return _row = _tracking(stage);
  }

  @override
  Stream<Position> positionStream() => _positions.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
