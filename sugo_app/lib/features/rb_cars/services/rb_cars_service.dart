import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../models/job.dart';
import '../models/job_technician.dart';
import '../models/job_enums.dart';
import '../models/job_party.dart';
import '../models/json_utils.dart';
import '../models/match_result.dart';
import '../models/technician_profile_details.dart';

/// Raised when a job cannot be posted or matched. Carries copy that is safe to
/// show a user, so screens never surface a raw Postgres or Deno message.
class RbCarsFailure implements Exception {
  const RbCarsFailure(this.message, {this.detail});

  final String message;
  final Object? detail;

  @override
  String toString() => 'RbCarsFailure($message)';
}

/// The Flutter side of RB-CARS.
///
/// ## Which calls go direct, and which go through an edge function
///
/// Direct PostgREST is used wherever an RLS policy already expresses the rule:
/// inserting a job (`jobs_client_insert_own`), reading your own jobs
/// (`jobs_client_select_own`), reading your matches
/// (`job_matches_client_select`). The database enforces ownership, so the
/// client can talk to it straight.
///
/// An edge function is used wherever the operation needs more than the caller
/// is allowed: ranking needs to read every technician, accepting an offer needs
/// to write `job_matches`, and recording an outcome needs to write
/// `job_outcomes`. None of those has a write policy, on purpose - a client that
/// could write its own scores could rig the recommendations.
class RbCarsService {
  RbCarsService({SupabaseClient? client}) : _injected = client;

  final SupabaseClient? _injected;

  /// Resolved per call rather than in the constructor.
  ///
  /// `Supabase.instance` throws until `Supabase.initialize` has run, so
  /// resolving eagerly meant merely *constructing* a service - which
  /// `JobPostingProvider` does the moment the posting flow opens - required a
  /// live backend. Widget tests could not pump the flow at all. Deferring it
  /// here costs one null check and makes the screens renderable offline; the
  /// throw still happens, just at the call that actually needs the network.
  SupabaseClient get _client => _injected ?? SupabaseService.client;

  static const String _matchFunction = 'match-technician';
  static const String _responseFunction = 'job-response';

  /// Storage bucket for job photos. Create it once in the dashboard:
  /// Storage -> New bucket -> `job-photos`, public read.
  static const String photoBucket = 'job-photos';

