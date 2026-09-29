import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/rb_cars/models/job.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';
import 'package:sugo_app/features/tracking/models/job_tracking.dart';
import 'package:sugo_app/features/tracking/screens/technician_delivery_screen.dart';
import 'package:sugo_app/features/tracking/services/tracking_service.dart';

/// Location switches itself on for a pickup's travelling legs (2026-09-29).
///
/// It used to be a switch the technician had to remember before the stage
/// button would even enable - and a forgotten switch meant a client watching
/// a map with nothing moving on it.
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
    servicePath: ServicePath.pickup,
  );

  Widget host(TrackingService service) => MaterialApp(
    theme: AppTheme.light,
    // Reduced motion: the trip's truck drives forever while sharing, which
    // `pumpAndSettle` would wait on for good. Its motion has its own test.
    builder: (BuildContext context, Widget? child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: child!,
    ),
    home: TechnicianDeliveryScreen(job: job, service: service),
  );

  // Tall enough that the whole screen is built: a ListView only builds what
  // is on screen, and the stage button sits at the bottom.
  setUp(() {
    final TestWidgetsFlutterBinding binding =
        TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(
      1200,
      4000,
    );
    binding.platformDispatcher.views.first.devicePixelRatio = 3;
  });
  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('"Start the delivery" turns location on, then moves the stage', (
    WidgetTester tester,
  ) async {
    final _FakeTracking service = _FakeTracking(TrackingStage.inRepair);
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();

    // On the bench nothing travels, so nothing is shared yet.
    expect(service.listening, isFalse);
    expect(find.textContaining('turns on when you tap below'), findsOneWidget);

    await tester.tap(find.text('Start the delivery'));
    await tester.pumpAndSettle();

    expect(service.listening, isTrue);
    expect(service.stages, <TrackingStage>[TrackingStage.outForDelivery]);
  });

  testWidgets('if location cannot come on, the stage waits', (
    WidgetTester tester,
  ) async {
    final _FakeTracking service = _FakeTracking(
      TrackingStage.inRepair,
      readiness: const LocationReadiness.blocked(
        'Location is switched off on this phone.',
        fix: LocationFix.locationSettings,
      ),
    );
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start the delivery'));
    await tester.pumpAndSettle();

    expect(service.stages, isEmpty);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('opened mid-delivery, it is already sharing', (
    WidgetTester tester,
  ) async {
    final _FakeTracking service = _FakeTracking(TrackingStage.outForDelivery);
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();

    expect(service.listening, isTrue);
  });
}

class _FakeTracking implements TrackingService {
  _FakeTracking(
    TrackingStage stage, {
    this.readiness = const LocationReadiness.ready(),
  }) : _row = _tracking(stage);

  final LocationReadiness readiness;
  JobTracking _row;
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
  Future<JobTracking> start(String jobId, {TrackingStage? stage}) async => _row;

  @override
  Future<ReturnMethod?> returnChoice(String jobId) async =>
      ReturnMethod.delivery;

  @override
  Future<LocationReadiness> prepareLocation() async => readiness;

  @override
  Stream<Position> positionStream() => _positions.stream;

  @override
  Future<JobTracking> setStage(String jobId, TrackingStage stage) async {
    stages.add(stage);
    return _row = _tracking(stage);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
