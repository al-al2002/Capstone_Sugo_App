import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/features/rb_cars/models/device_category.dart';
import 'package:sugo_app/features/rb_cars/models/job.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';
import 'package:sugo_app/features/rb_cars/models/match_result.dart';
import 'package:sugo_app/features/rb_cars/models/technician_preferences.dart';
import 'package:sugo_app/features/rb_cars/providers/job_posting_provider.dart';
import 'package:sugo_app/features/rb_cars/providers/match_provider.dart';
import 'package:sugo_app/features/rb_cars/services/rb_cars_service.dart';

/// The client preference pre-filter, app side (2026-11-15).
///
/// The engine's half is pinned in `match-technician/scoring/
/// preferences.test.ts`. This half is the contract with the database - six
/// `pref_*` columns whose CHECK constraints refuse anything off the fixed
/// options - and the two hand-offs a client actually feels: the step that
/// sets them, and the "try relaxing them" way out when they leave nobody.
void main() {
  group('TechnicianPreferences and the six columns', () {
    test('nothing set writes six nulls and reads as No preference', () {
      const TechnicianPreferences none = TechnicianPreferences.none;
      expect(none.hasAny, isFalse);
      expect(none.summary, 'No preference');
      expect(none.toColumns(), <String, Object?>{
        'pref_specialization': null,
        'pref_max_distance_km': null,
        'pref_min_rating': null,
        'pref_availability': null,
        'pref_available_on': null,
        'pref_min_trust': null,
      });
    });

    test('every value the app writes is one the CHECK constraints allow', () {
      final TechnicianPreferences all = TechnicianPreferences(
        specialization: PreferredSpecialization.phoneTablet,
        maxDistance: MaxDistance.km5,
        minRating: MinRating.r45,
        availability: AvailabilityPreference.onDate,
        availableOn: DateTime(2026, 11, 20),
        minTrust: TrustBadge.skillVerified,
      );
      expect(all.toColumns(), <String, Object?>{
        'pref_specialization': 'phone_tablet',
        'pref_max_distance_km': 5,
        'pref_min_rating': 4.5,
        'pref_availability': 'on_date',
        'pref_available_on': '2026-11-20',
        'pref_min_trust': 'skill_verified',
      });

      const Set<String> specs = <String>{
        'computer',
        'phone_tablet',
        'network_setup',
        'appliance',
        'pc_building',
      };
      for (final PreferredSpecialization s in PreferredSpecialization.values) {
        expect(specs, contains(s.wire));
      }
      expect(MaxDistance.values.map((MaxDistance d) => d.km), <int>[3, 5, 10]);
      expect(MinRating.values.map((MinRating r) => r.value), <double>[
        3.0,
        4.0,
        4.5,
      ]);
    });

    test('a saved job reads back as the same preferences', () {
      final TechnicianPreferences original = TechnicianPreferences(
        specialization: PreferredSpecialization.pcBuilding,
        maxDistance: MaxDistance.km10,
        minRating: MinRating.r30,
        availability: AvailabilityPreference.onDate,
        availableOn: DateTime(2026, 12, 1),
        minTrust: TrustBadge.communityTrusted,
      );
      expect(TechnicianPreferences.fromJson(original.toColumns()), original);
    });

    test('PostgREST numeric strings are read, off-list values are not', () {
      final TechnicianPreferences read =
          TechnicianPreferences.fromJson(<String, dynamic>{
            'pref_min_rating': '4.5',
            'pref_max_distance_km': 7,
            'pref_specialization': 'errands',
            'pref_min_trust': 'certified_pro',
            'pref_availability': 'on_date',
            'pref_available_on': null,
          });
      expect(read.minRating, MinRating.r45);
      expect(read.maxDistance, isNull);
      expect(read.specialization, isNull);
      expect(read.minTrust, isNull);
      expect(
        read.availability,
        isNull,
        reason: 'A date preference without its date cannot be checked.',
      );
    });

    test('"Pick a date" is never written without its date', () {
      const TechnicianPreferences half = TechnicianPreferences(
        availability: AvailabilityPreference.onDate,
      );
      expect(half.isMissingDate, isTrue);
      expect(half.toColumns()['pref_availability'], isNull);
      expect(half.toColumns()['pref_available_on'], isNull);
    });

    test('leaving "Pick a date" drops the date with it', () {
      final TechnicianPreferences dated = TechnicianPreferences(
        availability: AvailabilityPreference.onDate,
        availableOn: DateTime(2026, 11, 20),
      );
      final TechnicianPreferences now = dated.copyWith(
        availability: () => AvailabilityPreference.now,
      );
      expect(now.availableOn, isNull);
      expect(now.toColumns()['pref_available_on'], isNull);
    });

    test('without() removes exactly one preference', () {
      const TechnicianPreferences prefs = TechnicianPreferences(
        maxDistance: MaxDistance.km3,
        minRating: MinRating.r45,
      );
      final TechnicianPreferences relaxed = prefs.without(
        PreferenceField.maxDistance,
      );
      expect(relaxed.maxDistance, isNull);
      expect(relaxed.minRating, MinRating.r45);
      expect(relaxed.active, <PreferenceField>[PreferenceField.minRating]);
    });

    test('specialisations on offer follow the device picked on step 1', () {
      expect(
        PreferredSpecialization.forCategory(DeviceCategory.phone),
        <PreferredSpecialization>[PreferredSpecialization.phoneTablet],
      );
      expect(
        PreferredSpecialization.forCategory(DeviceCategory.laptop),
        <PreferredSpecialization>[
          PreferredSpecialization.computer,
          PreferredSpecialization.pcBuilding,
        ],
      );
      expect(
        PreferredSpecialization.forCategory(DeviceCategory.cctv),
        <PreferredSpecialization>[PreferredSpecialization.networkSetup],
      );
    });

    test('relax hints keep known preferences and skip unknown ones', () {
      final List<RelaxHint> hints = RelaxHint.listFrom(<Object>[
        <String, dynamic>{'preference': 'max_distance_km', 'would_match': 2},
        <String, dynamic>{'preference': 'a_sixth_one', 'would_match': 9},
      ]);
      expect(hints, hasLength(1));
      expect(hints.single.field, PreferenceField.maxDistance);
      expect(hints.single.wouldMatch, 2);
    });
  });

  group('JobDraft writes them', () {
    JobDraft draft() => JobDraft()
      ..deviceType = DeviceType.phone
      ..problemSymptom = 'phone_screen_cracked';

    test('a post with no preferences sends no pref_ columns at all', () {
      final Map<String, dynamic> row = draft().toInsert(clientId: 'c');
      expect(
        row.keys.where((String k) => k.startsWith('pref_')),
        isEmpty,
        reason:
            'Leaving them out keeps posting working against a database the '
            'migration has not reached yet.',
      );
    });

    test('a post with preferences sends all six', () {
      final JobDraft withPrefs = draft()
        ..preferences = const TechnicianPreferences(minRating: MinRating.r40);
      final Map<String, dynamic> row = withPrefs.toInsert(clientId: 'c');
      expect(row['pref_min_rating'], 4.0);
      expect(row.containsKey('pref_min_trust'), isTrue);
    });

    test('an edit always sends all six, so removing one clears it', () {
      final Map<String, dynamic> row = draft().toUpdate();
      expect(row.containsKey('pref_max_distance_km'), isTrue);
      expect(row['pref_max_distance_km'], isNull);
    });
  });

  group('the posting flow', () {
    test('a new device drops a specialisation it cannot use, nothing else', () {
      final JobPostingProvider posting = JobPostingProvider(
        service: _StubService(),
      );
      addTearDown(posting.dispose);

      posting.selectCategory(DeviceCategory.phone);
      posting.setPreferences(
        const TechnicianPreferences(
          specialization: PreferredSpecialization.phoneTablet,
          minRating: MinRating.r45,
        ),
      );

      posting.selectCategory(DeviceCategory.appliance);

      expect(posting.preferences.specialization, isNull);
      expect(posting.preferences.minRating, MinRating.r45);
    });

    test('the step only blocks on "Pick a date" without a date', () {
      final JobPostingProvider posting = JobPostingProvider(
        service: _StubService(),
      );
      addTearDown(posting.dispose);

      expect(posting.canLeavePreferences, isTrue);
      posting.setPreferences(
        const TechnicianPreferences(
          availability: AvailabilityPreference.onDate,
        ),
      );
      expect(posting.canLeavePreferences, isFalse);
      posting.setPreferences(
        posting.preferences.copyWith(availableOn: () => DateTime(2026, 11, 20)),
      );
      expect(posting.canLeavePreferences, isTrue);
    });

    test(
      'an empty run blamed on preferences is handed to the review',
      () async {
        final JobPostingProvider posting = JobPostingProvider(
          service: _StubService(
            run: const MatchingRun(
              message: 'No technician matches all of your preferences.',
              preferencesBlocked: true,
              relaxHints: <RelaxHint>[
                RelaxHint(field: PreferenceField.minRating, wouldMatch: 3),
              ],
            ),
          ),
        );
        addTearDown(posting.dispose);
        posting
          ..selectCategory(DeviceCategory.phone)
          ..selectSymptom('phone_screen_cracked')
          ..overrideServicePath(ServicePath.homeService)
          ..setLocation(latitude: 7.07, longitude: 125.61);

        await posting.submit();

        expect(posting.preferencesBlocked, isTrue);
        expect(posting.relaxHints.single.wouldMatch, 3);
      },
    );
  });

  group('the review screen offers a way out', () {
    test('a blocked run shows the relax panel, not the empty state', () async {
      final _StubService service = _StubService(
        job: _jobWith(const TechnicianPreferences(minRating: MinRating.r45)),
      );
      final MatchProvider matching = MatchProvider(
        jobId: 'job-1',
        service: service,
        initialPreferencesBlocked: true,
      );
      addTearDown(matching.dispose);

      await matching.load();

      expect(matching.showRelaxPreferences, isTrue);
    });

    test(
      'a run that is empty for another reason does not blame them',
      () async {
        final _StubService service = _StubService(
          job: _jobWith(const TechnicianPreferences(minRating: MinRating.r45)),
          run: const MatchingRun(message: 'No technician within 50 km.'),
        );
        final MatchProvider matching = MatchProvider(
          jobId: 'job-1',
          service: service,
        );
        addTearDown(matching.dispose);

        await matching.rematch();

        expect(matching.showRelaxPreferences, isFalse);
      },
    );

    test('relaxing saves the looser set on the job, then re-runs', () async {
      final _StubService service = _StubService(
        job: _jobWith(
          const TechnicianPreferences(
            maxDistance: MaxDistance.km3,
            minRating: MinRating.r45,
          ),
        ),
        run: MatchingRun(matches: <MatchResult>[_match]),
      );
      final MatchProvider matching = MatchProvider(
        jobId: 'job-1',
        service: service,
        initialPreferencesBlocked: true,
      );
      addTearDown(matching.dispose);
      await matching.load();

      await matching.relaxPreferences(
        matching.job!.preferences.without(PreferenceField.maxDistance),
      );

      expect(service.saved?.maxDistance, isNull);
      expect(service.saved?.minRating, MinRating.r45);
      expect(service.runs, 1);
      expect(matching.matches, hasLength(1));
      expect(matching.showRelaxPreferences, isFalse);
    });
  });
}

