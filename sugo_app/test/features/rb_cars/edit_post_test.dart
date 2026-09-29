import 'dart:typed_data';

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

/// Posting a job once, going back from the matches, and "Edit post".
///
/// The bug this file was written for: from the matching screen, back led to
/// the map step, and pressing "Find technician" again posted the same job a
/// second time. Two fixes, both pinned here - back now goes home, and the flow
/// itself updates the job it already posted instead of inserting another.
void main() {
  group('JobDraft.restoreDescription', () {
    test('puts each answer back in its own field', () {
      final JobDraft original = JobDraft()
        ..model = 'IdeaPad 3 14"'
        ..description = 'It shuts off after a minute.\n\nFan is loud.'
        ..notes = 'Gate code 1234';

      final JobDraft restored = JobDraft()
        ..restoreDescription(original.composedDescription);

      expect(restored.model, 'IdeaPad 3 14"');
      expect(restored.description, 'It shuts off after a minute.\n\nFan is loud.');
      expect(restored.notes, 'Gate code 1234');
      // Saving again must not grow a second "Model:" line.
      expect(restored.composedDescription, original.composedDescription);
    });

    test('a description with only free text stays free text', () {
      final JobDraft d = JobDraft()..restoreDescription('Just broken.');
      expect(d.description, 'Just broken.');
      expect(d.model, isNull);
      expect(d.notes, isNull);
    });

    test('nothing stays nothing', () {
      final JobDraft d = JobDraft()..restoreDescription(null);
      expect(d.composedDescription, isNull);
    });
  });

  group('DeviceCategory.forJob', () {
    test('a camera symptom reopens the CCTV card, not Network', () {
      expect(
        DeviceCategory.forJob(
          deviceType: DeviceType.network,
          symptomCode: 'cctv_no_video',
        ),
        DeviceCategory.cctv,
      );
      expect(
        DeviceCategory.forJob(
          deviceType: DeviceType.network,
          symptomCode: 'network_no_internet',
        ),
        DeviceCategory.network,
      );
      expect(
        DeviceCategory.forJob(deviceType: DeviceType.appliance),
        DeviceCategory.appliance,
      );
    });
  });

  group('editing an existing job', () {
    test('every answer is filled in, including the path they chose', () {
      final JobPostingProvider posting = JobPostingProvider.editing(
        _savedJob,
        service: _CountingService(),
      );
      addTearDown(posting.dispose);

      expect(posting.isEditing, isTrue);
      expect(posting.deviceCategory, DeviceCategory.laptop);
      expect(posting.draft.brand, 'Lenovo');
      expect(posting.draft.deviceDetail, 'laptop');
      expect(posting.draft.problemSymptom, 'laptop_wont_power_on');
      expect(posting.draft.latitude, 7.0731);
      expect(posting.draft.locationLabel, 'Bajada, Davao City');
      expect(posting.draft.budgetMax, 1500);
      expect(posting.draft.model, 'IdeaPad 3');
      expect(posting.draft.description, 'Dead after a storm.');
      // The client overrode the suggestion when posting; the edit keeps it.
      expect(posting.draft.servicePath, ServicePath.pickup);
      expect(posting.keptPhotoUrls, <String>['https://x/a.jpg', 'https://x/b.jpg']);
      expect(posting.canSubmit, isTrue);
    });

    test('saving updates the same job with kept and new photos', () async {
      final _CountingService service = _CountingService(uploaded: <String>['https://x/c.jpg']);
      final JobPostingProvider posting = JobPostingProvider.editing(
        _savedJob,
        service: service,
      );
      addTearDown(posting.dispose);

      posting.removeKeptPhoto('https://x/a.jpg');
      posting.addPhoto(XFile.fromData(Uint8List(1), name: 'new.jpg'));
      posting.setBudget(min: 500, max: 2000);

      final Job? saved = await posting.submit();

      expect(saved, isNotNull);
      expect(service.inserts, 0);
      expect(service.updatedJobIds, <String>['job-9']);
      expect(service.lastDraft!.photoUrls, <String>['https://x/b.jpg', 'https://x/c.jpg']);
      expect(service.lastDraft!.budgetMax, 2000);
      expect(service.matchingRuns, 1);
      // The new photo is now held by URL, so a second save does not re-upload it.
      expect(posting.photos, isEmpty);
      expect(posting.keptPhotoUrls, <String>['https://x/b.jpg', 'https://x/c.jpg']);
    });
  });

  group('posting twice', () {
    test('a second submit updates the job instead of posting another', () async {
      final _CountingService service = _CountingService();
      final JobPostingProvider posting = JobPostingProvider(service: service);
      addTearDown(posting.dispose);
      posting.selectCategory(DeviceCategory.laptop);
      posting.selectSymptom('laptop_wont_power_on');
      posting.setLocation(latitude: 7.0731, longitude: 125.6128);

      await posting.submit();
      await posting.submit();

      expect(service.inserts, 1, reason: 'the job must be inserted once');
      expect(service.updatedJobIds, <String>['job-new']);
    });

    testWidgets('back from the matches goes home, not to the map step', (
      WidgetTester tester,
    ) async {
      final _CountingService service = _CountingService();
      final JobPostingProvider posting = JobPostingProvider(service: service);
      addTearDown(posting.dispose);
      posting.selectCategory(DeviceCategory.laptop);
      posting.selectSymptom('laptop_wont_power_on');
      posting.setLocation(latitude: 7.0731, longitude: 125.6128);

      final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: AppTheme.light,
          home: const Scaffold(body: Text('HOME')),
        ),
      );

      // The flow as the client walks it: home, the map step, then review.
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('MAP STEP')),
        ),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => ReviewAndPostScreen(posting: posting),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Find technician'));
      await tester.pump();
      // Past the post, the match and the analysis screen's ~0.7 s finish.
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Choose a technician'), findsOneWidget);
      expect(service.inserts, 1);

      // The system back gesture.
      await navigator.currentState!.maybePop();
      await tester.pumpAndSettle();

      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('MAP STEP'), findsNothing);
      expect(service.inserts, 1, reason: 'going back must not post again');
    });
  });
}

