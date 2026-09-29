import 'package:flutter/foundation.dart';

import '../../rb_cars/models/job.dart';
import '../../rb_cars/models/match_result.dart';
import '../../rb_cars/models/technician.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../models/time_off.dart';
import '../services/technician_service.dart';
import '../services/time_off_service.dart';

/// State for the technician dashboard: profile, offers, active job, history.
///
/// Loads all four in parallel because none depends on another, so the dashboard
/// paints in one round trip's worth of time rather than four.
class TechnicianDashboardProvider extends ChangeNotifier {
  TechnicianDashboardProvider({
    TechnicianService? service,
    TimeOffService? timeOff,
  }) : _service = service ?? TechnicianService(),
       _timeOff = timeOff ?? TimeOffService();

  final TechnicianService _service;
  final TimeOffService _timeOff;

  TimeOff? _currentVacation;

  Technician? _technician;
  List<MatchResult> _offers = <MatchResult>[];
  List<Job> _activeJobs = <Job>[];
  List<TechnicianOutcome> _outcomes = <TechnicianOutcome>[];

  bool _isLoading = true;
  bool _isBusy = false;
  String? _error;
  String? _notice;

  Technician? get technician => _technician;
  List<MatchResult> get offers => _offers;
  List<Job> get activeJobs => _activeJobs;
  List<TechnicianOutcome> get outcomes => _outcomes;

  bool get isLoading => _isLoading;

  /// True while an accept, decline or complete is in flight. Buttons disable on
  /// this so a double tap cannot answer the same offer twice.
  bool get isBusy => _isBusy;

  String? get error => _error;
  String? get notice => _notice;

  /// The vacation covering today, or null when they are working.
  ///
  /// Replaced the online/offline switch on 2026-09-22. Set, ended and edited
  /// from the dashboard's availability card or the Profile tab.
  TimeOff? get currentVacation => _currentVacation;

  /// Last day of [currentVacation], or null when working.
  DateTime? get awayUntil => _currentVacation?.endsOn;

  /// For the dashboard's vacation actions, so they write through the same
  /// service this provider reads from.
  TimeOffService get timeOff => _timeOff;

  Job? get currentJob => _activeJobs.isEmpty ? null : _activeJobs.first;

  // ------------------------------------------------------------- stat cards

  /// Outcomes recorded in the last seven days.
  int get jobsThisWeek {
    final DateTime cutoff = DateTime.now().subtract(const Duration(days: 7));
    return _outcomes
        .where(
          (TechnicianOutcome o) =>
              o.createdAt != null && o.createdAt!.isAfter(cutoff),
        )
        .length;
  }

  int get jobsToday {
    final DateTime now = DateTime.now();
    return _outcomes.where((TechnicianOutcome o) {
      final DateTime? at = o.createdAt;
      if (at == null) return false;
      return at.year == now.year && at.month == now.month && at.day == now.day;
    }).length;
  }

  /// **Estimated**, not actual, earnings.
  ///
  /// The RB-CARS schema records no payment: `job_outcomes` has a rating, a
  /// diagnosis verdict and a reroute flag, and nothing about money. So this
  /// multiplies completed jobs by the tier's published hourly band times a
  /// typical job length - the same arithmetic Stage 2 uses for budget fit.
  ///
  /// The UI labels it "estimated" for that reason. Real figures would need a
  /// payments table, which is outside this capstone's scope.
  int get estimatedEarningsToday => jobsToday * _perJobEstimate;

  int get estimatedEarningsWeek => jobsThisWeek * _perJobEstimate;

  int get _perJobEstimate {
    final Technician? tech = _technician;
    if (tech == null) return 0;
    // Midpoint of the typical two-to-four hour band.
    return tech.indicativeHourlyFee * 3;
  }

  double get rating => _technician?.rating ?? 0;

  /// Outcomes that carry a client rating, newest first.
  List<TechnicianOutcome> get ratedOutcomes => _outcomes
      .where((TechnicianOutcome o) => o.isRated)
      .toList(growable: false);

  // ------------------------------------------------------------------ loads

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final List<Object?> results = await Future.wait(<Future<Object?>>[
        _service.me(),
        _service.incomingOffers(),
        _service.activeJobs(),
        _service.recentOutcomes(),
        _vacationToday(),
      ]);

      _technician = results[0] as Technician?;
      _offers = results[1] as List<MatchResult>;
      _activeJobs = results[2] as List<Job>;
      _outcomes = results[3] as List<TechnicianOutcome>;
      _currentVacation = results[4] as TimeOff?;
    } on RbCarsFailure catch (failure) {
      _error = failure.message;
    } catch (_) {
      _error = 'Could not load your dashboard. Pull down to retry.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load();

  /// Never fatal: a dashboard that cannot tell whether they are away should
  /// still show their offers and jobs.
  Future<TimeOff?> _vacationToday() async {
    try {
      final DateTime now = DateTime.now();
      for (final TimeOff period in await _timeOff.upcoming()) {
        if (period.isCurrent(now)) return period;
      }
      return null;
    } on RbCarsFailure {
      return null;
    }
  }

  // ---------------------------------------------------------------- actions

  Future<bool> acceptOffer(String matchId) =>
      _act(() => _service.accept(matchId), 'Job accepted. It is yours.');

  Future<bool> rerouteOffer(String matchId) => _act(
    () => _service.reroute(matchId),
    'Accepted as a shop pickup. The client has been told.',
  );

  /// The unit has to go to the workshop after all. Reloads afterwards so the
  /// active card picks up its new service path and the tracking controls.
  Future<bool> markNeedsShop(String jobId) => _act(
    () => _service.markNeedsShop(jobId),
    'Switched to shop pickup. The client can now track their appliance.',
  );

  Future<bool> declineOffer(String matchId) => _act(
    () => _service.decline(matchId),
    'Declined. It has moved to the next technician.',
  );

  /// Closes a job. `diagnosisCorrect` and `reroutedMidJob` are the two signals
  /// that feed back into Stage 1 scoring, which is why the UI asks for them
  /// rather than defaulting them.
  Future<bool> completeJob(
    String jobId, {
    required bool diagnosisCorrect,
    bool reroutedMidJob = false,
  }) {
    return _act(
      () => _service.complete(
        jobId,
        diagnosisCorrect: diagnosisCorrect,
        reroutedMidJob: reroutedMidJob,
      ),
      'Job completed. The client can now rate it.',
    );
  }

  Future<bool> _act(
    Future<JobResponseOutcome> Function() action,
    String successNotice,
  ) async {
    if (_isBusy) return false;

    _isBusy = true;
    _error = null;
    _notice = null;
    notifyListeners();

    try {
      await action();
      _notice = successNotice;
      // Re-read rather than mutating locally: an accept retires the other
      // offers, a decline may promote a different one, and a completion moves
      // counters. Local edits would drift from the server.
      await load();
      return true;
    } on RbCarsFailure catch (failure) {
      _error = failure.message;
      return false;
    } catch (_) {
      _error = 'Could not complete that action. Please try again.';
      return false;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
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
