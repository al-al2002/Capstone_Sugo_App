import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sugo_app/core/services/local_prefs.dart';
import 'package:sugo_app/features/rb_cars/models/job.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';
import 'package:sugo_app/features/rb_cars/models/match_result.dart';
import 'package:sugo_app/features/rb_cars/services/match_decline_watcher.dart';
import 'package:sugo_app/features/rb_cars/services/rb_cars_service.dart';
import 'package:sugo_app/features/technician/widgets/decline_confirm.dart';

/// Declines, both ends (2026-11-23): the technician is asked first, and the
/// client hears it over Realtime even when no push can arrive.
void main() {
  Job job(JobStatus status) => Job(
    id: 'job-1',
    clientId: 'c',
    deviceType: DeviceType.laptop,
    problemSymptom: 'laptop_overheating',
    hasPhysicalDamage: false,
    status: status,
  );

  Map<String, dynamic> row(String status, {String technician = 't1'}) =>
      <String, dynamic>{
        'id': 'm-$technician',
        'job_id': 'job-1',
        'technician_id': technician,
        'rank': 1,
        'status': status,
        'score_breakdown': <String, dynamic>{
          'technician': <String, dynamic>{
            'id': technician,
            'full_name': 'Lyra Cruz',
          },
        },
      };

  MatchResult match(String status, {String technician = 't1'}) =>
      MatchResult.fromJson(row(status, technician: technician));

  group('isTechnicianDecline', () {
    test('the technician declined: the job is open, nobody holds an offer', () {
      expect(
        isTechnicianDecline(job(JobStatus.matched), <MatchResult>[
          match('declined'),
          match('shortlisted', technician: 't2'),
        ]),
        isTrue,
      );
    });

    test('the client picked someone else: a live offer exists - silent', () {
      expect(
        isTechnicianDecline(job(JobStatus.matched), <MatchResult>[
          match('declined'),
          match('offered', technician: 't2'),
        ]),
        isFalse,
      );
    });

    test('someone accepted: the job is confirmed - silent', () {
      expect(
        isTechnicianDecline(job(JobStatus.confirmed), <MatchResult>[
          match('declined'),
          match('accepted', technician: 't2'),
        ]),
        isFalse,
      );
    });

    test('no job, nothing to say', () {
      expect(isTechnicianDecline(null, const <MatchResult>[]), isFalse);
    });
  });

  group('unannouncedDecline (a decline while the app was closed)', () {
    final DateTime now = DateTime(2026, 11, 23, 20);

    MatchResult answered(
      String id,
      String status,
      DateTime? at, {
      String technician = 't1',
    }) => MatchResult.fromJson(<String, dynamic>{
      ...row(status, technician: technician),
      'id': id,
      'responded_at': at?.toIso8601String(),
    });

    test('the latest unseen decline is announced', () {
      final MatchResult? missed = unannouncedDecline(
        job(JobStatus.matched),
        <MatchResult>[
          answered('old', 'declined', now.subtract(const Duration(hours: 5))),
          answered('new', 'declined', now.subtract(const Duration(minutes: 3))),
          answered('s', 'shortlisted', null, technician: 't3'),
        ],
        const <String>{},
        now: now,
      );
      expect(missed?.id, 'new');
    });

    test('once announced, never again', () {
      expect(
        unannouncedDecline(
          job(JobStatus.matched),
          <MatchResult>[
            answered('new', 'declined', now.subtract(const Duration(minutes: 3))),
          ],
          const <String>{'new'},
          now: now,
        ),
        isNull,
      );
    });

    test('old history is not news', () {
      expect(
        unannouncedDecline(
          job(JobStatus.matched),
          <MatchResult>[
            answered('x', 'declined', now.subtract(const Duration(days: 4))),
          ],
          const <String>{},
          now: now,
        ),
        isNull,
      );
    });

    test('silent while another offer is live, or a row was never offered', () {
      expect(
        unannouncedDecline(
          job(JobStatus.matched),
          <MatchResult>[
            answered('a', 'declined', now.subtract(const Duration(minutes: 3))),
            answered('b', 'offered', null, technician: 't2'),
          ],
          const <String>{},
          now: now,
        ),
        isNull,
      );
      // Declined but never answered as an offer (closed when someone else
      // took the job): not a technician's decline.
      expect(
        unannouncedDecline(
          job(JobStatus.matched),
          <MatchResult>[answered('c', 'declined', null)],
          const <String>{},
          now: now,
        ),
        isNull,
      );
    });

    test('the device remembers what it has announced', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      LocalPrefs.instance.debugReset();

      expect(await LocalPrefs.instance.shownDeclines(), isEmpty);
      await LocalPrefs.instance.markDeclineShown('m-1');
      await LocalPrefs.instance.markDeclineShown('m-2');
      expect(await LocalPrefs.instance.shownDeclines(), <String>{'m-1', 'm-2'});
    });
  });

  group('MatchDeclineWatcher', () {
    test('announces a real decline, with the technician\'s name, once', () async {
      final _FakeService service = _FakeService(
        job(JobStatus.matched),
        <MatchResult>[match('declined')],
      );
      final MatchDeclineWatcher watcher = MatchDeclineWatcher(
        service: service,
        settle: Duration.zero,
      );
      final List<DeclineNotice> heard = <DeclineNotice>[];
      final StreamSubscription<DeclineNotice> sub = watcher.notices.listen(
        heard.add,
      );

      // Two rows of one job at once are checked once.
      watcher.onDeclined(row('declined'));
      watcher.onDeclined(row('declined', technician: 't2'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(heard, hasLength(1));
      expect(heard.single.jobId, 'job-1');
      expect(heard.single.technicianName, 'Lyra Cruz');
      expect(service.reads, 1);

      await sub.cancel();
      await watcher.dispose();
    });

    test('stays silent when the decline was not the technician\'s', () async {
      final MatchDeclineWatcher watcher = MatchDeclineWatcher(
        service: _FakeService(job(JobStatus.matched), <MatchResult>[
          match('declined'),
          match('offered', technician: 't2'),
        ]),
        settle: Duration.zero,
      );
      final List<DeclineNotice> heard = <DeclineNotice>[];
      final StreamSubscription<DeclineNotice> sub = watcher.notices.listen(
        heard.add,
      );

      watcher.onDeclined(row('declined'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(heard, isEmpty);

      await sub.cancel();
      await watcher.dispose();
    });
  });

  group('confirmDeclineOffer', () {
    Future<List<bool>> open(WidgetTester tester) async {
      final List<bool> answers = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    answers.add(await confirmDeclineOffer(context)),
                child: const Text('Decline'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();
      return answers;
    }

    testWidgets('asks first; Decline confirms', (WidgetTester tester) async {
      final List<bool> answers = await open(tester);
      expect(find.text('Decline this request?'), findsOneWidget);
      expect(
        find.textContaining('Are you sure you want to decline it?'),
        findsOneWidget,
      );

      // The dialog's own Decline button (the host's is under the barrier).
      await tester.tap(find.text('Decline').last);
      await tester.pumpAndSettle();
      expect(answers, <bool>[true]);
    });

    testWidgets('Keep it declines nothing', (WidgetTester tester) async {
      final List<bool> answers = await open(tester);
      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(answers, <bool>[false]);
    });
  });
}

class _FakeService implements RbCarsService {
  _FakeService(this.job, this.matches);

  final Job job;
  final List<MatchResult> matches;
  int reads = 0;

  @override
  Future<Job?> jobById(String jobId) async {
    reads++;
    return job;
  }

  @override
  Future<List<MatchResult>> fetchMatches(String jobId) async => matches;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
