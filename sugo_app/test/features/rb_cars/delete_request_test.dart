import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/rb_cars/models/job.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';
import 'package:sugo_app/features/rb_cars/models/match_result.dart';
import 'package:sugo_app/features/rb_cars/screens/client_review_screen.dart';
import 'package:sugo_app/features/rb_cars/services/rb_cars_service.dart';

/// "Delete request" on "Choose a technician", beside "Edit post"
/// (2026-09-29): a client who has not booked anyone can drop the whole thing
/// from where they are, and land back home.
void main() {
  Future<void> pumpFrames(WidgetTester tester, int count) async {
    for (int i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('deletes after asking, under the bin, and goes home', (
    WidgetTester tester,
  ) async {
    final _FakeService service = _FakeService();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ClientReviewScreen(jobId: _job.id, service: service),
                  ),
                ),
                child: const Text('Home'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Home'));
    await pumpFrames(tester, 8);

    expect(find.text('Edit post'), findsOneWidget);
    await tester.tap(find.text('Delete request'));
    await pumpFrames(tester, 5);

    // Asked first - it cannot be undone.
    expect(find.text('Delete this request?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await pumpFrames(tester, 30);

    expect(service.deleted, <String>[_job.id]);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Choose a technician'), findsNothing);
  });

  testWidgets('keeping it deletes nothing', (WidgetTester tester) async {
    final _FakeService service = _FakeService();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ClientReviewScreen(jobId: _job.id, service: service),
      ),
    );
    await pumpFrames(tester, 8);

    await tester.tap(find.text('Delete request'));
    await pumpFrames(tester, 5);
    await tester.tap(find.text('Keep it'));
    await pumpFrames(tester, 5);

    expect(service.deleted, isEmpty);
    expect(find.text('Choose a technician'), findsOneWidget);
  });
}

/// Nobody has taken it: deletable.
const Job _job = Job(
  id: 'job-1',
  clientId: 'client-1',
  deviceType: DeviceType.laptop,
  problemSymptom: 'laptop_wont_power_on',
  hasPhysicalDamage: false,
  status: JobStatus.matched,
);

class _FakeService implements RbCarsService {
  final List<String> deleted = <String>[];

  @override
  Future<Job?> jobById(String jobId) async => _job;

  @override
  Future<List<MatchResult>> fetchMatches(String jobId) async =>
      const <MatchResult>[];

  @override
  Future<JobResponseOutcome> deleteJob(String jobId) async {
    deleted.add(jobId);
    return const JobResponseOutcome();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
