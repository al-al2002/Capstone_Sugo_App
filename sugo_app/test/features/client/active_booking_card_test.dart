import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/core/widgets/sugo_route_line.dart';
import 'package:sugo_app/features/bookings/models/booking_route.dart';
import 'package:sugo_app/features/client/widgets/active_booking_card.dart';
import 'package:sugo_app/features/rb_cars/models/job.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';
import 'package:sugo_app/features/rb_cars/models/job_technician.dart';

/// The home screen's booking card in the Dispatch redesign: the booking drawn
/// as a route, and the plane only ever where the data puts it.
void main() {
  const Job job = Job(
    id: 'a3f2b1c4-0000-0000-0000-000000000001',
    clientId: 'client-1',
    deviceType: DeviceType.laptop,
    problemSymptom: 'laptop_wont_power_on',
    hasPhysicalDamage: false,
    status: JobStatus.confirmed,
    assignedTechnicianId: 'tech-1',
  );

  const JobTechnician ryan = JobTechnician(
    jobId: 'a3f2b1c4-0000-0000-0000-000000000001',
    matchId: 'm1',
    technicianId: 'tech-1',
    status: MatchStatus.accepted,
    fullName: 'Ryan Santos',
  );

  Widget host(Widget child, {double width = 390, double scale = 1}) {
    return MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 900),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: child,
          ),
        ),
      ),
    );
  }

  test('every dashboard state maps to one fixed place on the route', () {
    expect(ActiveBookingState.finding.routePosition, BookingRoute.finding);
    expect(ActiveBookingState.choosing.routePosition, BookingRoute.choosing);
    expect(ActiveBookingState.awaiting.routePosition, BookingRoute.awaiting);
    expect(ActiveBookingState.confirmed.routePosition, BookingRoute.booked);
    expect(ActiveBookingState.travelling.routePosition, BookingRoute.underway);
    expect(ActiveBookingState.inProgress.routePosition, BookingRoute.underway);
  });

  test('a status read from the jobs row lands on the same stops', () {
    expect(BookingRoute.forStatus(JobStatus.pending), BookingRoute.finding);
    expect(BookingRoute.forStatus(JobStatus.matched), BookingRoute.choosing);
    expect(
      BookingRoute.forStatus(JobStatus.matched, offerPending: true),
      BookingRoute.awaiting,
    );
    expect(BookingRoute.forStatus(JobStatus.confirmed), BookingRoute.booked);
    expect(BookingRoute.forStatus(JobStatus.completed), BookingRoute.fixed);
    // A cancelled job is not on its way anywhere.
    expect(BookingRoute.forStatus(JobStatus.cancelled), isNull);
  });

  testWidgets('a confirmed booking sits at "Booked", with its technician', (
    WidgetTester tester,
  ) async {
    int opened = 0;
    int messaged = 0;
    await tester.pumpWidget(
      host(
        ActiveBookingCard(
          job: job,
          state: ActiveBookingState.confirmed,
          technician: ryan,
          onPrimary: () => opened++,
          onMessage: () => messaged++,
        ),
      ),
    );

    final SugoRouteLine route = tester.widget<SugoRouteLine>(
      find.byType(SugoRouteLine),
    );
    expect(route.stops, BookingRoute.stops);
    expect(route.position, BookingRoute.booked);
    expect(find.text('Your booking'), findsOneWidget);
    expect(find.text('Ryan Santos'), findsOneWidget);

    await tester.tap(find.text('View booking'));
    await tester.tap(find.text('Message'));
    await tester.pump();
    expect(opened, 1);
    expect(messaged, 1);
  });

  testWidgets('no Message button before anyone has accepted', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        ActiveBookingCard(
          job: const Job(
            id: 'd571224a-0000-0000-0000-000000000002',
            clientId: 'client-1',
            deviceType: DeviceType.laptop,
            problemSymptom: 'laptop_wont_power_on',
            hasPhysicalDamage: false,
            status: JobStatus.matched,
          ),
          state: ActiveBookingState.choosing,
          onPrimary: () {},
          onCancel: () {},
        ),
      ),
    );
    expect(find.text('Choose technician'), findsOneWidget);
    expect(find.text('Message'), findsNothing);
    expect(find.text('Delete request'), findsOneWidget);
  });

  testWidgets('fits a 320dp phone at 1.3x text', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      host(
        ActiveBookingCard(
          job: job,
          state: ActiveBookingState.confirmed,
          technician: ryan,
          onPrimary: () {},
          onMessage: () {},
          onCancel: () {},
          moreCount: 2,
          onSeeAll: () {},
        ),
        width: 320,
        scale: 1.3,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
