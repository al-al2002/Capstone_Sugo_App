import 'package:flutter/material.dart';

import '../../../core/services/local_prefs.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/widgets/sugo_status_badge.dart';
import '../../chat/models/chat_models.dart';
import '../../chat/services/chat_service.dart';
import '../../rb_cars/models/job.dart';
import '../../rb_cars/models/job_enums.dart';
import '../../rb_cars/models/job_technician.dart';
import '../../rb_cars/models/match_result.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../../technician/services/technician_service.dart';
import '../../tracking/models/job_tracking.dart';
import '../../tracking/services/tracking_service.dart';
import '../models/app_notification.dart';

/// Who the feed is being built for.
///
/// The two roles share every mechanism here - the derived-item plumbing, the
/// per-device read state, the muting, the history cutoff - and share none of
/// the *sources*. A client's feed is about their bookings; a technician's is
/// about work arriving and what the client has asked for. One service with
/// two source sets keeps that plumbing in one place; two services would have
/// duplicated it and drifted.
enum NotificationAudience { client, technician }

/// Builds a notification centre from data SUGO already has.
///
/// ## Sources, for a client
///
/// | Source | Becomes |
/// |---|---|
/// | `jobs` status (+ the requested technician) | Booking and Service items |
/// | `job_tracking` stage and delay | Tracking items |
/// | `job_conversations` unread counts | Message items |
///
/// ## Sources, for a technician
///
/// | Source | Becomes |
/// |---|---|
/// | `job_matches` where `status = 'offered'` | "New job request" |
/// | `job_return_preferences` on their live jobs | "They will collect it" / "They want it delivered" |
/// | `job_conversations` unread counts | Message items |
///
/// A technician's request item is the in-app half of a push that already
/// existed: `job-response` has sent "New job request" to their phone since
/// 20260922000006. What was missing was anywhere to see it afterwards - a
/// dismissed or missed push was simply gone.
///
/// Only the *latest* state of each job appears, not its whole history: a job
/// that went pending -> matched -> confirmed shows one "Ryan accepted your
/// booking" item, not three. The notification centre answers "what is new
/// with my bookings", and the timeline on the booking itself is where the
/// history lives.
///
/// ## Timestamps, honestly
///
/// Where the database records a time it is used - a job's `created_at`, a
/// match's creation, a tracking row's `updated_at`, a message's `created_at`.
/// A status change like "confirmed" has no timestamp of its own, so it is
/// stamped the first time this device sees it and that stamp is kept. In
/// practice that is minutes after the fact, because the dashboard refreshes
/// on every resume.
///
/// ## The first run
///
/// On a device that has never built the feed, every existing item is stamped
/// with its job's `created_at` and marked read. Without that, the first open
/// after installing this version would present a year of old bookings as
/// brand-new unread alerts.
class NotificationFeedService {
  NotificationFeedService({
    this.audience = NotificationAudience.client,
    RbCarsService? jobs,
    ChatService? chat,
    TrackingService? tracking,
    TechnicianService? technician,
    LocalPrefs? prefs,
    String? Function()? currentUserId,
  }) : _jobs = jobs ?? RbCarsService(),
       _chat = chat ?? ChatService(),
       _tracking = tracking ?? TrackingService(),
       _technicianService = technician,
       _prefs = prefs ?? LocalPrefs.instance,
       _uid = currentUserId ?? (() => SupabaseService.auth.currentUser?.id);

  final NotificationAudience audience;

  final RbCarsService _jobs;
  final ChatService _chat;
  final TrackingService _tracking;

  /// Built on first use rather than in the constructor, so a client feed
  /// never constructs one - and so a widget test that only needs the client
  /// side does not have to supply it.
  TechnicianService? _technicianService;
  TechnicianService get _technician =>
      _technicianService ??= TechnicianService();

  final LocalPrefs _prefs;
  final String? Function() _uid;

  /// Finished jobs older than this drop out of the feed entirely.
  static const Duration _history = Duration(days: 21);