Job _jobWith(TechnicianPreferences preferences) => Job(
  id: 'job-1',
  clientId: 'client-1',
  deviceType: DeviceType.phone,
  problemSymptom: 'phone_screen_cracked',
  hasPhysicalDamage: false,
  status: JobStatus.pending,
  preferences: preferences,
);

final MatchResult _match = MatchResult.fromJson(<String, dynamic>{
  'id': 'm1',
  'job_id': 'job-1',
  'technician_id': 't1',
  'rank': 1,
  'status': 'shortlisted',
});

/// Posts instantly, returns the run it was given, and remembers what
/// preferences were saved.
class _StubService implements RbCarsService {
  _StubService({Job? job, this.run = const MatchingRun()})
    : _job = job ?? _jobWith(TechnicianPreferences.none);

  Job _job;
  final MatchingRun run;
  TechnicianPreferences? saved;
  int runs = 0;

  @override
  Future<Job> postJob(JobDraft draft) async => _job;

  @override
  Future<List<String>> uploadPhotos(List<XFile> files) async => <String>[];

  @override
  Future<MatchingRun> runMatching(
    String jobId, {
    List<String> excludeTechnicianIds = const <String>[],
  }) async {
    runs += 1;
    return run;
  }

  @override
  Future<Job> updatePreferences(
    String jobId,
    TechnicianPreferences preferences,
  ) async {
    saved = preferences;
    _job = _jobWith(preferences);
    return _job;
  }

  @override
  Future<Job?> jobById(String jobId) async => _job;

  @override
  Future<List<MatchResult>> fetchMatches(String jobId) async =>
      runs > 0 ? run.matches : const <MatchResult>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