  String get _uid {
    final String? id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const RbCarsFailure('Please sign in again to continue.');
    }
    return id;
  }

  // ------------------------------------------------------------------- jobs

  /// Inserts the draft as a `jobs` row.
  ///
  /// `client_id` is taken from the session, never from the form, so a tampered
  /// payload cannot post a job in somebody else's name. The
  /// `jobs_client_insert_own` policy would reject it anyway - this just fails
  /// earlier and more clearly.
  Future<Job> postJob(JobDraft draft) async {
    if (!draft.isClassified) {
      throw const RbCarsFailure('Pick a device and a symptom first.');
    }

    try {
      final Map<String, dynamic> row = await _client
          .from('jobs')
          .insert(draft.toInsert(clientId: _uid))
          .select()
          .single();

      return Job.fromJson(row);
    } on PostgrestException catch (error, stackTrace) {
      _log('postJob', error, stackTrace);
      throw RbCarsFailure(_friendly(error), detail: error);
    }
  }

  /// Saves "Edit post": the job with the client's changes, its open matches
  /// cleared.
  ///
  /// Through `job-response` rather than a direct update: `jobs` is frozen with
  /// no client update policy, and an edit also clears `job_matches`, which has
  /// no client write policy at all. The server applies the same rules as
  /// deleting - only before any technician has accepted. Matching is re-run by
  /// the caller afterwards, exactly as after posting.
  Future<Job> updateJob(String jobId, JobDraft draft) async {
    if (!draft.isClassified) {
      throw const RbCarsFailure('Pick a device and a symptom first.');
    }

    final Map<String, dynamic> data = await _invoke(
      _responseFunction,
      <String, dynamic>{
        'job_id': jobId,
        'action': 'update_job',
        'job': draft.toUpdate(),
      },
    );

    final Object? row = data['job'];
    if (row is! Map<String, dynamic>) {
      throw const RbCarsFailure('Could not save your changes. Please try again.');
    }
    return Job.fromJson(row);
  }

  /// The caller's jobs that were completed within [within], newest first.
  ///
  /// Read from `job_outcomes`, whose `created_at` is the moment the job was
  /// closed - `jobs` itself keeps no completion time. Used to ask for a
  /// rating while the repair is fresh, and never about one from months ago.
  /// Never throws: a failed lookup just means no prompt this time.
  Future<List<String>> recentlyCompletedJobIds({
    Duration within = const Duration(days: 7),
  }) async {
    try {
      final List<dynamic> rows = await _client
          .from('job_outcomes')
          .select('job_id, created_at')
          .gte(
            'created_at',
            DateTime.now().subtract(within).toUtc().toIso8601String(),
          )
          .order('created_at', ascending: false);
      return rows
          .whereType<Map<String, dynamic>>()
          .map((Map<String, dynamic> row) => row['job_id'] as String)
          .toList(growable: false);
    } catch (error, stackTrace) {
      _log('recentlyCompletedJobIds', error, stackTrace);
      return const <String>[];
    }
  }

  /// The signed-in client's own jobs, newest first.
  Future<List<Job>> myJobs({JobStatus? status}) async {
    try {
      final PostgrestFilterBuilder<List<Map<String, dynamic>>> query = _client
          .from('jobs')
          .select()
          .eq('client_id', _uid);

      final List<Map<String, dynamic>> rows = status == null
          ? await query.order('created_at', ascending: false)
          : await query
                .eq('status', status.wire)
                .order('created_at', ascending: false);

      return rows.map(Job.fromJson).toList(growable: false);
    } on PostgrestException catch (error, stackTrace) {
      _log('myJobs', error, stackTrace);
      throw RbCarsFailure(_friendly(error), detail: error);
    }
  }

  /// The technician requested or booked on each of the caller's jobs, keyed by
  /// job id.
  ///
  /// Returned as a map rather than a list because every caller wants it that
  /// way - the dashboard is walking a list of jobs and asking "who is on this
  /// one?" for each.
  ///
  /// Never fatal. The name beside a job is an enrichment of a list that
  /// already renders without it, so a failure here returns an empty map and
  /// the dashboard simply shows what it showed before.
  Future<Map<String, JobTechnician>> bookedTechnicians() async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('client_job_technicians')
          .select();

      return <String, JobTechnician>{
        for (final Map<String, dynamic> row in rows)
          row['job_id'] as String: JobTechnician.fromJson(row),
      };
    } catch (error, stackTrace) {
      _log('bookedTechnicians', error, stackTrace);
      return <String, JobTechnician>{};
    }
  }

  /// Takes back a request the technician has not answered.
  ///
  /// The match returns to `shortlisted`, so the original Top 3 is intact and
  /// the client can choose again - including the same person, if they simply
  /// tapped the wrong card. Nothing is recorded against the technician: a
  /// withdrawal is not a decline, and it must never read as one on their
  /// acceptance rate.
  ///
  /// Goes through an RPC rather than the `job-response` edge function because
  /// it touches nothing the caller cannot already see. See migration
  /// 20260921000003 for the full reasoning.
  Future<void> withdrawTechnician(String jobId) async {
    try {
      await _client.rpc<void>(
        'withdraw_technician_offer',
        params: <String, dynamic>{'p_job_id': jobId},
      );
    } on PostgrestException catch (error, stackTrace) {
      _log('withdrawTechnician', error, stackTrace);

      // The database raises these with specific SQLSTATEs so the app can say
      // something true rather than a generic failure.
      throw RbCarsFailure(switch (error.code) {
        'P0002' => 'That request has already been answered.',
        '42501' => 'This job belongs to someone else.',
        '22023' => 'This job has already been confirmed.',
        _ => 'Could not cancel that request.',
      }, detail: error);
    } catch (error, stackTrace) {
      _log('withdrawTechnician', error, stackTrace);
      throw const RbCarsFailure(
        'Could not cancel that request. Check your connection.',
      );
    }
  }

  Future<Job?> jobById(String jobId) async {
    try {
      final Map<String, dynamic>? row = await _client
          .from('jobs')
          .select()
          .eq('id', jobId)
          .maybeSingle();
      return row == null ? null : Job.fromJson(row);
    } on PostgrestException catch (error, stackTrace) {
      _log('jobById', error, stackTrace);
      throw RbCarsFailure(_friendly(error), detail: error);
    }
  }

  // ---------------------------------------------------------------- matching

  /// Runs RB-CARS for a job and returns everything the run produced.
  ///
  /// [excludeTechnicianIds] is used when re-matching after declines, so nobody
  /// is offered a job they already turned down.
  ///
  /// The response used to be thrown away and only the written rows read back.
  /// That discarded two things worth having: the full ranking (everyone the
  /// engine scored, not just the three that fit in `job_matches`) and the
  /// engine's own explanation when it produced nothing - which is why an empty
  /// list could only ever be explained by a hardcoded guess on the screen.
  Future<MatchingRun> runMatching(
    String jobId, {
    List<String> excludeTechnicianIds = const <String>[],
  }) async {
    final Map<String, dynamic> response =
        await _invoke(_matchFunction, <String, dynamic>{
          'job_id': jobId,
          if (excludeTechnicianIds.isNotEmpty)
            'exclude_technician_ids': excludeTechnicianIds,
        });

    final Object? raw = response['considered'];
    final List<ConsideredTechnician> considered = raw is List
        ? raw
              .whereType<Map<String, dynamic>>()
              .map(ConsideredTechnician.fromJson)
              .toList(growable: false)
        : const <ConsideredTechnician>[];

    return MatchingRun(
      // Read the rows back through RLS rather than trusting the function's
      // echo. Same data, but it proves the client can actually see what was
      // written.
      matches: await fetchMatches(jobId),
      considered: considered,
      message: response['message'] as String?,
      evaluated: asInt(response['evaluated']),
    );
  }

  /// The offers for a job, best rank first.
  Future<List<MatchResult>> fetchMatches(String jobId) async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('job_matches')
          .select()
          .eq('job_id', jobId)
          .order('rank', ascending: true);

      return rows.map(MatchResult.fromJson).toList(growable: false);
    } on PostgrestException catch (error, stackTrace) {
      _log('fetchMatches', error, stackTrace);
      throw RbCarsFailure(_friendly(error), detail: error);
    }
  }

  /// Matches the client can still act on: the shortlist they have not chosen
  /// from yet, plus any technician already requested and still deciding.
  ///
  /// `shortlisted` MUST be included here. It is the state every match is in
  /// before the client picks one, so filtering to `offered` alone - which is
  /// what this did - would show the client an empty Top 3 on a job that had
  /// just been matched.
  Future<List<MatchResult>> fetchLiveOffers(String jobId) async {
    final List<MatchResult> all = await fetchMatches(jobId);
    return all.where((MatchResult m) => m.isOpen).toList(growable: false);
  }

  // ------------------------------------------------- technician confirmation

  /// The **client** picks one of the Top 3.
  ///
  /// This is not an acceptance. It narrows the job to that technician and
  /// retires the other two offers, so only the chosen one is asked. The
  /// technician still has to accept, reroute or decline from their own
  /// dashboard - those three actions never belong on a client screen.
  Future<JobResponseOutcome> selectTechnician(String matchId) {
    return _respond(<String, dynamic>{'match_id': matchId, 'action': 'select'});
  }

  /// Technician accepts an offer and will fix it on site.
  Future<JobResponseOutcome> acceptOffer(String matchId) {
    return _respond(<String, dynamic>{'match_id': matchId, 'action': 'accept'});
  }

  /// The signed-in client's own review of [jobId], or null if they have not
  /// written one.
  ///
  /// A plain select: `job_reviews_select_own` already restricts rows to ones
  /// the caller wrote or received, so no function is needed.
  Future<TechnicianReview?> myReview(String jobId) async {
    final String? uid = _client.auth.currentUser?.id;
    if (uid == null) return null;

    try {
      final Map<String, dynamic>? row = await _client
          .from('job_reviews')
          .select('id, stars, comment, created_at')
          .eq('job_id', jobId)
          .eq('reviewer_id', uid)
          .maybeSingle();
      return row == null ? null : TechnicianReview.fromJson(row);
    } on PostgrestException catch (error, stackTrace) {
      _log('myReview', error, stackTrace);
      return null;
    }
  }

  /// Writes, or corrects, the client's review of a completed job.
  ///
  /// This is the only thing in the app that records a rating. Until it existed
  /// every technician was rated 0.00: `complete` only accepts a rating from the
  /// client, and only the technician ever calls it. The `job_reviews` trigger
  /// (20260917000001) mirrors these stars into `job_outcomes.final_rating` and
  /// recomputes `technicians.rating`, so one review reaches the recommended
  /// row, the matcher and Stage 1 accuracy at once.
  ///
  /// Direct PostgREST, no function: the insert policy proves every claim the
  /// row makes - you are the reviewer, the job is yours, it is completed, and
  /// this technician did it. An edit may only change [stars] and [comment];
  /// column grants refuse anything else.
  Future<void> submitReview({
    required String jobId,
    required String technicianId,
    required int stars,
    String? comment,
    String? existingReviewId,
  }) async {
    final String? uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw const RbCarsFailure('Please sign in again to continue.');
    }
    if (stars < 1 || stars > 5) {
      throw const RbCarsFailure('Choose between one and five stars.');
    }

    final String? trimmed = comment?.trim();
    final String? body = (trimmed == null || trimmed.isEmpty) ? null : trimmed;

    try {
      if (existingReviewId == null) {
        await _client.from('job_reviews').insert(<String, dynamic>{
          'job_id': jobId,
          'technician_id': technicianId,
          'reviewer_id': uid,
          'stars': stars,
          'comment': body,
        });
      } else {
        await _client
            .from('job_reviews')
            .update(<String, dynamic>{'stars': stars, 'comment': body})
            .eq('id', existingReviewId);
      }
    } on PostgrestException catch (error, stackTrace) {
      _log('submitReview', error, stackTrace);
      // 23505: the unique (job_id, reviewer_id) - a second tap, or a review
      // written from another device a moment ago.
      if (error.code == '23505') {
        throw const RbCarsFailure('You have already reviewed this job.');
      }
      throw RbCarsFailure(_friendly(error), detail: error);
    }
  }

  // --------------------------------------------------------------- parties

  /// Both people on each of the caller's jobs, keyed by job id, with the
  /// caller's own rating of the other person where they have given one.
  ///
  /// Never fatal. Names and stars enrich a list that already renders without
  /// them, so a failure returns an empty map and the list shows what it did
  /// before rather than an error.
  Future<Map<String, JobParty>> jobParties() async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('job_parties')
          .select();
      return <String, JobParty>{
        for (final Map<String, dynamic> row in rows)
          row['job_id'] as String: JobParty.fromJson(row),
      };
    } catch (error, stackTrace) {
      _log('jobParties', error, stackTrace);
      return <String, JobParty>{};
    }
  }

  // -------------------------------------------------------- client ratings

  /// The technician's own rating of the client on [jobId], or null.
  ///
  /// Returned in the review shape (`id`, `stars`, `comment`) so the same
  /// rating sheet edits either direction.
  Future<TechnicianReview?> myClientReview(String jobId) async {
    final String? uid = _client.auth.currentUser?.id;
    if (uid == null) return null;

    try {
      final Map<String, dynamic>? row = await _client
          .from('client_reviews')
          .select('id, stars, comment, created_at')
          .eq('job_id', jobId)
          .eq('technician_id', uid)
          .maybeSingle();
      return row == null ? null : TechnicianReview.fromJson(row);
    } on PostgrestException catch (error, stackTrace) {
      _log('myClientReview', error, stackTrace);
      return null;
    }
  }

  /// Writes, or corrects, a technician's rating of the client on a completed
  /// job. The mirror of [submitReview].
  ///
  /// Direct PostgREST: the insert policy proves every claim the row makes -
  /// the caller is the assigned technician, [clientId] really is this job's
  /// client, and the job is completed. A guard trigger pins everything but the
  /// stars and comment on an edit.
  Future<void> submitClientReview({
    required String jobId,
    required String clientId,
    required int stars,
    String? comment,
    String? existingReviewId,
  }) async {
    final String? uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw const RbCarsFailure('Please sign in again to continue.');
    }
    if (stars < 1 || stars > 5) {
      throw const RbCarsFailure('Choose between one and five stars.');
    }

    final String? trimmed = comment?.trim();
    final String? body = (trimmed == null || trimmed.isEmpty) ? null : trimmed;

    try {
      if (existingReviewId == null) {
        await _client.from('client_reviews').insert(<String, dynamic>{
          'job_id': jobId,
          'client_id': clientId,
          'technician_id': uid,
          'stars': stars,
          'comment': body,
        });
      } else {
        await _client
            .from('client_reviews')
            .update(<String, dynamic>{'stars': stars, 'comment': body})
            .eq('id', existingReviewId);
      }
    } on PostgrestException catch (error, stackTrace) {
      _log('submitClientReview', error, stackTrace);
      if (error.code == '23505') {
        throw const RbCarsFailure('You have already rated this client.');
      }
      if (error.code == '42501') {
        throw const RbCarsFailure(
          'You can rate a client once their job is completed.',
        );
      }
      throw RbCarsFailure(_friendly(error), detail: error);
    }
  }

  /// A client's public profile - what a technician may see before, during
  /// and after a job, and what anyone sees from a Community byline.
  Future<ClientProfileDetails> clientProfile(String clientId) async {
    try {
      final Object? data = await _client.rpc<Object?>(
        'client_profile',
        params: <String, dynamic>{'p_client_id': clientId},
      );
      if (data is! Map<String, dynamic>) {
        throw const RbCarsFailure('That profile is not available.');
      }
      return ClientProfileDetails.fromJson(data);
    } on PostgrestException catch (error, stackTrace) {
      _log('clientProfile', error, stackTrace);
      throw RbCarsFailure(
        error.code == 'P0002'
            ? 'That profile is not available.'
            : 'Could not load this profile.',
        detail: error,
      );
    }
  }

  /// Removes a job nobody has taken yet.
  ///
  /// Only legal while the job is `pending` or `matched` with no technician
  /// assigned - the server refuses once anyone has accepted, because by then
  /// the record belongs to the technician too. See `handleDeleteJob`.
  Future<JobResponseOutcome> deleteJob(String jobId) {
    return _respond(<String, dynamic>{
      'job_id': jobId,
      'action': 'delete_job',
    });
  }

  /// Mid-job: an on-site repair the technician cannot finish at the client's
  /// home, so the unit has to go to the workshop.
  ///
  /// Keyed on the JOB, not a match, because by now the offer is accepted and
  /// the booking exists. Switches `service_path` to `pickup` and opens the
  /// tracking row, so the client's map appears from the moment they are told
  /// their appliance is being collected.
  Future<JobResponseOutcome> markNeedsShop(String jobId) {
    return _respond(<String, dynamic>{
      'job_id': jobId,
      'action': 'needs_shop',
    });
  }

  /// Technician accepts but the unit has to go to the shop. Switches the job's
  /// service path to `pickup`.
  /// No longer reachable from the app: the offer screen is now a straight
  /// accept/decline and the shop decision happens on site via [markNeedsShop].
  /// Kept so an older installed build still works against this function.
  Future<JobResponseOutcome> rerouteOffer(String matchId) {
    return _respond(<String, dynamic>{
      'match_id': matchId,
      'action': 'reroute',
    });
  }

  /// Technician declines. The function marks this row declined and either
  /// promotes the next rank or re-runs matching when all three are gone.
  Future<JobResponseOutcome> declineOffer(String matchId) {
    return _respond(<String, dynamic>{
      'match_id': matchId,
      'action': 'decline',
    });
  }

  /// Closes the job and writes the `job_outcomes` row that Stage 1 learns from.
  Future<JobResponseOutcome> completeJob(
    String jobId, {
    bool? diagnosisCorrect,
    bool reroutedMidJob = false,
    double? finalRating,
  }) {
    return _respond(<String, dynamic>{
      'job_id': jobId,
      'action': 'complete',
      'diagnosis_correct': diagnosisCorrect,
      'rerouted_mid_job': reroutedMidJob,
      if (finalRating != null) 'final_rating': finalRating,
    });
  }

  Future<JobResponseOutcome> _respond(Map<String, dynamic> body) async {
    final Map<String, dynamic> data = await _invoke(_responseFunction, body);
    return JobResponseOutcome.fromJson(data);
  }

  // ------------------------------------------------------------------ photos

  /// Uploads job photos and returns their public URLs.
  ///
  /// Deliberately forgiving: a missing bucket or a failed upload returns the
  /// URLs that did succeed rather than throwing, because losing a photo must
  /// never block someone from posting a repair job. The caller reports how many
  /// made it.
  Future<List<String>> uploadPhotos(List<XFile> files) async {
    if (files.isEmpty) return const <String>[];

    final String uid = _uid;
    final List<String> urls = <String>[];

    for (int i = 0; i < files.length; i++) {
      final XFile file = files[i];
      final String extension = _extensionOf(file);
      final String name =
          '$uid/${DateTime.now().millisecondsSinceEpoch}_$i.$extension';

      try {
        // `uploadBinary` rather than `upload`: the latter reads from a
        // filesystem, which Flutter Web does not have. The content type is set
        // explicitly for the same reason the ID upload does it - an inferred
        // type comes back as octet-stream for a blob and the bucket rejects it.
        await _client.storage
            .from(photoBucket)
            .uploadBinary(
              name,
              await file.readAsBytes(),
              fileOptions: FileOptions(
                upsert: false,
                contentType: _mimeFor(extension),
              ),
            );
        urls.add(_client.storage.from(photoBucket).getPublicUrl(name));
      } catch (error, stackTrace) {
        _log('uploadPhotos', error, stackTrace);
      }
    }

    return urls;
  }

  /// Best available extension. On web the path is a `blob:` URL with none, so
  /// the picker's reported name and MIME type are used instead.
  String _extensionOf(XFile file) {
    const Set<String> allowed = <String>{'jpg', 'jpeg', 'png', 'webp', 'heic'};
    final String name = file.name.isNotEmpty ? file.name : file.path;
    if (name.contains('.')) {
      final String candidate = name.split('.').last.toLowerCase();
      if (allowed.contains(candidate)) return candidate;
    }
    return switch (file.mimeType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/heic' || 'image/heif' => 'heic',
      _ => 'jpg',
    };
  }

  String _mimeFor(String extension) => switch (extension) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    _ => 'image/jpeg',
  };

  // ------------------------------------------------------------------ shared

  /// Calls an edge function and normalises its response into a map.
  Future<Map<String, dynamic>> _invoke(
    String name,
    Map<String, dynamic> body,
  ) async {
    try {
      final FunctionResponse response = await _client.functions.invoke(
        name,
        body: body,
      );

      final Object? data = response.data;
      if (data is Map<String, dynamic>) {
        if (data['error'] != null) {
          throw RbCarsFailure(data['error'].toString(), detail: data['detail']);
        }
        return data;
      }
      return <String, dynamic>{};
    } on FunctionException catch (error, stackTrace) {
      _log(name, error, stackTrace);
      throw RbCarsFailure(_friendlyFunction(error), detail: error.details);
    } on RbCarsFailure {
      rethrow;
    } catch (error, stackTrace) {
      _log(name, error, stackTrace);
      throw const RbCarsFailure(
        'Could not reach the matching service. Check your connection and '
        'try again.',
      );
    }
  }

  String _friendly(PostgrestException error) {
    final String message = error.message.toLowerCase();
    if (message.contains('row-level security')) {
      return 'You do not have permission to do that.';
    }
    if (message.contains('violates check constraint')) {
      return 'Some of those details are not valid. Please review and retry.';
    }
    if (message.contains('foreign key')) {
      return 'That technician or job no longer exists.';
    }
    return 'Something went wrong saving that. Please try again.';
  }

  String _friendlyFunction(FunctionException error) {
    final Object? details = error.details;
    if (details is Map && details['error'] is String) {
      return details['error'] as String;
    }
    if (error.status == 401) return 'Please sign in again to continue.';
    if (error.status == 403) return 'You do not have permission to do that.';
    if (error.status == 404) return 'We could not find that job.';
    if (error.status == 409) {
      return 'That offer was already answered by someone else.';
    }
    return 'The matching service could not complete that request.';
  }

  void _log(String action, Object error, StackTrace stackTrace) {
    if (kDebugMode) {
      debugPrint('RbCarsService.$action failed: $error');
      debugPrintStack(stackTrace: stackTrace, maxFrames: 6);
    }
  }
}

