import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/job.dart';
import '../models/job_enums.dart';
import '../models/match_result.dart';
import '../models/technician_preferences.dart';
import '../services/rb_cars_service.dart';

/// Holds the Top 3 for one job, and drives accept / decline / reroute.
///
/// Used by both sides of the handover: the client review screen reads
/// [matches] to show the ranked options, and the technician confirmation
/// screen calls [accept], [reroute] and [decline] on the offer made to them.
class MatchProvider extends ChangeNotifier {
  MatchProvider({
    required this.jobId,
    RbCarsService? service,
    String? initialNotice,
    bool? initialPreferencesBlocked,
    List<RelaxHint> initialRelaxHints = const <RelaxHint>[],
  }) : _service = service ?? RbCarsService(),
       _notice = initialNotice,
       _preferencesBlocked = initialPreferencesBlocked,
       _relaxHints = initialRelaxHints;

  final String jobId;
  final RbCarsService _service;

  /// How long each read in [load] may take before it is a connection problem.
  static const Duration loadTimeout = Duration(seconds: 20);

  List<MatchResult> _matches = <MatchResult>[];
  List<ConsideredTechnician> _considered = <ConsideredTechnician>[];
  Job? _job;
  bool _isLoading = false;
  bool _isMatching = false;
  bool _isResponding = false;
  bool _isCheckingTechnician = false;
  String? _error;

  /// Seeded from the posting flow when the first run found nobody, so the
  /// reason survives the hop to this screen.
  String? _notice;

  List<MatchResult> get matches => _matches;

  /// The full ranking from the most recent run, offers and non-offers alike.
  ///
  /// Empty until a run happens on this screen: it lives only in the matching
  /// function's response, never in the database, so a plain [load] cannot
  /// recover it.
  List<ConsideredTechnician> get considered => _considered;

  Job? get job => _job;
  bool get isLoading => _isLoading;

  /// True while RB-CARS itself is running again ([rematch]), as opposed to
  /// [load] reading results that already exist. Only the first is analysis,
  /// so only the first gets the analysis screen.
  bool get isMatching => _isMatching;
  bool get isResponding => _isResponding;

  /// True while asking whether a technician is on another job, before the
  /// client is shown the request dialog.
  bool get isCheckingTechnician => _isCheckingTechnician;

  /// Whether the technician behind [matchId] is on another job right now.
  /// See `RbCarsService.technicianIsBusy`.
  Future<bool> technicianBusy(String matchId) async =>
      (await technicianStatus(matchId)).busy;

  /// Busy or not, plus the distance to their shop for a shop repair - the
  /// one round trip the booking dialog waits on.
  Future<TechnicianStatus> technicianStatus(String matchId) async {
    _isCheckingTechnician = true;
    notifyListeners();
    try {
      return await _service.technicianStatus(matchId);
    } finally {
      _isCheckingTechnician = false;
      notifyListeners();
    }
  }

  String? get error => _error;

  DateTime? _bookingPausedUntil;

  /// When this client may book again, while the book-and-cancel cooldown
  /// (2026-11-17) is running: 2 cancels within an hour pause booking for 2
  /// minutes. Null when they may book now, including once the time passes.
  ///
  /// Learned on [load], and from the server's refusal if a booking is tried
  /// during a pause that started elsewhere (another phone, say). The screen
  /// counts down to it. The server enforces the pause either way.
  DateTime? get bookingPausedUntil {
    final DateTime? until = _bookingPausedUntil;
    return until != null && until.isAfter(DateTime.now()) ? until : null;
  }

  /// Re-reads the pause from the server. A failed check reads as "not
  /// paused" - it must never stop the matches from loading.
  Future<void> refreshBookingPause() async {
    DateTime? until;
    try {
      until = await _service.bookingPausedUntil();
    } catch (_) {
      until = null;
    }
    if (until == _bookingPausedUntil) return;
    _bookingPausedUntil = until;
    notifyListeners();
  }

  /// The countdown reached zero.
  void clearBookingPause() {
    if (_bookingPausedUntil == null) return;
    _bookingPausedUntil = null;
    notifyListeners();
  }

  /// Transient message after an action, e.g. "Rank 1 declined, showing rank 2".
  String? get notice => _notice;

