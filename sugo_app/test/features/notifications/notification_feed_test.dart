import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sugo_app/core/services/local_prefs.dart';
import 'package:sugo_app/features/chat/models/chat_models.dart';
import 'package:sugo_app/features/chat/services/chat_service.dart';
import 'package:sugo_app/features/notifications/models/app_notification.dart';
import 'package:sugo_app/features/notifications/services/notification_feed_service.dart';
import 'package:sugo_app/features/rb_cars/models/job.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';
import 'package:sugo_app/features/rb_cars/models/job_technician.dart';
import 'package:sugo_app/features/rb_cars/services/rb_cars_service.dart';
import 'package:sugo_app/features/tracking/models/job_tracking.dart';
import 'package:sugo_app/features/tracking/services/tracking_service.dart';

/// The notification centre is *derived* - SUGO stores no notifications - so
/// these tests pin the derivation rules rather than a table's contents.
void main() {
  const String uid = 'client-1';

  Job job({
    required String id,
    required JobStatus status,
    ServicePath? path,
    DateTime? createdAt,
  }) => Job(
    id: id,
    clientId: uid,
    deviceType: DeviceType.appliance,
    problemSymptom: 'appliance_not_cooling',
    hasPhysicalDamage: false,
    status: status,
    servicePath: path,
    assignedTechnicianId: status == JobStatus.pending ? null : 'tech-1',
    createdAt: createdAt ?? DateTime.now().subtract(const Duration(hours: 2)),
  );

  JobTechnician technician(MatchStatus status) =>
      JobTechnician.fromJson(<String, dynamic>{
        'job_id': 'job-1',
        'match_id': 'm1',
        'technician_id': 'tech-1',
        'status': status.wire,
        'technician': <String, dynamic>{'full_name': 'Ryan Santos'},
        'created_at': DateTime.now()
            .subtract(const Duration(hours: 1))
            .toIso8601String(),
      });

  NotificationFeedService build({
    List<Job> jobs = const <Job>[],
    Map<String, JobTechnician> people = const <String, JobTechnician>{},
    List<Conversation> threads = const <Conversation>[],
    Map<String, JobTracking> tracking = const <String, JobTracking>{},
  }) => NotificationFeedService(
    jobs: _FakeJobs(jobs, people),
    chat: _FakeChat(threads),
    tracking: _FakeTracking(tracking),
    prefs: LocalPrefs.instance,
    currentUserId: () => uid,
  );

  setUp(() {
    // A working preference store, so read state and the observed-time map
    // behave as they do on a device - and a singleton that has forgotten the
    // previous test's values.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LocalPrefs.instance.debugReset();
  });

  test('a job contributes only its latest state, not its history', () async {
    final List<AppNotification> feed = await build(
      jobs: <Job>[job(id: 'job-1', status: JobStatus.confirmed)],
      people: <String, JobTechnician>{'job-1': technician(MatchStatus.accepted)},
    ).load();

    expect(feed, hasLength(1));
    // First name only: a notification is read at a glance, and "Ryan accepted
    // your booking" is how a person would say it.
    expect(feed.single.title, 'Ryan accepted your booking');
    expect(feed.single.category, NotificationCategory.booking);
  });

  test('a first run marks everything read instead of crying wolf', () async {
    final NotificationFeedService service = build(
      jobs: <Job>[job(id: 'job-1', status: JobStatus.completed)],
    );

    final List<AppNotification> first = await service.load();
    expect(
      first.single.unread,
      isFalse,
      reason:
          'Installing this version must not present old bookings as new '
          'unread alerts.',
    );
  });

  test('a status change after the first run arrives unread', () async {
    // First run: the job is confirmed, and everything is seeded as read.
    await build(
      jobs: <Job>[job(id: 'job-1', status: JobStatus.confirmed)],
      people: <String, JobTechnician>{'job-1': technician(MatchStatus.accepted)},
    ).load();

    // The same job later completes: a new id, so a new unread item.
    final List<AppNotification> after = await build(
      jobs: <Job>[job(id: 'job-1', status: JobStatus.completed)],
      people: <String, JobTechnician>{'job-1': technician(MatchStatus.accepted)},
    ).load();

    expect(after.single.title, 'Service completed');
    expect(after.single.unread, isTrue);
  });

  test('marking seen clears it, and survives a reload', () async {
    final NotificationFeedService service = build(
      jobs: <Job>[job(id: 'job-1', status: JobStatus.confirmed)],
      people: <String, JobTechnician>{'job-1': technician(MatchStatus.accepted)},
    );
    await service.load();

    final List<AppNotification> fresh = await build(
      jobs: <Job>[job(id: 'job-1', status: JobStatus.inProgress)],
      people: <String, JobTechnician>{'job-1': technician(MatchStatus.accepted)},
    ).load();
    expect(fresh.single.unread, isTrue);

    await service.markSeen(fresh);

    final List<AppNotification> again = await build(
      jobs: <Job>[job(id: 'job-1', status: JobStatus.inProgress)],
      people: <String, JobTechnician>{'job-1': technician(MatchStatus.accepted)},
    ).load();
    expect(again.single.unread, isFalse);
  });

  test('an unread thread becomes a message item, always unread', () async {
    final List<AppNotification> feed = await build(
      threads: <Conversation>[
        Conversation.fromJson(<String, dynamic>{
          'job_id': 'job-1',
          'counterpart': <String, dynamic>{'full_name': 'Ryan Santos'},
          'job_status': JobStatus.confirmed.wire,
          'device_type': 'appliance',
          'problem_symptom': 'appliance_not_cooling',
          'last_message': 'On my way now.',
          'last_message_at': DateTime.now().toIso8601String(),
          'unread_count': 2,
        }),
      ],
    ).load();

    expect(feed, hasLength(1));
    expect(feed.single.category, NotificationCategory.messages);
    expect(feed.single.title, '2 new messages from Ryan');
    expect(
      feed.single.unread,
      isTrue,
      reason:
          'Chat read state is the server\'s - it clears when the thread is '
          'opened, not when the centre is scrolled past.',
    );
  });

  test('a travelling pickup job adds a tracking item', () async {
    final List<AppNotification> feed = await build(
      jobs: <Job>[
        job(id: 'job-1', status: JobStatus.confirmed, path: ServicePath.pickup),
      ],
      people: <String, JobTechnician>{'job-1': technician(MatchStatus.accepted)},
      tracking: <String, JobTracking>{
        'job-1': JobTracking.fromJson(<String, dynamic>{
          'id': 'tr1',
          'job_id': 'job-1',
          'technician_id': 'tech-1',
          'stage': 'heading_to_pickup',
          'started_at': DateTime.now()
              .subtract(const Duration(minutes: 10))
              .toIso8601String(),
        }),
      },
    ).load();

    final AppNotification tracking = feed.firstWhere(
      (AppNotification n) => n.category == NotificationCategory.tracking,
    );
    expect(tracking.title, 'Technician is on the way');
    expect(tracking.action, NotificationAction.openTracking);
  });

  test('a muted category disappears from the feed and the count', () async {
    await LocalPrefs.instance.setNotificationEnabled(
      uid,
      NotificationCategory.booking.name,
      false,
    );

    final NotificationFeedService service = build(
      jobs: <Job>[job(id: 'job-1', status: JobStatus.confirmed)],
      people: <String, JobTechnician>{'job-1': technician(MatchStatus.accepted)},
    );

    expect(await service.load(), isEmpty);
    expect(await service.unreadCount(), 0);
  });

  test('finished work older than three weeks drops out', () async {
    final List<AppNotification> feed = await build(
      jobs: <Job>[
        job(
          id: 'job-1',
          status: JobStatus.completed,
          createdAt: DateTime.now().subtract(const Duration(days: 60)),
        ),
      ],
    ).load();

    expect(feed, isEmpty);
  });
}

class _FakeJobs implements RbCarsService {
  _FakeJobs(this.jobs, this.people);

  final List<Job> jobs;
  final Map<String, JobTechnician> people;

  @override
  Future<List<Job>> myJobs({JobStatus? status}) async => jobs;

  @override
  Future<Map<String, JobTechnician>> bookedTechnicians() async => people;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeChat implements ChatService {
  _FakeChat(this.threads);

  final List<Conversation> threads;

  @override
  Future<List<Conversation>> conversations() async => threads;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTracking implements TrackingService {
  _FakeTracking(this.rows);

  final Map<String, JobTracking> rows;

  @override
  Future<JobTracking?> fetch(String jobId) async => rows[jobId];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