/// What `job-response` returned.
class JobResponseOutcome {
  const JobResponseOutcome({
    this.jobId,
    this.matchId,
    this.status,
    this.servicePath,
    this.rerouted = false,
    this.nextOfferMatchId,
    this.nextOfferRank,
    this.rematched = false,
    this.awaitingClientReselect = false,
    this.shortlistRemaining = 0,
    this.message,
  });

  factory JobResponseOutcome.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? next =
        json['next_offer'] as Map<String, dynamic>?;

    return JobResponseOutcome(
      jobId: json['job_id'] as String?,
      matchId: json['match_id'] as String?,
      status: json['status'] as String?,
      servicePath: ServicePath.fromWire(json['service_path'] as String?),
      rerouted: json['rerouted'] as bool? ?? false,
      nextOfferMatchId: next?['match_id'] as String?,
      nextOfferRank: next?['rank'] as int?,
      rematched: json['rematched'] as bool? ?? false,
      awaitingClientReselect:
          json['awaiting_client_reselect'] as bool? ?? false,
      shortlistRemaining: json['shortlist_remaining'] as int? ?? 0,
      message: json['message'] as String?,
    );
  }

  final String? jobId;
  final String? matchId;
  final String? status;
  final ServicePath? servicePath;
  final bool rerouted;

  /// Legacy fields from the old auto-cascade, where declining promoted rank 2
  /// without asking the client. The server no longer sends `next_offer`, so
  /// these are always null now; they are kept so an older client build talking
  /// to the new function still parses a response instead of throwing.
  final String? nextOfferMatchId;
  final int? nextOfferRank;

  /// True when every offer was declined and the engine produced a fresh Top 3.
  final bool rematched;

  /// True when the technician declined but the client still has shortlisted
  /// matches to choose from. The app should return them to the shortlist rather
  /// than showing a "finding you someone" state.
  final bool awaitingClientReselect;

  /// How many shortlisted matches are left to choose from.
  final int shortlistRemaining;

  final String? message;

  bool get isConfirmed => status == 'confirmed';
  bool get isCompleted => status == 'completed';
  bool get hasNextOffer => nextOfferMatchId != null;
}
