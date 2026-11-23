import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/features/onboarding/models/travel_conditions.dart';
import 'package:sugo_app/features/profile/models/client_booking_stats.dart';
import 'package:sugo_app/features/rb_cars/models/job.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';
import 'package:sugo_app/features/rb_cars/models/technician_profile_details.dart';
import 'package:sugo_app/features/rb_cars/widgets/how_they_work_card.dart';

/// Two asks from 2026-11-23: a client's "In progress" counts only Home
/// Service and Shop Repair jobs, and a technician's profile says how they
/// work - what they take, and whether they come in rain or heavy traffic.
void main() {
  Job job(String id, ServicePath? path, JobStatus status) => Job(
    id: id,
    clientId: 'c',
    deviceType: DeviceType.laptop,
    problemSymptom: 'laptop_overheating',
    hasPhysicalDamage: false,
    status: status,
    servicePath: path,
  );

  group('ClientBookingStats', () {
    test('community questions and cancelled requests do not count', () {
      final ClientBookingStats stats = ClientBookingStats.from(<Job>[
        job('1', ServicePath.homeService, JobStatus.matched),
        job('2', ServicePath.pickup, JobStatus.inProgress),
        job('3', ServicePath.homeService, JobStatus.confirmed),
        job('4', ServicePath.pickup, JobStatus.completed),
        // Not counted:
        job('5', ServicePath.itCommunity, JobStatus.pending),
        job('6', ServicePath.itCommunity, JobStatus.completed),
        job('7', ServicePath.homeService, JobStatus.cancelled),
        job('8', null, JobStatus.pending),
      ]);

      expect(stats.active, 3, reason: 'In progress: open service jobs only');
      expect(stats.completed, 1);
      expect(stats.total, 4, reason: 'Bookings = completed + in progress');
    });

    test('a request still waiting for a technician is in progress', () {
      final ClientBookingStats stats = ClientBookingStats.from(<Job>[
        job('1', ServicePath.homeService, JobStatus.pending),
      ]);
      expect(stats.active, 1);
    });

    test('no jobs reads as zero, not a dash', () {
      final ClientBookingStats stats = ClientBookingStats.from(const <Job>[]);
      expect(stats.total, 0);
      expect(stats.active, 0);
    });
  });

  group('HowTheyWork', () {
    test('reads the four fields the profile RPC returns', () {
      final HowTheyWork? how = HowTheyWork.fromJson(<String, dynamic>{
        'offers_home_service': true,
        'offers_shop_repair': false,
        'rain_travel': 'not_heavy',
        'heavy_traffic_travel': false,
      });
      expect(how, isNotNull);
      expect(how!.homeService, isTrue);
      expect(how.shopRepair, isFalse);
      expect(how.rain, RainTravel.notHeavy);
      expect(how.traffic, TrafficTravel.avoids);
    });

    test('a server without the fields gives null, so the card is left out', () {
      expect(HowTheyWork.fromJson(<String, dynamic>{'id': 't1'}), isNull);
    });

    testWidgets('the card says what they take and how they travel', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HowTheyWorkCard(
              how: HowTheyWork(
                homeService: true,
                shopRepair: true,
                rain: RainTravel.any,
              ),
            ),
          ),
        ),
      );

      expect(find.text('How they work'), findsOneWidget);
      expect(find.text('Home & shop'), findsOneWidget);
      expect(find.text('Even in heavy rain'), findsOneWidget);
      // Never answered: said so, not guessed.
      expect(find.text('Not answered'), findsOneWidget);
    });

    testWidgets('fits a small phone at large text', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(640, 1000);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(320, 500),
              textScaler: TextScaler.linear(1.3),
            ),
            child: Scaffold(
              body: Padding(
                padding: EdgeInsets.all(16),
                child: HowTheyWorkCard(
                  how: HowTheyWork(
                    rain: RainTravel.never,
                    traffic: TrafficTravel.goes,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Goes in heavy traffic'), findsOneWidget);
    });
  });
}
