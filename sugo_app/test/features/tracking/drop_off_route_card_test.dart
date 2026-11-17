import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/bookings/screens/bookings_list_view.dart';
import 'package:sugo_app/features/bookings/screens/job_detail_screen.dart';
import 'package:sugo_app/features/client/widgets/active_booking_card.dart';
import 'package:sugo_app/features/disputes/models/job_dispute.dart';
import 'package:sugo_app/features/disputes/services/dispute_service.dart';
import 'package:sugo_app/features/rb_cars/models/job.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';
import 'package:sugo_app/features/rb_cars/models/job_party.dart';
import 'package:sugo_app/features/rb_cars/models/match_result.dart';
import 'package:sugo_app/features/rb_cars/models/technician.dart';
import 'package:sugo_app/features/rb_cars/models/technician_profile_details.dart';
import 'package:sugo_app/features/rb_cars/services/rb_cars_service.dart';
import 'package:sugo_app/features/rb_cars/services/technician_directory_service.dart';
import 'package:sugo_app/features/tracking/models/job_tracking.dart';
import 'package:sugo_app/features/tracking/models/route_result.dart';
import 'package:sugo_app/features/tracking/services/tracking_service.dart';
import 'package:sugo_app/features/tracking/widgets/drop_off_route_card.dart';