  /// At most this many pickup jobs are asked for a tracking row per load.
  static const int _maxTrackingLookups = 3;

  /// The feed, newest first, with muted categories removed.
  Future<List<AppNotification>> load() async {
    final String? uid = _uid();
    if (uid == null) return const <AppNotification>[];

    // Chat is the one source both roles share, so it is read once here and
    // the role-specific sources are gathered alongside it.
    final List<Conversation> threads = await _chat.conversations().catchError(
      (Object _) => <Conversation>[],
    );

    final List<_Draft> drafts = switch (audience) {
      NotificationAudience.client => await _clientDrafts(),
      NotificationAudience.technician => await _technicianDrafts(),
    };

    // Stamp anything this device has not seen before.
    final Map<String, int>? stored = await _prefs.notificationObservedTimes(uid);
    final bool firstRun = stored == null;
    final Map<String, int> observed = Map<String, int>.of(
      stored ?? <String, int>{},
    );
    final int now = DateTime.now().millisecondsSinceEpoch;
    bool changed = false;
    for (final _Draft d in drafts) {
      if (d.knownTime != null || observed.containsKey(d.id)) continue;
      observed[d.id] = firstRun
          ? (d.fallbackTime ?? DateTime.now()).millisecondsSinceEpoch
          : now;
      changed = true;
    }
    if (changed) await _prefs.saveNotificationObservedTimes(uid, observed);

    final Set<String> seen = await _prefs.seenNotifications(uid);
    if (firstRun && drafts.isNotEmpty) {
      await _prefs.markNotificationsSeen(uid, drafts.map((_Draft d) => d.id));
      seen.addAll(drafts.map((_Draft d) => d.id));
    }

    final List<AppNotification> items = <AppNotification>[
      for (final _Draft d in drafts)
        d.build(
          at:
              d.knownTime ??
              DateTime.fromMillisecondsSinceEpoch(observed[d.id] ?? now),
          unread: !seen.contains(d.id),
        ),
      ..._messageItems(threads),
    ];

    final Set<NotificationCategory> muted = await _muted(uid);
    final DateTime cutoff = DateTime.now().subtract(_history);

    return items
        .where((AppNotification n) => !muted.contains(n.category))
        .where((AppNotification n) => n.unread || n.at.isAfter(cutoff))
        .toList()
      ..sort((AppNotification a, AppNotification b) => b.at.compareTo(a.at));
  }

