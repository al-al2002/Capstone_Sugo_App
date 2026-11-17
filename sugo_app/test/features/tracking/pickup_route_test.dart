import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/rb_cars/models/job.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';
import 'package:sugo_app/features/technician/widgets/technician_job_actions.dart';
import 'package:sugo_app/features/tracking/models/job_tracking.dart';
import 'package:sugo_app/features/tracking/screens/technician_delivery_screen.dart';
import 'package:sugo_app/features/tracking/services/tracking_service.dart';
import 'package:sugo_app/features/tracking/widgets/route_map_card.dart';

/// A shop repair the technician collects and brings back (2026-11-17): the
/// route to the client is there for both trips, not only the return.
void main() {
  Job job({DeliveryOption option = DeliveryOption.delivery}) => Job(
    id: 'job-1',
    clientId: 'client-1',
    deviceType: DeviceType.laptop,
    problemSymptom: 'laptop_screen_broken',
    hasPhysicalDamage: true,
    status: JobStatus.confirmed,
    servicePath: ServicePath.pickup,
    deliveryOption: option,
    assignedTechnicianId: 'tech-1',
    latitude: 7.0731,
    longitude: 125.6128,
    addressText: 'Matina Crossing, Davao City',
  );

  group('the job page', () {
    Future<void> show(WidgetTester tester, Job j) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 1600);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: TechnicianJobActions(
                job: j,
                onTrip: () {},
                onComplete: () {},
                onNeedsShop: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('pickup and delivery shows the client\'s address', (
      WidgetTester tester,
    ) async {
      await show(tester, job());
      expect(find.byType(RouteMapPreview), findsOneWidget);
      expect(find.text('Matina Crossing, Davao City'), findsWidgets);
      expect(find.text('Route to the client, both trips'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a drop-off does not - the client comes to the shop', (
      WidgetTester tester,
    ) async {
      await show(tester, job(option: DeliveryOption.self));
      expect(find.byType(RouteMapPreview), findsNothing);
    });
  });

  group('the pickup screen', () {
    Future<void> open(WidgetTester tester, TrackingStage stage) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(420, 3000);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          // Reduced motion: the truck drives forever while sharing.
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: TechnicianDeliveryScreen(
            job: job(),
            service: _FakeTracking(stage),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('on the way to collect it: the road to the client', (
      WidgetTester tester,
    ) async {
      await open(tester, TrackingStage.headingToPickup);
      expect(find.text('Collect it from the client'), findsOneWidget);
      expect(find.textContaining('Trip 1 of 2'), findsOneWidget);
      expect(find.byType(RouteMapCard), findsOneWidget);
      expect(find.text('Client address'), findsOneWidget);
      expect(find.text('Show route'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('unit in hand, heading to the shop: no client route', (
      WidgetTester tester,
    ) async {
      await open(tester, TrackingStage.collected);
      expect(find.text('Collect it from the client'), findsNothing);
    });
  });
}

class _FakeTracking implements TrackingService {
  _FakeTracking(TrackingStage stage)
    : _row = JobTracking(
        id: 'track-1',
        jobId: 'job-1',
        technicianId: 'tech-1',
        stage: stage,
      );

  final JobTracking _row;
  final StreamController<Position> _positions =
      StreamController<Position>.broadcast();

  @override
  Future<JobTracking> start(String jobId, {TrackingStage? stage}) async => _row;

  @override
  Future<ReturnMethod?> returnChoice(String jobId) async =>
      ReturnMethod.delivery;

  @override
  Future<LocationReadiness> prepareLocation() async =>
      const LocationReadiness.ready();

  @override
  Stream<Position> positionStream() => _positions.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