final Job _savedJob = Job(
  id: 'job-9',
  clientId: 'client-1',
  deviceType: DeviceType.laptop,
  deviceDetail: 'laptop',
  brand: 'Lenovo',
  problemSymptom: 'laptop_wont_power_on',
  hasPhysicalDamage: false,
  status: JobStatus.matched,
  servicePath: ServicePath.pickup,
  latitude: 7.0731,
  longitude: 125.6128,
  addressText: 'Bajada, Davao City',
  budgetMin: 500,
  budgetMax: 1500,
  description: 'Model: IdeaPad 3\n\nDead after a storm.',
  photoUrls: const <String>['https://x/a.jpg', 'https://x/b.jpg'],
);

/// Records what the provider asked for, and answers instantly.
class _CountingService implements RbCarsService {
  _CountingService({this.uploaded = const <String>[]});

  final List<String> uploaded;
  int inserts = 0;
  int matchingRuns = 0;
  final List<String> updatedJobIds = <String>[];
  JobDraft? lastDraft;

  Job _jobFor(String id, JobDraft draft) => Job(
    id: id,
    clientId: 'client-1',
    deviceType: draft.deviceType ?? DeviceType.laptop,
    problemSymptom: draft.problemSymptom ?? '',
    hasPhysicalDamage: draft.hasPhysicalDamage,
    status: JobStatus.pending,
  );

  @override
  Future<Job> postJob(JobDraft draft) async {
    inserts++;
    lastDraft = draft;
    return _jobFor('job-new', draft);
  }

  @override
  Future<Job> updateJob(String jobId, JobDraft draft) async {
    updatedJobIds.add(jobId);
    lastDraft = draft;
    return _jobFor(jobId, draft);
  }

  @override
  Future<List<String>> uploadPhotos(List<XFile> files) async => uploaded;

  @override
  Future<MatchingRun> runMatching(
    String jobId, {
    List<String> excludeTechnicianIds = const <String>[],
  }) async {
    matchingRuns++;
    return const MatchingRun();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