/// "Bring it to the shop" (2026-11-17): a Shop Repair the client drops off
/// themselves gets the road to the technician's shop once the technician
/// accepts - on the job page, and on the home screen's booking card.
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

  void phone(WidgetTester tester, {Size size = const Size(320, 1400)}) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
  }

  Widget host(Widget child, {double scale = 1.3}) => MaterialApp(
    theme: AppTheme.light,
    home: Builder(
      builder: (BuildContext context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    ),
  );

  group('the route card', () {
    testWidgets('with location already allowed, the road is drawn at once', (
      WidgetTester tester,
    ) async {
      phone(tester);
      final _FakeTracking tracking = _FakeTracking(allowed: true);
      await tester.pumpWidget(
        host(
          DropOffRouteCard(
            jobId: 'job-1',
            technicianId: 'tech-1',
            directory: _FakeDirectory(),
            tracking: tracking,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bring it to the shop'), findsOneWidget);
      expect(find.text('Santos Repair Hub'), findsOneWidget);
      // Distance and time, from the road - not a straight line.
      expect(find.text('3.4 km'), findsOneWidget);
      expect(find.text('12 min away'), findsOneWidget);
      expect(find.text('Route drawn from where you are now.'), findsOneWidget);
      expect(find.text('Start route'), findsOneWidget);
      expect(find.text('Open in maps'), findsOneWidget);
      // Asked the server for the road from the client's position, without
      // ever showing a permission prompt.
      expect(tracking.routeCalls, 1);
      expect(tracking.prompts, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('without permission it waits for a tap before asking', (
      WidgetTester tester,
    ) async {
      phone(tester);
      final _FakeTracking tracking = _FakeTracking(allowed: false);
      await tester.pumpWidget(
        host(
          DropOffRouteCard(
            jobId: 'job-1',
            technicianId: 'tech-1',
            directory: _FakeDirectory(),
            tracking: tracking,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The shop is there; the route is offered, not forced.
      expect(find.text('Santos Repair Hub'), findsOneWidget);
      expect(find.text('Show my route'), findsOneWidget);
      expect(find.text('Start route'), findsNothing);
      expect(tracking.prompts, 0);
      expect(tracking.routeCalls, 0);

      await tester.tap(find.text('Show my route'));
      await tester.pumpAndSettle();

      expect(tracking.prompts, 1);
      expect(tracking.routeCalls, 1);
      expect(find.text('Start route'), findsOneWidget);
      expect(find.text('3.4 km'), findsOneWidget);
    });

    testWidgets('a refused permission says why, and offers settings', (
      WidgetTester tester,
    ) async {
      phone(tester);
      final _FakeTracking tracking = _FakeTracking(
        allowed: false,
        readiness: const LocationReadiness.blocked(
          'Location is blocked for SUGO. Allow it in the app settings to '
          'share your position.',
          fix: LocationFix.appSettings,
        ),
      );
      await tester.pumpWidget(
        host(
          DropOffRouteCard(
            jobId: 'job-1',
            technicianId: 'tech-1',
            directory: _FakeDirectory(),
            tracking: tracking,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show my route'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Location is blocked for SUGO'),
        findsOneWidget,
      );
      expect(find.text('Open settings'), findsOneWidget);
      expect(tracking.routeCalls, 0);
    });

    testWidgets('a shop with no pin says to message the technician', (
      WidgetTester tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(
        host(
          DropOffRouteCard(
            jobId: 'job-1',
            technicianId: 'tech-1',
            directory: _FakeDirectory(pinned: false),
            tracking: _FakeTracking(allowed: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('The shop has no pin on the map yet'),
        findsOneWidget,
      );
      expect(find.text('Open in maps'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits a small phone at large text, route drawn', (
      WidgetTester tester,
    ) async {
      phone(tester, size: const Size(320, 2000));
      await tester.pumpWidget(
        host(
          DropOffRouteCard(
            jobId: 'job-1',
            technicianId: 'tech-1',
            directory: _FakeDirectory(),
            tracking: _FakeTracking(allowed: true, trafficDelay: 240),
          ),
          scale: 1.5,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('+4 min traffic'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // The entrance and the band's growing pills play once and stop - nothing
  // here loops, so a full-motion screen settles.
  testWidgets('settles at full motion', (WidgetTester tester) async {
    phone(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: DropOffRouteCard(
              jobId: 'job-1',
              technicianId: 'tech-1',
              directory: _FakeDirectory(),
              tracking: _FakeTracking(allowed: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('3.4 km'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('the job page', () {
    Future<void> open(
      WidgetTester tester,
      Job job,
      BookingsRole role, {
      JobTracking? row,
    }) async {
      phone(tester, size: const Size(320, 2400));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 2400),
              disableAnimations: true,
            ),
            child: JobDetailScreen(
              job: job,
              role: role,
              service: _FakeJobs(job),
              tracking: _FakeTracking(allowed: false, row: row),
              disputes: _FakeDisputes(),
              directory: _FakeDirectory(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('an accepted drop-off shows the way to the shop', (
      WidgetTester tester,
    ) async {
      await open(tester, dropOff, BookingsRole.client);

      expect(find.byType(DropOffRouteCard), findsOneWidget);
      expect(find.text('Santos Repair Hub'), findsOneWidget);
      // Not the promise of a pickup trip that never happens on this job,
      // and no "Track" button leading to the same card.
      expect(
        find.textContaining('Tracking opens once your technician sets off'),
        findsNothing,
      );
      expect(find.text('Track'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a delivery job keeps its tracking card', (
      WidgetTester tester,
    ) async {
      const Job delivery = Job(
        id: 'job-1',
        clientId: 'client-1',
        deviceType: DeviceType.laptop,
        problemSymptom: 'laptop_screen_broken',
        hasPhysicalDamage: true,
        status: JobStatus.confirmed,
        servicePath: ServicePath.pickup,
        deliveryOption: DeliveryOption.delivery,
        assignedTechnicianId: 'tech-1',
      );
      await open(tester, delivery, BookingsRole.client);

      expect(find.byType(DropOffRouteCard), findsNothing);
      expect(
        find.textContaining('Tracking opens once your technician sets off'),
        findsOneWidget,
      );
    });

    // 2026-11-17: "I'll bring it" covers the way back too. Once the unit is
    // on the bench, the client is told they collect it - never asked
    // "deliver it to me, or pick it up?".
    testWidgets('on the bench, a drop-off is not asked how it comes back', (
      WidgetTester tester,
    ) async {
      await open(
        tester,
        const Job(
          id: 'job-1',
          clientId: 'client-1',
          deviceType: DeviceType.laptop,
          problemSymptom: 'laptop_screen_broken',
          hasPhysicalDamage: true,
          status: JobStatus.inProgress,
          servicePath: ServicePath.pickup,
          deliveryOption: DeliveryOption.self,
          assignedTechnicianId: 'tech-1',
        ),
        BookingsRole.client,
        row: const JobTracking(
          id: 'track-1',
          jobId: 'job-1',
          technicianId: 'tech-1',
          stage: TrackingStage.inRepair,
        ),
      );

      expect(find.text('How do you want it back?'), findsNothing);
      expect(find.text('Deliver it to me'), findsNothing);
      expect(find.text("You'll collect it at the shop"), findsOneWidget);
      expect(find.text('Drop-off and collection'), findsOneWidget);
      expect(find.text('Delivery'), findsNothing);
      expect(find.text('Repair progress'), findsOneWidget);
      expect(find.text('Track your appliance'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the technician never gets the client\'s route card', (
      WidgetTester tester,
    ) async {
      await open(tester, dropOff, BookingsRole.technician);
      expect(find.byType(DropOffRouteCard), findsNothing);
    });
  });

  testWidgets('the home card says the next move is the client\'s', (
    WidgetTester tester,
  ) async {
    phone(tester, size: const Size(390, 1200));
    int opened = 0;
    await tester.pumpWidget(
      host(
        ActiveBookingCard(
          job: dropOff,
          state: ActiveBookingState.confirmed,
          onPrimary: () => opened++,
        ),
        scale: 1,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bring it to the shop'), findsOneWidget);
    expect(find.text('Route to the shop'), findsOneWidget);
    await tester.tap(find.text('Route to the shop'));
    expect(opened, 1);
  });
}

class _FakeDirectory implements TechnicianDirectoryService {
  _FakeDirectory({this.pinned = true});

  final bool pinned;

  @override
  Future<TechnicianProfileDetails> profile(
    String technicianId, {
    double? latitude,
    double? longitude,
    int reviewLimit = 20,
  }) async => TechnicianProfileDetails(
    technician: const Technician(id: 'tech-1', fullName: 'Ryan Santos'),
    contactUnlocked: true,
    shopName: 'Santos Repair Hub',
    shopLatitude: pinned ? 7.0731 : null,
    shopLongitude: pinned ? 125.6128 : null,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTracking implements TrackingService {
  _FakeTracking({
    required this.allowed,
    this.readiness = const LocationReadiness.ready(),
    this.trafficDelay = 0,
    this.row,
  });

  final bool allowed;
  final LocationReadiness readiness;
  final double trafficDelay;

  /// The job's tracking row, when the test needs one (e.g. on the bench).
  final JobTracking? row;

  int prompts = 0;
  int routeCalls = 0;

  @override
  Stream<JobTracking?> watch(String jobId) => Stream<JobTracking?>.value(row);

  @override
  Future<ReturnMethod> returnMethod(String jobId) async =>
      ReturnMethod.clientPickup;

  @override
  Future<bool> locationAllowed() async => allowed;

  @override
  Future<LocationReadiness> prepareLocation() async {
    prompts++;
    return readiness;
  }

  @override
  Future<Position?> currentPosition() async => Position(
    latitude: 7.0650,
    longitude: 125.6000,
    timestamp: DateTime(2026, 11, 17, 15),
    accuracy: 8,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  @override
  Future<RouteResult> routeFor(
    String jobId, {
    required double originLatitude,
    required double originLongitude,
  }) async {
    routeCalls++;
    return RouteResult(
      available: true,
      points: <LatLng>[
        LatLng(originLatitude, originLongitude),
        const LatLng(7.0690, 125.6060),
        const LatLng(7.0731, 125.6128),
      ],
      distanceMeters: 3400,
      travelSeconds: 720,
      trafficDelaySeconds: trafficDelay,
      destination: const LatLng(7.0731, 125.6128),
      destinationLabel: 'Workshop',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeJobs implements RbCarsService {
  _FakeJobs(this.job);

  final Job job;

  @override
  Future<Job?> jobById(String jobId) async => job;

  @override
  Future<Map<String, JobParty>> jobParties() async =>
      const <String, JobParty>{};

  @override
  Future<String?> clientPhone(String jobId) async => null;

  @override
  Future<List<MatchResult>> fetchMatches(String jobId) async =>
      const <MatchResult>[];

  @override
  Future<TechnicianReview?> myReview(String jobId) async => null;

  @override
  Future<TechnicianReview?> myClientReview(String jobId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDisputes implements DisputeService {
  @override
  Future<List<JobDispute>> forJob(String jobId) async => const <JobDispute>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
