import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/rb_cars/models/job.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';
import 'package:sugo_app/features/rb_cars/models/match_result.dart';
import 'package:sugo_app/features/technician/widgets/active_job_card.dart';
import 'package:sugo_app/features/technician/widgets/incoming_offer_card.dart';
import 'package:sugo_app/features/technician/widgets/technician_job_actions.dart';

/// "Accept" and "Mark as complete" show that they are working (2026-09-29).
///
/// Both call the server and can take a few seconds - accepting runs the whole
/// decline cascade, completing feeds the outcome back to RB-CARS. They used to
/// just go grey, which looks like a tap that did not register.
void main() {
  final MatchResult offer = MatchResult.fromJson(<String, dynamic>{
    'id': 'match-1',
    'job_id': 'job-1',
    'technician_id': 'tech-1',
    'rank': 1,
    'status': 'offered',
    'score_breakdown': <String, dynamic>{
      'job': <String, dynamic>{
        'id': 'job-1',
        'device_type': 'laptop',
        'problem_symptom': 'no_power',
        'has_physical_damage': false,
        'service_path': 'home_service',
      },
    },
  });

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

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    ),
  );

  IncomingOfferCard offerCard({
    required bool busy,
    required bool accepting,
    VoidCallback? onAccept,
  }) => IncomingOfferCard(
    match: offer,
    isBusy: busy,
    isAccepting: accepting,
    onAccept: onAccept ?? () {},
    onDecline: () {},
    onViewDetails: () {},
    onMessage: () {},
  );

  group('Accept', () {
    testWidgets('the offer being accepted says so, and cannot be sent twice', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await tester.pumpWidget(
        host(offerCard(busy: true, accepting: true, onAccept: () => taps++)),
      );
      await tester.pump();

      expect(find.text('Accepting…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Accept'), findsNothing);

      await tester.tap(find.text('Accepting…'), warnIfMissed: false);
      expect(taps, 0);
    });

    testWidgets('another offer, while one is being accepted, only disables', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(host(offerCard(busy: true, accepting: false)));
      await tester.pump();

      expect(find.text('Accept'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    // Since 2026-11-17 Accept asks "Ready to take this job?" first, the same
    // as View task, so the accept itself is sent from the dialog.
    testWidgets('at rest, it is just "Accept", confirmed in the dialog', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await tester.pumpWidget(
        host(offerCard(busy: false, accepting: false, onAccept: () => taps++)),
      );

      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      expect(find.text('Ready to take this job?'), findsOneWidget);
      expect(taps, 0);

      await tester.tap(find.text('Accept job'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });
  });

  group('the dashboard card', () {
    testWidgets('is a summary with one way in: "View job"', (
      WidgetTester tester,
    ) async {
      // The user's ask (2026-09-29): one button on the dashboard, the rest
      // on the job's own screen.
      int views = 0;
      await tester.pumpWidget(
        host(ActiveJobCard(job: job, onView: () => views++)),
      );

      expect(find.text('View job'), findsOneWidget);
      expect(find.text('Mark as complete'), findsNothing);
      expect(find.text('Trip to the client'), findsNothing);
      expect(find.textContaining('take to shop'), findsNothing);

      await tester.tap(find.text('View job'));
      expect(views, 1);
    });
  });

  group("the job's own screen", () {
    // No pinned address on `job`, so no network map in these tests.
    TechnicianJobActions actions({
      Job? on,
      bool completing = false,
      bool moving = false,
      double? distanceKm,
      VoidCallback? onTrip,
    }) => TechnicianJobActions(
      job: on ?? job,
      onTrip: onTrip ?? () {},
      onComplete: () {},
      onNeedsShop: () {},
      isCompleting: completing,
      isMovingToShop: moving,
      distanceKm: distanceKm,
    );

    testWidgets('has everything the card used to', (WidgetTester tester) async {
      await tester.pumpWidget(host(actions()));

      expect(find.text('Trip to the client'), findsOneWidget);
      expect(find.text('Mark as complete'), findsOneWidget);
      expect(find.text('Take it to your shop'), findsOneWidget);
    });

    testWidgets('has no "Show route" - "Trip to the client" is the route', (
      WidgetTester tester,
    ) async {
      // The user's ask (2026-11-16): the map's own "Show route" button
      // duplicated the trip, which already shows the route.
      const Job located = Job(
        id: 'job-1',
        clientId: 'client-1',
        deviceType: DeviceType.laptop,
        problemSymptom: 'laptop_wont_power_on',
        hasPhysicalDamage: false,
        status: JobStatus.confirmed,
        assignedTechnicianId: 'tech-1',
        servicePath: ServicePath.homeService,
        latitude: 7.07,
        longitude: 125.61,
        addressText: 'Purok 3, Toril, Davao City',
      );
      await tester.pumpWidget(host(actions(on: located, distanceKm: 4.2)));
      await tester.pump();

      expect(find.text('Show route'), findsNothing);
      expect(find.text('Client address'), findsOneWidget);
      expect(find.text('Purok 3, Toril, Davao City'), findsOneWidget);
      expect(find.text('4.2 km'), findsOneWidget);
      expect(find.text('Trip to the client'), findsOneWidget);
    });

    testWidgets('a drop-off job names itself and has no shop switch', (
      WidgetTester tester,
    ) async {
      const Job dropOff = Job(
        id: 'job-2',
        clientId: 'client-1',
        deviceType: DeviceType.laptop,
        problemSymptom: 'laptop_wont_power_on',
        hasPhysicalDamage: false,
        status: JobStatus.confirmed,
        assignedTechnicianId: 'tech-1',
        servicePath: ServicePath.pickup,
        deliveryOption: DeliveryOption.self,
      );
      await tester.pumpWidget(host(actions(on: dropOff)));

      expect(find.textContaining('Drop-off ·'), findsOneWidget);
      expect(find.text('Drop-off and collection'), findsOneWidget);
      expect(find.text('Take it to your shop'), findsNothing);
    });

    testWidgets('fits a small phone with large text', (
      WidgetTester tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 1200);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 1200),
            textScaler: TextScaler.linear(1.4),
          ),
          child: host(actions(distanceKm: 12.6)),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows it is completing while the outcome is saved', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(host(actions(completing: true)));
      await tester.pump();

      expect(find.text('Completing…'), findsOneWidget);
      expect(find.text('Mark as complete'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('the trip cannot be opened while it completes', (
      WidgetTester tester,
    ) async {
      int trips = 0;
      await tester.pumpWidget(
        host(actions(completing: true, onTrip: () => trips++)),
      );
      await tester.pump();

      await tester.tap(find.text('Trip to the client'), warnIfMissed: false);
      expect(trips, 0);
    });

    testWidgets('and while it switches to the shop', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(host(actions(moving: true)));
      await tester.pump();

      expect(find.text('Switching…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