  /// How many unread items the bell should show. Never throws: a badge is
  /// decoration and must not put an error over the dashboard.
  Future<int> unreadCount() async {
    try {
      final List<AppNotification> all = await load();
      return all.where((AppNotification n) => n.unread).length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> markSeen(Iterable<AppNotification> items) async {
    final String? uid = _uid();
    if (uid == null) return;
    // Chat items are cleared by opening the thread, which writes `read_at` on
    // the server - marking them here would only hide them on this phone.
    await _prefs.markNotificationsSeen(
      uid,
      items
          .where((AppNotification n) => n.category != NotificationCategory.messages)
          .map((AppNotification n) => n.id),
    );
  }

  Future<Set<NotificationCategory>> _muted(String uid) async {
    final Set<NotificationCategory> muted = <NotificationCategory>{};
    for (final NotificationCategory c in NotificationCategory.values) {
      if (!await _prefs.notificationEnabled(uid, c.name)) muted.add(c);
    }
    return muted;
  }

  // ------------------------------------------------------------- sources

  /// The client's bookings, the people on them, and their live tracking.
  Future<List<_Draft>> _clientDrafts() async {
    final (List<Job> jobs, Map<String, JobTechnician> people) = await (
      _jobs.myJobs(),
      _jobs.bookedTechnicians(),
    ).wait;

    final Map<String, JobTracking> tracking = await _trackingFor(jobs);

    return <_Draft>[
      for (final Job job in jobs) ..._jobItems(job, people[job.id]),
      for (final Job job in jobs)
        if (tracking[job.id] != null) ..._trackingItems(job, tracking[job.id]!),
    ];
  }

  /// Work arriving, and what the client has asked for on the work in hand.
  ///
  /// Never fatal in either half: a technician whose offers fail to load
  /// should still see their messages, and vice versa. The dashboard is the
  /// authoritative list of requests - this is the record of them arriving.
  Future<List<_Draft>> _technicianDrafts() async {
    final (List<MatchResult> offers, List<Job> live) = await (
      _technician.incomingOffers().catchError(
        (Object _) => const <MatchResult>[],
      ),
      _technician.activeJobs().catchError((Object _) => const <Job>[]),
    ).wait;

    return <_Draft>[
      for (final MatchResult offer in offers) _offerItem(offer),
      ...await _returnChoiceItems(live),
    ];
  }

  Future<Map<String, JobTracking>> _trackingFor(List<Job> jobs) async {
    final List<Job> travelling = jobs
        .where(
          (Job j) =>
              TrackingJourney.tracks(j.servicePath) &&
              (j.status == JobStatus.confirmed ||
                  j.status == JobStatus.inProgress),
        )
        .take(_maxTrackingLookups)
        .toList();

    final Map<String, JobTracking> out = <String, JobTracking>{};
    await Future.wait(<Future<void>>[
      for (final Job job in travelling)
        _tracking
            .fetch(job.id)
            .then((JobTracking? t) {
              if (t != null) out[job.id] = t;
            })
            .catchError((Object _) {}),
    ]);
    return out;
  }

  // ------------------------------------------------------------- builders

  static String _device(Job job) => job.deviceType.label.split(' /').first;

  List<_Draft> _jobItems(Job job, JobTechnician? who) {
    final String device = _device(job);
    final String? name = who?.firstName;

    switch (job.status) {
      case JobStatus.pending:
        return <_Draft>[
          _Draft(
            id: 'job:${job.id}:pending',
            category: NotificationCategory.booking,
            title: 'Request submitted',
            body: 'We are finding the best technicians for your $device.',
            icon: Icons.send_rounded,
            tone: SugoTone.info,
            jobId: job.id,
            knownTime: job.createdAt,
          ),
        ];
      case JobStatus.matched:
        if (who != null && who.status == MatchStatus.offered) {
          return <_Draft>[
            _Draft(
              id: 'job:${job.id}:offered:${who.technicianId}',
              category: NotificationCategory.booking,
              title: 'Request sent to ${who.firstName}',
              body: 'Waiting for them to accept your ${job.symptomLabel.toLowerCase()} job.',
              icon: Icons.hourglass_top_rounded,
              tone: SugoTone.warning,
              jobId: job.id,
              knownTime: who.matchedAt,
            ),
          ];
        }
        if (who != null && who.status == MatchStatus.declined) {
          return <_Draft>[
            _Draft(
              id: 'job:${job.id}:declined:${who.technicianId}',
              category: NotificationCategory.booking,
              title: '${who.firstName} could not take this job',
              body: 'Your other matches are still ready. Choose another technician.',
              icon: Icons.person_off_rounded,
              tone: SugoTone.danger,
              jobId: job.id,
              fallbackTime: job.createdAt,
            ),
          ];
        }
        return <_Draft>[
          _Draft(
            id: 'job:${job.id}:matched',
            category: NotificationCategory.booking,
            // No count: the feed is derived from the job row, which does not
            // say how many matches were written, and "3" would be a guess on
            // the day the engine could only find two.
            title: 'We found technicians who match your request',
            body: 'See who we recommend for your $device, and why.',
            icon: Icons.workspace_premium_rounded,
            tone: SugoTone.brand,
            jobId: job.id,
            fallbackTime: job.createdAt,
          ),
        ];
      case JobStatus.confirmed:
        return <_Draft>[
          _Draft(
            id: 'job:${job.id}:confirmed',
            category: NotificationCategory.booking,
            title: name == null
                ? 'Booking accepted'
                : '$name accepted your booking',
            body: job.title,
            icon: Icons.check_circle_rounded,
            tone: SugoTone.success,
            jobId: job.id,
            fallbackTime: job.createdAt,
          ),
        ];
      case JobStatus.inProgress:
        return <_Draft>[
          _Draft(
            id: 'job:${job.id}:in_progress',
            category: NotificationCategory.service,
            title: 'Service in progress',
            body: name == null
                ? 'Work has started on your $device.'
                : '$name has started work on your $device.',
            icon: Icons.build_rounded,
            tone: SugoTone.accent,
            jobId: job.id,
            fallbackTime: job.createdAt,
          ),
        ];
      case JobStatus.completed:
        return <_Draft>[
          _Draft(
            id: 'job:${job.id}:completed',
            category: NotificationCategory.service,
            title: 'Service completed',
            body: name == null
                ? 'Your $device repair is done. Tap to rate it.'
                : 'How did $name do? Tap to rate the repair.',
            icon: Icons.verified_rounded,
            tone: SugoTone.success,
            jobId: job.id,
            fallbackTime: job.createdAt,
          ),
        ];
      case JobStatus.cancelled:
        return <_Draft>[
          _Draft(
            id: 'job:${job.id}:cancelled',
            category: NotificationCategory.booking,
            title: 'Booking cancelled',
            body: job.title,
            icon: Icons.cancel_rounded,
            tone: SugoTone.neutral,
            jobId: job.id,
            fallbackTime: job.createdAt,
          ),
        ];
    }
  }

  /// "A client booked you." The in-app counterpart of the push `job-response`
  /// already sends when a client picks this technician.
  _Draft _offerItem(MatchResult offer) {
    final JobSnapshot? job = offer.job;
    final String device = (job?.deviceType.label ?? 'repair')
        .split(' /')
        .first
        .toLowerCase();

    return _Draft(
      id: 'offer:${offer.id}',
      category: NotificationCategory.booking,
      title: 'New job request',
      body: job == null
          ? 'A client has asked you to take a job. Open it to see the task.'
          : 'A client picked you for a $device repair — '
                '${job.symptomLabel.toLowerCase()}, ${job.budgetLabel}.',
      icon: Icons.inbox_rounded,
      tone: SugoTone.brand,
      jobId: offer.jobId,
      // Where the request actually lives: the offer card. There is no booking
      // screen to open until they accept.
      action: NotificationAction.openOffers,
      knownTime: offer.createdAt,
    );
  }

  /// "They will collect it" / "They want it delivered."
  ///
  /// The client makes this call on their own tracking screen and the
  /// technician carries it out, so being told is the whole of their part in
  /// it. A push goes out at the moment of the choice; this is where it can
  /// still be found afterwards.
  Future<List<_Draft>> _returnChoiceItems(List<Job> live) async {
    final List<Job> pickups = live
        .where((Job j) => j.servicePath == ServicePath.pickup)
        .take(_maxTrackingLookups)
        .toList();

    if (pickups.isEmpty) return const <_Draft>[];

    final Map<String, ReturnMethod> choices = await _tracking
        .returnMethods(pickups.map((Job j) => j.id).toList())
        .catchError((Object _) => const <String, ReturnMethod>{});

    return <_Draft>[
      for (final Job job in pickups)
        if (choices[job.id] case final ReturnMethod method)
          _Draft(
            id: 'return:${job.id}:${method.wire}',
            category: NotificationCategory.service,
            title: method == ReturnMethod.clientPickup
                ? 'The client will collect it'
                : 'The client wants it delivered',
            body: method == ReturnMethod.clientPickup
                ? 'No delivery trip for ${_device(job).toLowerCase()} — mark '
                      'it ready for collection when it is fixed.'
                : 'Take the ${_device(job).toLowerCase()} back to them once '
                      'the repair is done.',
            icon: method == ReturnMethod.clientPickup
                ? Icons.storefront_rounded
                : Icons.delivery_dining_rounded,
            tone: SugoTone.info,
            jobId: job.id,
            action: NotificationAction.openTracking,
            fallbackTime: job.createdAt,
          ),
    ];
  }

  List<_Draft> _trackingItems(Job job, JobTracking t) {
    final String device = _device(job).toLowerCase();
    final TrackingJourney journey = TrackingJourney.of(job.servicePath);
    final String title = switch (t.stage) {
      TrackingStage.headingToPickup => 'Technician is on the way',
      TrackingStage.collected => 'Your $device was collected',
      TrackingStage.returningToShop => 'Heading to the workshop',
      TrackingStage.inRepair when journey == TrackingJourney.homeVisit =>
        'Your technician has arrived',
      TrackingStage.inRepair => 'Repair started at the workshop',
      TrackingStage.outForDelivery => 'Out for delivery',
      TrackingStage.readyForCollection => 'Ready for collection',
      TrackingStage.delivered => 'Delivered',
    };

    return <_Draft>[
      _Draft(
        id: 'track:${job.id}:${t.stage.wire}',
        category: NotificationCategory.tracking,
        title: title,
        body: t.stage.blurbOn(journey),
        icon: t.stage.icon,
        tone: t.stage.isFinished ? SugoTone.success : SugoTone.info,
        jobId: job.id,
        action: t.stage.showsMap
            ? NotificationAction.openTracking
            : NotificationAction.openJob,
        // `started_at` for the first leg, when the trip itself began; later
        // stages fall back to the moment this device noticed them, because
        // `updated_at` moves with every position fix and would make an hour-old
        // stage look like it happened a second ago.
        knownTime: t.stage == TrackingStage.headingToPickup ? t.startedAt : null,
        fallbackTime: t.startedAt,
      ),
      if (t.isDelayed)
        _Draft(
          id: 'delay:${job.id}:${t.stage.wire}',
          category: NotificationCategory.tracking,
          title: 'Running ${t.delayLabel ?? 'late'}',
          body: t.delayReasonLabel == null
              ? 'Your technician is behind the original estimate.'
              : 'Delayed by ${t.delayReasonLabel}.',
          icon: Icons.schedule_rounded,
          tone: SugoTone.warning,
          jobId: job.id,
          action: NotificationAction.openTracking,
          knownTime: t.etaSampledAt,
        ),
    ];
  }

  List<AppNotification> _messageItems(List<Conversation> threads) {
    return <AppNotification>[
      for (final Conversation c in threads)
        if (c.hasUnread && c.lastMessageAt != null)
          AppNotification(
            id: 'msg:${c.jobId}:${c.lastMessageAt!.millisecondsSinceEpoch}',
            category: NotificationCategory.messages,
            title: c.unreadCount > 1
                ? '${c.unreadCount} new messages from ${_first(c.counterpartName)}'
                : 'New message from ${_first(c.counterpartName)}',
            body: c.preview,
            at: c.lastMessageAt!,
            icon: Icons.chat_bubble_rounded,
            tone: SugoTone.info,
            action: NotificationAction.openChat,
            jobId: c.jobId,
            unread: true,
            counterpartName: c.counterpartName,
            counterpartAvatarUrl: c.counterpartAvatarUrl,
          ),
    ];
  }

  static String _first(String name) => name.trim().split(RegExp(r'\s+')).first;
}

/// A notification before its time and read state are resolved.
class _Draft {
  const _Draft({
    required this.id,
    required this.category,
    required this.title,
    required this.body,
    required this.icon,
    required this.tone,
    this.jobId,
    this.knownTime,
    this.fallbackTime,
    this.action = NotificationAction.openJob,
  });

  final String id;
  final NotificationCategory category;
  final String title;
  final String body;
  final IconData icon;
  final SugoTone tone;
  final String? jobId;
  final NotificationAction action;

  /// A time the database actually recorded for this event.
  final DateTime? knownTime;

  /// Used only on a first run, to backdate an item instead of calling it new.
  final DateTime? fallbackTime;

  AppNotification build({required DateTime at, required bool unread}) =>
      AppNotification(
        id: id,
        category: category,
        title: title,
        body: body,
        at: at,
        icon: icon,
        tone: tone,
        action: action,
        jobId: jobId,
        unread: unread,
      );
}
