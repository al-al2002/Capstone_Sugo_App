import 'package:flutter/foundation.dart';

import '../models/job.dart';
import '../models/match_result.dart';
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
  }) : _service = service ?? RbCarsService(),
       _notice = initialNotice;

  final String jobId;
  final RbCarsService _service;

  List<MatchResult> _matches = <MatchResult>[];
  List<ConsideredTechnician> _considered = <ConsideredTechnician>[];
  Job? _job;
  bool _isLoading = false;
  bool _isMatching = false;
  bool _isResponding = false;
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
  String? get error => _error;

  /// Transient message after an action, e.g. "Rank 1 declined, showing rank 2".
  String? get notice => _notice;

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
  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _job = await _service.jobById(jobId);
      _matches = await _service.fetchMatches(jobId);
    } on RbCarsFailure catch (failure) {
      _error = failure.message;
    } catch (_) {
      _error = 'Could not load your matches. Pull to retry.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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
  Future<bool> selectTechnician(String matchId) => _respond(
    () => _service.selectTechnician(matchId),
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

      // Always re-read: a decline may have promoted rank 2, or triggered a
      // whole new Top 3. Trusting local state here would show a stale list.
      _matches = await _service.fetchMatches(jobId);
      _job = await _service.jobById(jobId);

      _notice = successNotice ?? _noticeForDecline(outcome);
      return true;
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
