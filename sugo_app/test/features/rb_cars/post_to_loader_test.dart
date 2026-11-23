import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/rb_cars/models/device_category.dart';
import 'package:sugo_app/features/rb_cars/models/job.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';
import 'package:sugo_app/features/rb_cars/models/match_result.dart';
import 'package:sugo_app/features/rb_cars/providers/job_posting_provider.dart';
import 'package:sugo_app/features/rb_cars/screens/review_and_post_screen.dart';
import 'package:sugo_app/features/rb_cars/services/rb_cars_service.dart';
import 'package:sugo_app/features/rb_cars/widgets/request_send_intro.dart';
import 'package:sugo_app/features/rb_cars/widgets/technician_matching_loader.dart';

/// "Find technician" must reach the matching animation on the frame it is
/// tapped, with the insert and the matcher running underneath it.
///
/// The regression this guards against is invisible in a screenshot: if the
/// screen ever goes back to awaiting `submit()` before navigating, the client
/// watches a spinner on a dead form for several seconds and then gets the
/// animation for a frame or two, after the work it depicts has finished. Only a
/// test that holds the post open can tell the two apart.
void main() {
  /// Everything the harness needs, built together so the [Completer] is
  /// created inside the test body.
  ///
  /// That placement matters. `testWidgets` runs its body under `FakeAsync`, and
  /// a Completer made in `setUp` belongs to the enclosing zone instead.
  /// Completing one of those never schedules anything the fake clock will run,
  /// so the await it gates simply hangs and the screen never moves - which
  /// looks exactly like the production bug this file exists to catch.
  ({JobPostingProvider posting, Completer<Job> gate}) harness() {
    final Completer<Job> gate = Completer<Job>();
    final JobPostingProvider posting = JobPostingProvider(
      service: _GatedService(gate),
    );
    posting.selectCategory(DeviceCategory.laptop);
    // Keep this loader test on the normal matching path. A basic issue
    // ("Very slow or freezing") suggests the technician community since
    // 2026-11-17, so this uses one that is matched.
    posting.selectSymptom('laptop_overheating');
    posting.setLocation(latitude: 7.0731, longitude: 125.6128);
    return (posting: posting, gate: gate);
  }

  Future<void> pumpReview(WidgetTester tester, JobPostingProvider posting) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ReviewAndPostScreen(posting: posting),
      ),
    );
  }

  testWidgets('the animation is on screen while the job is still posting', (
    WidgetTester tester,
  ) async {
    final ({JobPostingProvider posting, Completer<Job> gate}) h = harness();
    addTearDown(h.posting.dispose);

    await pumpReview(tester, h.posting);
    expect(find.text('Find technician'), findsOneWidget);

    await tester.tap(find.text('Find technician'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Since 2026-11-23 the first animation is the letter to the technicians
    // (RequestSendIntro); the analysis screen follows it.
    expect(
      find.byType(RequestSendIntro),
      findsOneWidget,
      reason:
          'An animation should already be running while postJob is still in '
          'flight, not after it returns.',
    );
    expect(
      h.gate.isCompleted,
      isFalse,
      reason: 'The post is deliberately still open at this point.',
    );

    // The letter plays out (2.8 s) and fades into the analysis screen - with
    // the post STILL open, so the work really is running underneath both.
    for (int i = 0; i < 34; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(RequestSendIntro), findsNothing);
    expect(find.byType(TechnicianMatchingLoader), findsOneWidget);
    expect(h.gate.isCompleted, isFalse);

    // The form is gone: this was a pushReplacement, so back does not lead to a
    // second submit of the same draft.
    //
    // Pumped past the page transition first. Since the 2026-09 redesign the
    // app uses `FadeForwardsPageTransitionsBuilder` (the Android 14
    // transition), which keeps the outgoing route mounted while it fades -
    // roughly twice as long as the old zoom transition. The loader assertion
    // above is the one that has to hold *early*; this one only has to hold
    // once the navigation has settled.
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Review & post'), findsNothing);

    // Releasing the insert moves the screen on, which is what proves the post
    // was genuinely running underneath the animation rather than not at all.
    h.gate.complete(_job);
    // The analysis screen then finishes - every step ticked, the bar filled,
    // about 0.7 s - before handing over to the results. Pumped in steps
    // because that finish is driven by frames, not by a single timer.
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Choose a technician'), findsOneWidget);
  });

  testWidgets('a failed post offers a retry rather than an empty screen', (
    WidgetTester tester,
  ) async {
    final ({JobPostingProvider posting, Completer<Job> gate}) h = harness();
    addTearDown(h.posting.dispose);

    await pumpReview(tester, h.posting);
    await tester.tap(find.text('Find technician'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    h.gate.completeError(const RbCarsFailure('The server said no.'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('The server said no.'), findsOneWidget);
    expect(find.text("Couldn't finish that"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(TechnicianMatchingLoader), findsNothing);

    // The letter is cut short rather than finishing over an error.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(RequestSendIntro), findsNothing);
  });

  // 2026-11-23: a post that hangs on a bad connection used to leave the
  // client on the analysis screen for ever.
  testWidgets(
    'a post that hangs becomes "Connection problem", and Retry brings the '
    'animation back without posting twice',
    (WidgetTester tester) async {
      final _HangingService service = _HangingService();
      final JobPostingProvider posting = JobPostingProvider(
        service: service,
        limits: const PostingTimeLimits(
          save: Duration(seconds: 5),
          matching: Duration(seconds: 5),
        ),
      );
      addTearDown(posting.dispose);
      posting.selectCategory(DeviceCategory.laptop);
      posting.selectSymptom('laptop_overheating');
      posting.setLocation(latitude: 7.0731, longitude: 125.6128);

      await pumpReview(tester, posting);
      await tester.tap(find.text('Find technician'));
      await tester.pump();

      // Past the 5 s limit: the animation is gone, the pop-up is up.
      for (int i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Connection problem'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(
        find.text("Retrying is safe - your job won't be posted twice."),
        findsOneWidget,
      );
      expect(find.byType(TechnicianMatchingLoader), findsNothing);
      expect(find.byType(RequestSendIntro), findsNothing);
      expect(service.postAttempts, 1);

      // Retry: straight back to the analysis screen, not the letter.
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Connection problem'), findsNothing);
      expect(find.byType(TechnicianMatchingLoader), findsOneWidget);
      expect(find.byType(RequestSendIntro), findsNothing);

      // The same job id both times, so a first attempt that did reach the
      // server is found again rather than saved twice.
      expect(service.postAttempts, 2);
      expect(service.requestIds.toSet().length, 1);
      expect(service.requestIds.first, isNotNull);

      // Let the second attempt time out too, so no timer is left running.
      for (int i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Connection problem'), findsOneWidget);
    },
  );

  testWidgets('no internet at all: the pop-up straight away', (
    WidgetTester tester,
  ) async {
    final ({JobPostingProvider posting, Completer<Job> gate}) h = harness();
    addTearDown(h.posting.dispose);

    await pumpReview(tester, h.posting);
    await tester.tap(find.text('Find technician'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    h.gate.completeError(
      const RbCarsFailure(RbCarsFailure.offlineMessage, offline: true),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Connection problem'), findsOneWidget);
    expect(find.text(RbCarsFailure.offlineMessage), findsOneWidget);
    expect(find.byType(RequestSendIntro), findsNothing);
  });
}

/// A connection that never answers: every post hangs. Records each attempt's
/// job id, to prove a retry re-uses it.
class _HangingService implements RbCarsService {
  int postAttempts = 0;
  final List<String?> requestIds = <String?>[];

  @override
  Future<Job> postJob(JobDraft draft) {
    postAttempts++;
    requestIds.add(draft.requestId);
    return Completer<Job>().future;
  }

  @override
  Future<List<String>> uploadPhotos(List<XFile> files) async => <String>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const Job _job = Job(
  id: 'job-1',
  clientId: 'client-1',
  deviceType: DeviceType.laptop,
  problemSymptom: 'laptop_wont_power_on',
  hasPhysicalDamage: false,
  status: JobStatus.pending,
);

/// Posts only when the test says so. Everything else is a no-op: this suite is
/// about *when* the screen changes, not about what the backend returns.
class _GatedService implements RbCarsService {
  _GatedService(this.gate);

  final Completer<Job> gate;

  @override
  Future<Job> postJob(JobDraft draft) => gate.future;

  @override
  Future<List<String>> uploadPhotos(List<XFile> files) async => <String>[];

  @override
  Future<MatchingRun> runMatching(
    String jobId, {
    List<String> excludeTechnicianIds = const <String>[],
  }) async {
    return const MatchingRun();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