  /// Whether the client's own preferences are what left this job with
  /// nobody. Null is "not known yet": opened from the dashboard rather than
  /// straight after a run, so [load] makes the best guess from the job.
  bool? _preferencesBlocked;

  List<RelaxHint> _relaxHints;

  /// Show "No technician matches your preferences - try relaxing them"
  /// rather than the plain empty state. Only while there is nothing to show
  /// and the job still has preferences that could be relaxed.
  bool get showRelaxPreferences =>
      isEmpty &&
      (_preferencesBlocked ?? false) &&
      (_job?.preferences.hasAny ?? false);

  /// For each preference, how many technicians removing only it brings back.
  /// Empty when the run that set [showRelaxPreferences] did not say.
  List<RelaxHint> get relaxHints => _relaxHints;

  bool get isEmpty => !_isLoading && _matches.isEmpty;

  /// Matches the client can still act on, best rank first: the shortlist plus
  /// any technician already requested and still deciding. See
  /// `RbCarsService.fetchLiveOffers` for why `shortlisted` belongs here.
  List<MatchResult> get liveOffers =>
      _matches.where((MatchResult m) => m.isOpen).toList(growable: false);

  /// The technician the client has requested, if they have chosen one and that
  /// technician has not answered yet. Drives the "waiting for X" state.
  MatchResult? get requestedMatch {
    for (final MatchResult match in _matches) {
      if (match.isAwaitingTechnician) return match;
    }
    return null;
  }

  MatchResult? get acceptedMatch {
    for (final MatchResult match in _matches) {
      if (match.isAccepted) return match;
    }
    return null;
  }

