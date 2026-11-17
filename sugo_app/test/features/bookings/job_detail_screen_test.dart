import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/bookings/screens/bookings_list_view.dart';
import 'package:sugo_app/features/bookings/screens/job_detail_screen.dart';
import 'package:sugo_app/features/disputes/models/job_dispute.dart';
import 'package:sugo_app/features/disputes/services/dispute_service.dart';
import 'package:sugo_app/features/rb_cars/models/job.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';
import 'package:sugo_app/features/rb_cars/models/job_party.dart';
import 'package:sugo_app/features/rb_cars/models/match_result.dart';
import 'package:sugo_app/features/rb_cars/models/technician_profile_details.dart';
import 'package:sugo_app/features/rb_cars/services/rb_cars_service.dart';
import 'package:sugo_app/features/tracking/models/job_tracking.dart';
import 'package:sugo_app/features/tracking/services/tracking_service.dart';

/// The job detail screen, rendered offline (2026-11-17).
///
/// It could not be until its services became injectable; this pins the
/// renovated hero - a band tinted by the booking's state, carrying the same
/// headline and sentence as before - for each state, on a small phone at
/// large text. Reduced motion, because a live booking's status dot pulses.
void main() {
  Job job(JobStatus status) => Job(
    id: 'job-1',
    clientId: 'client-1',
    deviceType: DeviceType.laptop,
    problemSymptom: 'laptop_wont_power_on',
    hasPhysicalDamage: false,
    status: status,
    servicePath: ServicePath.homeService,
    assignedTechnicianId: status == JobStatus.pending ? null : 'tech-1',
  );

  Future<void> open(
    WidgetTester tester,
    JobStatus status, {
    BookingsRole role = BookingsRole.client,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 1600);
    addTearDown(tester.view.reset);

    final Job j = job(status);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 1600),
            disableAnimations: true,
            textScaler: TextScaler.linear(1.3),
          ),
          child: JobDetailScreen(
            job: j,
            role: role,
            service: _FakeJobs(j),
            tracking: _FakeTracking(),
            disputes: _FakeDisputes(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('a confirmed booking: the brand hero, its words unchanged', (
    WidgetTester tester,
  ) async {
    await open(tester, JobStatus.confirmed);

    expect(find.text('Booking confirmed'), findsOneWidget);
    expect(
      find.text('Your technician has accepted. Message them any time.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a completed booking reads as finished', (
    WidgetTester tester,
  ) async {
    await open(tester, JobStatus.completed);

    // Twice by design: the hero's headline, and the timeline's last step.
    expect(find.text('Service completed'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a cancelled booking says so, with no route line', (
    WidgetTester tester,
  ) async {
    await open(tester, JobStatus.cancelled);

    expect(find.text('Booking cancelled'), findsOneWidget);
    expect(find.text('Posted'), findsNothing); // no route stops
    expect(tester.takeException(), isNull);
  });

  // 2026-11-17: "minimal, but don't remove the widgets". The secondary
  // sections open folded to one line each, and every one is still there.
  testWidgets('the page opens with its secondary sections folded', (
    WidgetTester tester,
  ) async {
    await open(tester, JobStatus.confirmed);

    for (final String title in <String>['Progress', 'Price', 'Details']) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    // One line each while folded.
    expect(find.text('Booking accepted'), findsOneWidget); // Progress, now
    expect(find.textContaining('Laptop'), findsWidgets); // Details
    // The content is a tap away, not removed.
    expect(find.text('Physical damage'), findsNothing);
    await tester.tap(find.text('Details'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Physical damage'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the technician\'s copy is worded for them', (
    WidgetTester tester,
  ) async {
    await open(tester, JobStatus.confirmed, role: BookingsRole.technician);

    expect(
      find.text('You accepted this job. The client is expecting you.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
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

class _FakeTracking implements TrackingService {
  @override
  Stream<JobTracking?> watch(String jobId) => Stream<JobTracking?>.value(null);

  @override
  Future<ReturnMethod> returnMethod(String jobId) async =>
      ReturnMethod.delivery;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDisputes implements DisputeService {
  @override
  Future<List<JobDispute>> forJob(String jobId) async => const <JobDispute>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
