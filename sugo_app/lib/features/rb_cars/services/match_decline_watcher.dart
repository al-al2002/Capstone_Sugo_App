import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../models/job.dart';
import '../models/job_enums.dart';
import '../models/match_result.dart';
import 'rb_cars_service.dart';

/// A technician declined one of the client's requests.
@immutable
class DeclineNotice {
  const DeclineNotice({required this.jobId, this.technicianName});

  final String jobId;

  /// From the declined match's technician snapshot, when it has one.
  final String? technicianName;
}

/// Whether a match that just turned `declined` was a technician declining -
/// read from how the job looks once the server has finished (2026-11-23).
///
/// Three things mark an offer `declined` (see `job-response`):
///
/// * **The technician declines** - the job is still open and nobody holds a
///   live offer. Announce it.
/// * **The client picked someone else** while one was pending: the old offer
///   is retired, and the new one is now `offered`. Their own doing - silent.
/// * **Someone accepted**: the job is confirmed and the others close. Silent.
///
/// An urgent request that timed out also lands here; the sweep offers the
/// next technician at once, so it has a live offer too and stays silent - the
/// client is told by the urgent message instead.
bool isTechnicianDecline(Job? job, List<MatchResult> matches) {
  if (job == null) return false;
  if (job.status != JobStatus.pending && job.status != JobStatus.matched) {
    return false;
  }
  return !matches.any(
    (MatchResult m) => m.isAwaitingTechnician || m.isAccepted,
  );
}

/// Hears a technician decline while the client's app is open, with no push
/// needed (2026-11-23).
///
/// ## Why it exists
///
/// The decline pop-up was raised only by the decline push, and the user saw
/// it never appear: no device had a push token, and the web build has no
/// Firebase messaging at all. This watches `job_matches` over Supabase
/// Realtime instead (migration 20261123000003 added the table to the
/// publication), the way chat and live tracking already work. RLS means a
/// client is only ever sent changes to matches on their own jobs.
///
/// ## How
///
/// Every update that leaves a match `declined` arrives here. The watcher
/// waits a moment ([settle]) for the server to finish what the decline set
/// off - retiring, re-matching, an urgent hand-on - then reads the job and
/// its matches back and announces only a real technician decline
/// ([isTechnicianDecline]). Several declines on one job at once (an accept
/// closes the rest) are checked once.
///
/// It never throws: a missed announcement is the worst outcome, and the
/// client's request still shows its state on the dashboard.
class MatchDeclineWatcher {
  MatchDeclineWatcher({
    SupabaseClient? client,
    RbCarsService? service,
    this.settle = const Duration(milliseconds: 1500),
  }) : _injected = client,
       _service = service ?? RbCarsService();

  final SupabaseClient? _injected;
  final RbCarsService _service;

  /// How long to let the server finish before reading the job back.
  final Duration settle;

  SupabaseClient get _client => _injected ?? SupabaseService.client;

  final StreamController<DeclineNotice> _notices =
      StreamController<DeclineNotice>.broadcast();

  /// Real technician declines, one per decline.
  Stream<DeclineNotice> get notices => _notices.stream;

  RealtimeChannel? _channel;

  /// Jobs being checked right now, so a burst of declines is checked once.
  final Set<String> _checking = <String>{};

  /// Starts listening. Safe to call more than once, and without a session.
  void start() {
    if (_channel != null) return;
    try {
      final String? uid = _client.auth.currentUser?.id;
      if (uid == null) return;
      _channel = _client
          .channel('match-declines:$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'job_matches',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'status',
              value: 'declined',
            ),
            callback: (PostgresChangePayload payload) =>
                onDeclined(payload.newRecord),
          )
          .subscribe();
    } catch (error) {
      debugPrint('MatchDeclineWatcher.start failed: $error');
    }
  }

  /// A match row that has just become `declined`. Public for tests.
  @visibleForTesting
  void onDeclined(Map<String, dynamic> row) {
    final Object? jobId = row['job_id'];
    if (jobId is! String || !_checking.add(jobId)) return;

    String? name;
    try {
      name = MatchResult.fromJson(row).technician?.displayName;
    } catch (_) {
      // No snapshot: the pop-up says "Your technician".
    }

    unawaited(_check(jobId, name));
  }

  Future<void> _check(String jobId, String? name) async {
    try {
      await Future<void>.delayed(settle);
      final Job? job = await _service.jobById(jobId);
      final List<MatchResult> matches = await _service.fetchMatches(jobId);
      if (isTechnicianDecline(job, matches) && !_notices.isClosed) {
        _notices.add(DeclineNotice(jobId: jobId, technicianName: name));
      }
    } catch (error) {
      debugPrint('MatchDeclineWatcher check failed: $error');
    } finally {
      _checking.remove(jobId);
    }
  }

  Future<void> dispose() async {
    final RealtimeChannel? open = _channel;
    _channel = null;
    if (open != null) {
      try {
        await _client.removeChannel(open);
      } catch (_) {}
    }
    await _notices.close();
  }
}
