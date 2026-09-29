import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/rb_cars/models/job.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';
import 'package:sugo_app/features/rb_cars/models/match_result.dart';
import 'package:sugo_app/features/rb_cars/screens/client_review_screen.dart';
import 'package:sugo_app/features/rb_cars/services/rb_cars_service.dart';
import 'package:sugo_app/features/rb_cars/widgets/technician_matching_loader.dart';

/// When the analysis screen appears on the results screen, and where.
///
/// Two regressions the user reported on 2026-09-28:
///
/// * Opening a job from the dashboard ("Choose technician") showed the
///   analysis animation again, though nothing was being analysed - the
///   results already existed and were only being read back.
/// * The animation sat against the left edge instead of the centre. It looked
///   centred in the golden, whose panes hand down tight constraints; a real
///   Scaffold body hands down loose ones.
void main() {
  Future<void> pumpFrames(WidgetTester tester, int count) async {
    for (int i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('opening a job with results reads them without the animation', (
    WidgetTester tester,
  ) async {
    final _GatedService service = _GatedService();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ClientReviewScreen(jobId: _job.id, service: service),
      ),
    );
    await pumpFrames(tester, 3);

    // Still reading: a skeleton, never the analysis screen.
    expect(find.byType(TechnicianMatchingLoader), findsNothing);
    expect(find.text('Choose a technician'), findsOneWidget);

    service.matches.complete(const <MatchResult>[]);
    await pumpFrames(tester, 5);
    expect(find.byType(TechnicianMatchingLoader), findsNothing);
  });

  testWidgets('searching again does show it, and hands back when done', (
    WidgetTester tester,
  ) async {
    final _GatedService service = _GatedService();
    service.matches.complete(const <MatchResult>[]);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ClientReviewScreen(jobId: _job.id, service: service),
      ),
    );
    await pumpFrames(tester, 3);

    // Nobody matched yet, so the empty state offers a real re-match.
    await tester.tap(find.text('Search again'));
    await pumpFrames(tester, 5);
    expect(find.byType(TechnicianMatchingLoader), findsOneWidget);

    service.run.complete(const MatchingRun(message: 'Nobody nearby.'));
    await pumpFrames(tester, 15);
    expect(find.byType(TechnicianMatchingLoader), findsNothing);
  });

  testWidgets('the analysis screen is centred on a real Scaffold', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: MatchingLoaderScaffold(loader: TechnicianMatchingLoader()),
      ),
    );
    await pumpFrames(tester, 3);

    final double screenCentre = tester.view.physicalSize.width / 2 / 2;
    final Offset title = tester.getCenter(
      find.text('Analyzing your request...'),
    );
    expect(title.dx, moreOrLessEquals(screenCentre, epsilon: 1));

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

const Job _job = Job(
  id: 'job-1',
  clientId: 'client-1',
  deviceType: DeviceType.laptop,
  problemSymptom: 'laptop_wont_power_on',
  hasPhysicalDamage: false,
  status: JobStatus.matched,
);

/// Reads and matches only when the test says so.
class _GatedService implements RbCarsService {
  final Completer<List<MatchResult>> matches = Completer<List<MatchResult>>();
  final Completer<MatchingRun> run = Completer<MatchingRun>();

  @override
  Future<Job?> jobById(String jobId) async => _job;

  @override
  Future<List<MatchResult>> fetchMatches(String jobId) => matches.future;

  @override
  Future<MatchingRun> runMatching(
    String jobId, {
    List<String> excludeTechnicianIds = const <String>[],
  }) => run.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