  /// Loads the job and its offers. Safe to call repeatedly.
  /// Deletes this job while nobody has taken it. The server re-checks that
  /// (`handleDeleteJob`) and refuses otherwise; the error is the caller's.
  Future<JobResponseOutcome> deleteJob() => _service.deleteJob(jobId);

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Time-limited (2026-11-23): a read that hangs on a bad connection
      // would otherwise hold the analysis screen up for ever.
      _job = await _service.jobById(jobId).timeout(loadTimeout);
      _matches = await _service.fetchMatches(jobId).timeout(loadTimeout);
      // Reopened from the dashboard, no run on this screen yet: a job with
      // preferences and nobody to show most likely has them to thank. If it
      // does not, the next run says so and this is corrected.
      _preferencesBlocked ??=
          _matches.isEmpty && (_job?.preferences.hasAny ?? false);
    } on TimeoutException {
      _error = 'Your connection is slow or offline. Pull down to try again.';
    } on RbCarsFailure catch (failure) {
      _error = failure.message;
    } catch (_) {
      _error = 'Could not load your matches. Pull to retry.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    // After the matches, and on its own: it never holds them up.
    await refreshBookingPause();
  }

  /// Re-runs RB-CARS for this job.
  ///
  /// [excludeDeclined] false is the "show me everyone" path: it scores the
  /// whole pool again with no exclusions, which is what fills [considered]
  /// with every technician rather than only those still in play.
  Future<void> rematch({bool excludeDeclined = true}) async {
    _isLoading = true;
    _isMatching = true;
    _error = null;
    _notice = null;
    notifyListeners();

    try {
      final List<String> declined = excludeDeclined
          ? _matches
                .where((MatchResult m) => m.isDeclined)
                .map((MatchResult m) => m.technicianId)
                .toList(growable: false)
          : const <String>[];

      final MatchingRun run = await _service.runMatching(
        jobId,
        excludeTechnicianIds: declined,
      );

      _matches = run.matches;
      _considered = run.considered;
      _job = await _service.jobById(jobId);
      _preferencesBlocked = run.matches.isEmpty && run.preferencesBlocked;
      _relaxHints = _preferencesBlocked! ? run.relaxHints : const <RelaxHint>[];

      // The engine says exactly which gate emptied the pool. Preferring its
      // message over our own guess is the difference between "nobody is
      // available" and "three were outside their own service radius".
      _notice = _matches.isEmpty
          ? run.message ??
                'No other technicians are available for this job right now.'
          : 'Found ${_matches.length} new option'
                '${_matches.length == 1 ? '' : 's'}, '
                '${run.evaluated} scored.';
    } on RbCarsFailure catch (failure) {
      _error = failure.message;
    } catch (_) {
      _error = 'Could not run the matcher again. Please try later.';
    } finally {
      _isLoading = false;
      _isMatching = false;
      notifyListeners();
    }
  }

  /// The client books this technician. Retires the other two offers and
  /// leaves the chosen one waiting for the technician's answer.
  /// Saves looser preferences on the job, then runs RB-CARS again.
  ///
  /// The way out of "No technician matches your preferences": each chip on
  /// that screen removes one preference, and "Clear all" passes
  /// [TechnicianPreferences.none]. Saved on the job rather than held here,
  /// so the decline cascade and any later run use the relaxed set too.
  Future<void> relaxPreferences(TechnicianPreferences next) async {
    if (_isLoading || _isResponding) return;

    _isLoading = true;
    _isMatching = true;
    _error = null;
    notifyListeners();

    try {
      _job = await _service.updatePreferences(jobId, next);
    } on RbCarsFailure catch (failure) {
      _error = failure.message;
      _isLoading = false;
      _isMatching = false;
      notifyListeners();
      return;
    } catch (_) {
      _error = 'Could not update your preferences. Please try again.';
      _isLoading = false;
      _isMatching = false;
      notifyListeners();
      return;
    }

    // Nothing was declined while there was nothing to show, so the plain
    // re-run is the right one.
    await rematch();
  }

  Future<bool> selectTechnician(
    String matchId, {
    DeliveryOption? deliveryOption,
  }) => _respond(
    () => _service.selectTechnician(matchId, deliveryOption: deliveryOption),
    'Request sent. Waiting for the technician to confirm.',
  );

  /// Technician accepts, and will fix it on site.
  Future<bool> accept(String matchId) =>
      _respond(() => _service.acceptOffer(matchId), 'Job confirmed.');

  /// Technician accepts but needs the unit in the shop. Switches the job to
  /// the pickup path.
  Future<bool> reroute(String matchId) => _respond(
    () => _service.rerouteOffer(matchId),
    'Job confirmed as a shop pickup.',
  );

  /// Technician declines. The backend promotes the next rank, or re-runs the
  /// matcher when all three are gone.
  Future<bool> decline(String matchId) async {
    return _respond(() => _service.declineOffer(matchId), null);
  }

  Future<bool> _respond(
    Future<JobResponseOutcome> Function() action,
    String? successNotice,
  ) async {
    if (_isResponding) return false;

    _isResponding = true;
    _error = null;
    _notice = null;
    notifyListeners();

    try {
      final JobResponseOutcome outcome = await action();

      // A decline that exhausted the shortlist re-runs the engine on the
      // server, with the job's preferences - which may be what left nobody.
      if (outcome.rematched) {
        _preferencesBlocked = outcome.preferencesBlocked;
        _relaxHints = const <RelaxHint>[];
      }

      // Always re-read: a decline may have promoted rank 2, or triggered a
      // whole new Top 3. Trusting local state here would show a stale list.
      _matches = await _service.fetchMatches(jobId);
      _job = await _service.jobById(jobId);

      _notice = successNotice ?? _noticeForDecline(outcome);
      return true;
    } on BookingPausedFailure catch (failure) {
      // The screen shows the countdown in place of a one-off error.
      _bookingPausedUntil = failure.until;
      return false;
    } on RbCarsFailure catch (failure) {
      _error = failure.message;
      return false;
    } catch (_) {
      _error = 'Could not record that response. Please try again.';
      return false;
    } finally {
      _isResponding = false;
      notifyListeners();
    }
  }

  String _noticeForDecline(JobResponseOutcome outcome) {
    // The job is no longer passed to rank 2 automatically - that would put it
    // on a dashboard the client never chose. It comes back to the client.
    if (outcome.awaitingClientReselect) {
      final int left = outcome.shortlistRemaining;
      return left == 1
          ? 'They turned it down. One other match is still available - pick '
                'them to send your request.'
          : 'They turned it down. $left other matches are still available - '
                'pick one to send your request.';
    }
    if (outcome.rematched) {
      return _matches.isEmpty
          ? 'No one from your matches took it, and nobody else is available '
                'right now.'
          : 'No one from your matches took it, so we ran a fresh match '
                'against the remaining technicians.';
    }
    return 'Offer declined.';
  }

  void clearNotice() {
    if (_notice == null) return;
    _notice = null;
    notifyListeners();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }
}
