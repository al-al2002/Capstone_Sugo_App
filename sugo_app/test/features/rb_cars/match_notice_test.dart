import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/features/rb_cars/models/device_category.dart';
import 'package:sugo_app/features/rb_cars/models/job.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';
import 'package:sugo_app/features/rb_cars/models/match_result.dart';
import 'package:sugo_app/features/rb_cars/providers/job_posting_provider.dart';
import 'package:sugo_app/features/rb_cars/providers/match_provider.dart';
import 'package:sugo_app/features/rb_cars/services/rb_cars_service.dart';

/// When the matcher finds nobody it says which gate emptied the pool. That
/// sentence has to reach the client.
///
/// It nearly does not: the matching run happens inside the posting flow, and
/// the review screen then re-reads `job_matches` straight from the database -
/// where a message that only ever existed in the matching *response* cannot be
/// found. Without the hand-off tested here the client is told "nobody verified
/// is available", which can be flatly untrue: the real pool had a verified,
/// available technician who simply lives outside his own service radius.
void main() {
  const String reason =
      'No technician covers this location. 1 was outside their own '
      'service radius.';

  JobPostingProvider readyDraft(RbCarsService service) {
    final JobPostingProvider posting = JobPostingProvider(service: service);
    posting.selectCategory(DeviceCategory.laptop);
    posting.selectSymptom('laptop_wont_power_on');
    posting.setLocation(latitude: 7.0731, longitude: 125.6128);
    return posting;
  }

  group('the posting flow keeps the reason', () {
    test('an empty run is remembered with its explanation', () async {
      final JobPostingProvider posting = readyDraft(
        _StubService(const MatchingRun(message: reason)),
      );
      addTearDown(posting.dispose);

      expect(posting.matchingNotice, isNull, reason: 'Nothing has run yet.');

      await posting.submit();

      expect(posting.matchingNotice, reason);
    });

    test('a run that found someone leaves no notice to show', () async {
      final JobPostingProvider posting = readyDraft(
        _StubService(
          MatchingRun(
            matches: <MatchResult>[_match],
            // A message can accompany a successful run; it must not be
            // mistaken for an explanation of an empty one.
            message: 'Found 1, scored 4.',
          ),
        ),
      );
      addTearDown(posting.dispose);

      await posting.submit();

      expect(posting.matchingNotice, isNull);
    });

    test('an engine that says nothing leaves nothing', () async {
      final JobPostingProvider posting = readyDraft(
        _StubService(const MatchingRun()),
      );
      addTearDown(posting.dispose);

      await posting.submit();

      expect(posting.matchingNotice, isNull);
    });
  });

  group('the review screen shows it', () {
    test('an initial notice survives the load that follows', () async {
      final MatchProvider matching = MatchProvider(
        jobId: 'job-1',
        service: _StubService(const MatchingRun()),
        initialNotice: reason,
      );
      addTearDown(matching.dispose);

      await matching.load();

      expect(matching.isEmpty, isTrue);
      expect(
        matching.notice,
        reason,
        reason:
            'load() re-reads job_matches and finds nothing, which is exactly '
            'when the reason matters. It must not be cleared on the way.',
      );
    });

    test('with no notice the screen falls back to its own wording', () async {
      final MatchProvider matching = MatchProvider(
        jobId: 'job-1',
        service: _StubService(const MatchingRun()),
      );
      addTearDown(matching.dispose);

      await matching.load();

      expect(matching.notice, isNull);
    });
  });
}

/// Built through the JSON factory rather than the constructor: the breakdown
/// is four nested objects deep, and none of it matters here - the provider
/// only asks whether the run came back with any matches at all.
final MatchResult _match = MatchResult.fromJson(<String, dynamic>{
  'id': 'm1',
  'job_id': 'job-1',
  'technician_id': 't1',
  'rank': 1,
  'status': 'offered',
});

const Job _job = Job(
  id: 'job-1',
  clientId: 'client-1',
  deviceType: DeviceType.laptop,
  problemSymptom: 'laptop_wont_power_on',
  hasPhysicalDamage: false,
  status: JobStatus.pending,
);

/// Posts instantly and returns whatever matching run the test hands it.
class _StubService implements RbCarsService {
  _StubService(this.run);

  final MatchingRun run;

  @override
  Future<Job> postJob(JobDraft draft) async => _job;

  @override
  Future<List<String>> uploadPhotos(List<XFile> files) async => <String>[];

  @override
  Future<MatchingRun> runMatching(
    String jobId, {
    List<String> excludeTechnicianIds = const <String>[],
  }) async => run;

  @override
  Future<Job?> jobById(String jobId) async => _job;

  @override
  Future<List<MatchResult>> fetchMatches(String jobId) async =>
      const <MatchResult>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
