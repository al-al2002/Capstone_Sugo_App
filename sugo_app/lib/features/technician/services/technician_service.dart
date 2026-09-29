import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../rb_cars/models/job.dart';
import '../../rb_cars/models/job_enums.dart';
import '../../rb_cars/models/match_result.dart';
import '../../rb_cars/models/technician.dart';
import '../../rb_cars/services/rb_cars_service.dart';

/// Everything the technician dashboard reads.
///
/// ## What goes direct and what does not
///
/// All the reads here are plain PostgREST, because an RLS policy already
/// expresses each rule:
///
/// * own `technicians` row - `technicians_select_own`
/// * offers made to them - `job_matches_technician_select`
/// * jobs assigned to them - `jobs_technician_select_assigned`
/// * their own outcomes - `job_outcomes_technician_select`
///
/// Nothing here writes directly. The one direct write there used to be - the
/// online/offline toggle - was retired on 2026-09-22 in favour of vacation days
/// (`TimeOffService`). Accept, decline and complete go through the
/// `job-response` edge function, since those write tables with no write policy
/// at all.
class TechnicianService {
  TechnicianService({SupabaseClient? client, RbCarsService? rbCars})
    : _client = client ?? SupabaseService.client,
      _rbCars = rbCars ?? RbCarsService();

  final SupabaseClient _client;
  final RbCarsService _rbCars;

  String get _uid {
    final String? id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const RbCarsFailure('Please sign in again to continue.');
    }
    return id;
  }

  /// The signed-in technician's own row, joined to their profile.
  Future<Technician?> me() async {
    try {
      final Map<String, dynamic>? row = await _client
          .from('technicians')
          .select('*, profiles!inner(full_name, avatar_url, phone)')
          .eq('id', _uid)
          .maybeSingle();

      return row == null ? null : Technician.fromJson(row);
    } on PostgrestException catch (error) {
      _log('me', error);
      throw const RbCarsFailure('Could not load your technician profile.');
    }
  }

  /// Offers currently awaiting this technician's answer, best rank first.
  ///
  /// `status = 'offered'` is the load-bearing filter here. A match becomes
  /// `offered` only when the CLIENT selects this technician - the engine writes
  /// its Top 3 as `shortlisted`, which never reaches this query. That is what
  /// keeps the dashboard to jobs someone actually booked them for, rather than
  /// every job they happened to rank well on.
  ///
  /// It is enforced twice on purpose: this WHERE clause, and the
  /// `job_matches_technician_select` policy, which excludes `shortlisted` rows
  /// outright so a mistake here cannot leak the shortlist.
  ///
  /// The job behind each offer comes from `score_breakdown.job`, not from the
  /// `jobs` table: they are not assigned yet, so RLS hides the row until they
  /// accept.
  Future<List<MatchResult>> incomingOffers() async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('job_matches')
          .select()
          .eq('technician_id', _uid)
          .eq('status', 'offered')
          .order('rank', ascending: true)
          .order('created_at', ascending: false);

      return rows.map(MatchResult.fromJson).toList(growable: false);
    } on PostgrestException catch (error) {
      _log('incomingOffers', error);
      throw const RbCarsFailure('Could not load your job requests.');
    }
  }

  /// Jobs assigned to this technician that are not finished yet.
  Future<List<Job>> activeJobs() async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('jobs')
          .select()
          .eq('assigned_technician_id', _uid)
          .inFilter('status', <String>[
            JobStatus.confirmed.wire,
            JobStatus.inProgress.wire,
          ])
          .order('created_at', ascending: false);

      return rows.map(Job.fromJson).toList(growable: false);
    } on PostgrestException catch (error) {
      _log('activeJobs', error);
      throw const RbCarsFailure('Could not load your active jobs.');
    }
  }

  /// Every job assigned to this technician, in any state, newest first.
  ///
  /// The Jobs tab used [activeJobs], which only returns `confirmed` and
  /// `in_progress` - so its Completed and Cancelled filters could never show a
  /// single row. A technician looking for last week's finished repair found an
  /// empty tab with "Jobs you finish will be listed here". This is the list
  /// that tab needs; [activeJobs] stays for the dashboard, which really does
  /// want only what is live.
  Future<List<Job>> assignedJobs() async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('jobs')
          .select()
          .eq('assigned_technician_id', _uid)
          .order('created_at', ascending: false);

      return rows.map(Job.fromJson).toList(growable: false);
    } on PostgrestException catch (error) {
      _log('assignedJobs', error);
      throw const RbCarsFailure('Could not load your jobs.');
    }
  }

  /// Completed outcomes, newest first. Feeds both the reviews strip and the
  /// earnings estimate.
  Future<List<TechnicianOutcome>> recentOutcomes({int limit = 20}) async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('job_outcomes')
          .select()
          .eq('technician_id', _uid)
          .order('created_at', ascending: false)
          .limit(limit);

      return rows.map(TechnicianOutcome.fromJson).toList(growable: false);
    } on PostgrestException catch (error) {
      _log('recentOutcomes', error);
      throw const RbCarsFailure('Could not load your recent jobs.');
    }
  }

  /// Accept an offer and fix it on site.
  Future<JobResponseOutcome> accept(String matchId) =>
      _rbCars.acceptOffer(matchId);

  /// Accept, but the unit has to go to the shop.
  ///
  /// Unreachable from the UI now - see [markNeedsShop].
  Future<JobResponseOutcome> reroute(String matchId) =>
      _rbCars.rerouteOffer(matchId);

  /// On site, and it cannot be fixed here: send the unit to the workshop.
  Future<JobResponseOutcome> markNeedsShop(String jobId) =>
      _rbCars.markNeedsShop(jobId);

  /// Decline, cascading the offer to the next rank.
  Future<JobResponseOutcome> decline(String matchId) =>
      _rbCars.declineOffer(matchId);

  /// Close a job and write the `job_outcomes` row that Stage 1 learns from.
  Future<JobResponseOutcome> complete(
    String jobId, {
    required bool diagnosisCorrect,
    bool reroutedMidJob = false,
  }) {
    return _rbCars.completeJob(
      jobId,
      diagnosisCorrect: diagnosisCorrect,
      reroutedMidJob: reroutedMidJob,
    );
  }

  void _log(String action, Object error) {
    if (kDebugMode) debugPrint('TechnicianService.$action failed: $error');
  }
}

/// One `job_outcomes` row as the technician sees it.
class TechnicianOutcome {
  const TechnicianOutcome({
    required this.id,
    required this.jobId,
    this.diagnosisCorrect,
    this.reroutedMidJob = false,
    this.finalRating,
    this.createdAt,
  });

  factory TechnicianOutcome.fromJson(Map<String, dynamic> json) {
    final Object? rating = json['final_rating'];
    return TechnicianOutcome(
      id: json['id'] as String,
      jobId: json['job_id'] as String,
      diagnosisCorrect: json['diagnosis_correct'] as bool?,
      reroutedMidJob: json['rerouted_mid_job'] as bool? ?? false,
      finalRating: rating is num
          ? rating.toDouble()
          : (rating is String ? double.tryParse(rating) : null),
      createdAt: json['created_at'] is String
          ? DateTime.tryParse(json['created_at'] as String)?.toLocal()
          : null,
    );
  }

  final String id;
  final String jobId;
  final bool? diagnosisCorrect;
  final bool reroutedMidJob;
  final double? finalRating;
  final DateTime? createdAt;

  bool get isRated => finalRating != null && finalRating! > 0;
}
