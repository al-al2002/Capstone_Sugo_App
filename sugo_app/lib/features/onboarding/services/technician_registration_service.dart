import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../../technician/models/assessment.dart';
import '../models/specialization_catalog.dart';
import '../models/verification_document.dart';

/// One assessment a technician still has to sit, or has already sat.
///
/// Keyed to an [AssessmentTrack], not to a single specialisation row. Passing
/// one of these verifies every brand the technician declared inside the track,
/// which is why the list is short even when the specialisation list is long.
class PendingAssessment {
  const PendingAssessment({
    required this.track,
    required this.specializationCount,
    this.verifiedCount = 0,
    this.skillLevel,
    this.lastScore,
    this.lastAttemptAt,
    this.attemptCount = 0,
    this.retakeAvailableAt,
  });

  factory PendingAssessment.fromJson(Map<String, dynamic> json) {
    final DateTime? takenAt = DateTime.tryParse(
      json['last_attempt_at'] as String? ?? '',
    );
    final bool passed = json['passed'] as bool? ?? false;

    return PendingAssessment(
      track:
          AssessmentTrack.fromWire(json['track'] as String?) ??
          AssessmentTrack.computerRepair,
      specializationCount: json['specialization_count'] as int? ?? 0,
      verifiedCount: json['verified_count'] as int? ?? 0,
      skillLevel: SkillLevel.fromWire(json['skill_level'] as String?),
      lastScore: (json['last_score'] as num?)?.toDouble(),
      lastAttemptAt: takenAt,
      attemptCount: json['attempt_count'] as int? ?? 0,
      // Mirrors `assessment_retake_cooldown()`. The server enforces it; this
      // is only so the UI can show a countdown instead of offering a button
      // that fails.
      retakeAvailableAt: (passed || takenAt == null)
          ? null
          : takenAt.add(retakeCooldown),
    );
  }

  final AssessmentTrack track;

  /// How many declared (device, brand) rows this one sitting covers.
  final int specializationCount;

  final int verifiedCount;
  final SkillLevel? skillLevel;
  final double? lastScore;
  final DateTime? lastAttemptAt;
  final int attemptCount;

  /// When a failed attempt may be retried. Null when there is nothing to wait
  /// for - either never attempted, or already passed.
  final DateTime? retakeAvailableAt;

  /// Mirror of `public.assessment_retake_cooldown()`.
  ///
  /// Duplicated here on purpose so the countdown can render offline. The
  /// database remains the authority - a client with a tampered clock is
  /// refused by `record_assessment_result()` regardless of what this says.
  static const Duration retakeCooldown = Duration(hours: 24);

  bool get isPassed => verifiedCount > 0;

  bool get hasAttempted => attemptCount > 0;

  /// True while the cooldown from a failed attempt is still running.
  bool get isCoolingDown {
    final DateTime? at = retakeAvailableAt;
    return at != null && at.isAfter(DateTime.now());
  }

  Duration get remainingCooldown {
    final DateTime? at = retakeAvailableAt;
    if (at == null) return Duration.zero;
    final Duration left = at.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  /// "Retake in 3h 20m" - the only thing the user can act on while blocked.
  String get cooldownLabel {
    final Duration left = remainingCooldown;
    if (left == Duration.zero) return 'Ready to retake';
    final int hours = left.inHours;
    final int minutes = left.inMinutes.remainder(60);
    if (hours > 0) return 'Retake in ${hours}h ${minutes}m';
    return 'Retake in ${minutes}m';
  }

  /// "Covers 6 brands" - makes the grouping visible, so the technician can see
  /// that one quiz is doing the work of six.
  String get coverageLabel {
    if (specializationCount <= 1) return '1 specialisation';
    return 'Covers $specializationCount specialisations';
  }
}

/// Everything the technician registration flow writes and reads.
///
/// ## Which calls go direct, and which go through an edge function
///
/// * **Specialisations, documents, base location** - direct. Each has an RLS
///   policy scoped to `auth.uid()`, and none of them awards anything: the
///   insert policy pins `verified` and `skill_level` to their defaults, so a
///   hostile client can declare a specialisation but never qualify itself.
/// * **Assessment submission** - the `submit-assessment` edge function, and it
///   has to be. The client cannot read `correct_choice_index` (revoked in
///   20260906000002) so it cannot mark its own paper, and
///   `record_assessment_result()` is service-role only so it cannot award
///   itself a skill level either.
/// * **Final submission** - the `submit-registration` edge function, because
///   `submit_registration_for_review()` is service-role only. Letting the app
///   set `pending_review` directly would let it skip the completeness checks.
class TechnicianRegistrationService {
  TechnicianRegistrationService({SupabaseClient? client})
    : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  static const String _submitAssessmentFunction = 'submit-assessment';
  static const String _submitRegistrationFunction = 'submit-registration';

  /// Radius options, in kilometres.
  ///
  /// A fixed set rather than a free number field. A slider inviting "37 km"
  /// implies a precision the matcher does not have, and four options are
  /// enough to express the real cases: same barangay, across the city, the
  /// whole city, and the surrounding municipalities.
  static const List<double> radiusOptions = <double>[5, 10, 15, 20];

  /// Matches the `service_radius_km` column default.
  static const double defaultRadiusKm = 10;

  String get _uid {
    final String? id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const RbCarsFailure('Please sign in again to continue.');
    }
    return id;
  }

  /// Ensures the `technicians` row exists.
  ///
  /// Called before the first write that references it. The row is created with
  /// nothing but its id, so the column defaults decide the starting state:
  /// unverified, offline, `basic` tier. Deliberately not created at sign-up -
  /// someone who picks the technician role and leaves should not leave a
  /// technician row behind.
  Future<void> ensureTechnicianRow() async {
    try {
      await _client.from('technicians').upsert(<String, dynamic>{
        'id': _uid,
      }, onConflict: 'id');
    } on PostgrestException catch (error) {
      _log('ensureTechnicianRow', error);
      throw RbCarsFailure(
        _describe(error, 'Could not set up your technician profile.'),
      );
    }
  }

  // ------------------------------------------------------- specialisations

  Future<List<TechnicianSpecialization>> loadSpecializations() async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('technician_specializations')
          .select()
          .eq('technician_id', _uid)
          .order('created_at');

      return rows
          .map(TechnicianSpecialization.fromJson)
          .toList(growable: false);
    } on PostgrestException catch (error) {
      _log('loadSpecializations', error);
      throw const RbCarsFailure('Could not load your specialisations.');
    }
  }

  /// Saves the picker's selection, adding what is new and removing what was
  /// deselected.
  ///
  /// A diff rather than delete-all-then-insert, so untouched rows keep their
  /// ids and their earned `skill_level` instead of being recreated unverified
  /// on every visit to the step.
  Future<List<TechnicianSpecialization>> saveSpecializations(
    List<TechnicianSpecialization> selection,
  ) async {
    await ensureTechnicianRow();

    final String uid = _uid;
    final List<TechnicianSpecialization> existing = await loadSpecializations();

    final Set<String> wanted = selection
        .map((TechnicianSpecialization s) => s.localKey)
        .toSet();
    final Set<String> current = existing
        .map((TechnicianSpecialization s) => s.localKey)
        .toSet();

    final List<TechnicianSpecialization> toAdd = selection
        .where((TechnicianSpecialization s) => !current.contains(s.localKey))
        .toList();

    // Anything deselected goes, verified or not. That used to exclude verified
    // rows, which became untenable with tracks: one pass verifies every brand
    // in the track, so a single quiz could permanently freeze a brand added by
    // mistake.
    //
    // Nothing is lost by allowing it. Since 20260907000009 the attempt history
    // is keyed on `track` and `specialization_id` is `on delete set null`, so
    // the record of the sitting - and the retake cooldown computed from it -
    // survives. Re-adding a brand in a track that was already passed comes back
    // verified automatically, via the `inherit_track_verification` trigger.
    final List<TechnicianSpecialization> toRemove = existing
        .where((TechnicianSpecialization s) => !wanted.contains(s.localKey))
        .toList();

    try {
      if (toAdd.isNotEmpty) {
        await _client
            .from('technician_specializations')
            .insert(
              toAdd
                  .map((TechnicianSpecialization s) => s.toInsertJson(uid))
                  .toList(),
            );
      }

      if (toRemove.isNotEmpty) {
        await _client
            .from('technician_specializations')
            .delete()
            .inFilter(
              'id',
              toRemove
                  .map((TechnicianSpecialization s) => s.id)
                  .whereType<String>()
                  .toList(),
            );
      }

      return loadSpecializations();
    } on PostgrestException catch (error) {
      _log('saveSpecializations', error);
      throw RbCarsFailure(
        _describe(error, 'Could not save your specialisations.'),
      );
    }
  }

  // ------------------------------------------------------------ assessments

  /// The assessment list: one entry per TRACK the technician has declared in.
  ///
  /// Reads `technician_assessment_tracks`, a view that groups the
  /// specialisation rows by track and folds in the attempt history. That
  /// grouping is the whole point: a technician with laptop and desktop work
  /// across three brands sees ONE "Computer repair" assessment, not six.
  ///
  /// One query rather than the two-query pairing this used to do in Dart,
  /// because the view already joins the results.
  Future<List<PendingAssessment>> loadAssessments() async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('technician_assessment_tracks')
          .select()
          .eq('technician_id', _uid);

      final List<PendingAssessment> items = rows
          .map(PendingAssessment.fromJson)
          .toList();

      // Outstanding first, so the work to do is at the top.
      items.sort((PendingAssessment a, PendingAssessment b) {
        if (a.isPassed != b.isPassed) return a.isPassed ? 1 : -1;
        return a.track.label.compareTo(b.track.label);
      });

      return List<PendingAssessment>.unmodifiable(items);
    } on PostgrestException catch (error) {
      _log('loadAssessments', error);
      throw const RbCarsFailure('Could not load your assessments.');
    }
  }

  /// Question bank for a track.
  ///
  /// ## Placeholder content, stated plainly
  ///
  /// Every track is seeded with ten questions by migration 20260907000008.
  /// They are placeholders in the sense that a real deployment would have them
  /// written and reviewed by working technicians - not in the sense of being
  /// fake: each has a single defensible answer from ordinary repair practice.
  /// The UI, the scoring, the bands and the cooldown are all real.
  Future<List<AssessmentQuestion>> fetchQuestions(AssessmentTrack track) async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('assessment_questions')
          .select('id, specialization, question, choices')
          .eq('specialization', track.wire)
          .order('created_at');

      if (rows.isEmpty) {
        throw RbCarsFailure(
          'No questions are available for ${track.label} yet. '
          'Choose another specialisation, or check back soon.',
        );
      }

      return rows.map(AssessmentQuestion.fromJson).toList(growable: false);
    } on PostgrestException catch (error) {
      _log('fetchQuestions', error);
      throw const RbCarsFailure('Could not load the assessment questions.');
    }
  }

  /// Submits answers for marking.
  ///
  /// The score, the pass verdict, the attempt number, the cooldown and which
  /// specialisations get verified are all decided server-side. Nothing this
  /// method sends can influence them beyond the answers themselves.
  Future<AssessmentOutcome> submitAssessment({
    required AssessmentTrack track,
    required Map<String, int> answers,
  }) async {
    try {
      final FunctionResponse response = await _client.functions.invoke(
        _submitAssessmentFunction,
        body: <String, dynamic>{'track': track.wire, 'answers': answers},
      );

      final Object? data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const RbCarsFailure('The server returned an unexpected reply.');
      }
      if (data['error'] != null) {
        throw RbCarsFailure(data['error'].toString());
      }

      return AssessmentOutcome.fromJson(data);
    } on FunctionException catch (error) {
      _log('submitAssessment', error);
      final Object? details = error.details;
      if (details is Map && details['error'] is String) {
        throw RbCarsFailure(details['error'] as String);
      }
      throw const RbCarsFailure('Could not submit your assessment.');
    } on RbCarsFailure {
      rethrow;
    } catch (error) {
      _log('submitAssessment', error);
      throw const RbCarsFailure(
        'Could not reach the server. Check your connection and try again.',
      );
    }
  }

  // -------------------------------------------------------------- documents

  Future<List<VerificationDocument>> loadDocuments() async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('technician_verification_documents')
          .select()
          .eq('technician_id', _uid)
          .order('uploaded_at', ascending: false);

      return rows.map(VerificationDocument.fromJson).toList(growable: false);
    } on PostgrestException catch (error) {
      _log('loadDocuments', error);
      return const <VerificationDocument>[];
    }
  }

  /// Uploads an optional trust-boosting document.
  ///
  /// Portfolio images go to the public `job-photos` bucket, because they are
  /// promotional and clients are meant to see them. Certificates and NBI
  /// clearances go to the private `identity-documents` bucket - an NBI
  /// clearance carries a full name, address and birth date, so a public URL
  /// for one would be a data leak.
  Future<VerificationDocument> uploadDocument({
    required VerificationDocType docType,
    required XFile file,
    String? caption,
  }) async {
    await ensureTechnicianRow();

    final String uid = _uid;
    final bool isPublic = docType == VerificationDocType.portfolio;
    final String bucket = isPublic
        ? RbCarsService.photoBucket
        : 'identity-documents';

    final String extension = _extensionOf(file);
    final String objectPath =
        '$uid/${docType.wire}_${DateTime.now().millisecondsSinceEpoch}.$extension';

    String? uploaded;

    try {
      await _client.storage
          .from(bucket)
          .uploadBinary(
            objectPath,
            await file.readAsBytes(),
            fileOptions: FileOptions(
              upsert: true,
              contentType: _mimeTypes[extension] ?? 'image/jpeg',
            ),
          );
      uploaded = objectPath;

      final String fileUrl = isPublic
          ? _client.storage.from(bucket).getPublicUrl(objectPath)
          : objectPath;

      final Map<String, dynamic> row = await _client
          .from('technician_verification_documents')
          .insert(<String, dynamic>{
            'technician_id': uid,
            'doc_type': docType.wire,
            'file_url': fileUrl,
            if (caption != null && caption.trim().isNotEmpty)
              'caption': caption.trim(),
          })
          .select()
          .single();

      return VerificationDocument.fromJson(row);
    } on StorageException catch (error) {
      _log('uploadDocument', error);
      throw const RbCarsFailure('Could not upload that file.');
    } on PostgrestException catch (error) {
      // Same orphan cleanup as the identity submission: the object is already
      // in the bucket and nothing now references it.
      if (uploaded != null) {
        try {
          await _client.storage.from(bucket).remove(<String>[uploaded]);
        } catch (_) {
          // Best effort while another error propagates.
        }
      }
      _log('uploadDocument', error);
      throw RbCarsFailure(_describe(error, 'Could not save that document.'));
    }
  }

  Future<void> deleteDocument(VerificationDocument doc) async {
    try {
      await _client
          .from('technician_verification_documents')
          .delete()
          .eq('id', doc.id);
    } on PostgrestException catch (error) {
      _log('deleteDocument', error);
      throw const RbCarsFailure(
        'Could not remove that document. It may already be under review.',
      );
    }
  }

  // ------------------------------------------------------------ base location

  /// Saves the base location and service radius.
  ///
  /// Writes straight to `technicians`. The guard trigger from 20260905000002
  /// blocks the privileged columns and leaves these alone, which is exactly
  /// the split it was written for: a technician may describe their own work,
  /// but not their own standing.
  Future<void> saveBaseLocation({
    required double latitude,
    required double longitude,
    required double radiusKm,
  }) async {
    await ensureTechnicianRow();

    try {
      await _client
          .from('technicians')
          .update(<String, dynamic>{
            'base_latitude': latitude,
            'base_longitude': longitude,
            'service_radius_km': radiusKm,
          })
          .eq('id', _uid);
    } on PostgrestException catch (error) {
      _log('saveBaseLocation', error);
      throw RbCarsFailure(
        _describe(error, 'Could not save your service area.'),
      );
    }
  }

  Future<({double? latitude, double? longitude, double radiusKm})>
  loadBaseLocation() async {
    try {
      final Map<String, dynamic>? row = await _client
          .from('technicians')
          .select('base_latitude, base_longitude, service_radius_km')
          .eq('id', _uid)
          .maybeSingle();

      if (row == null) {
        return (latitude: null, longitude: null, radiusKm: defaultRadiusKm);
      }

      return (
        latitude: (row['base_latitude'] as num?)?.toDouble(),
        longitude: (row['base_longitude'] as num?)?.toDouble(),
        radiusKm:
            (row['service_radius_km'] as num?)?.toDouble() ?? defaultRadiusKm,
      );
    } on PostgrestException catch (error) {
      _log('loadBaseLocation', error);
      return (latitude: null, longitude: null, radiusKm: defaultRadiusKm);
    }
  }

  // ----------------------------------------------------------------- submit

  /// Files the finished registration for admin review.
  ///
  /// Goes through an edge function because
  /// `submit_registration_for_review()` is service-role only - it performs the
  /// completeness checks, and a client that could call it directly could also
  /// skip them by writing `pending_review` itself.
  Future<void> submitForReview() async {
    try {
      final FunctionResponse response = await _client.functions.invoke(
        _submitRegistrationFunction,
      );

      final Object? data = response.data;
      if (data is Map<String, dynamic> && data['error'] != null) {
        throw RbCarsFailure(data['error'].toString());
      }
    } on FunctionException catch (error) {
      _log('submitForReview', error);
      final Object? details = error.details;
      if (details is Map && details['error'] is String) {
        throw RbCarsFailure(details['error'] as String);
      }
      throw const RbCarsFailure('Could not submit your registration.');
    } on RbCarsFailure {
      rethrow;
    } catch (error) {
      _log('submitForReview', error);
      throw const RbCarsFailure(
        'Could not reach the server. Check your connection and try again.',
      );
    }
  }

  // ----------------------------------------------------------------- helpers

  static const Set<String> _allowedExtensions = <String>{
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
    'pdf',
  };

  static const Map<String, String> _mimeTypes = <String, String>{
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'pdf': 'application/pdf',
  };

  String _extensionOf(XFile file) {
    final String name = file.name.isNotEmpty ? file.name : file.path;
    if (name.contains('.')) {
      final String candidate = name.split('.').last.toLowerCase();
      if (_allowedExtensions.contains(candidate)) return candidate;
    }
    return switch (file.mimeType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/heic' || 'image/heif' => 'heic',
      'application/pdf' => 'pdf',
      _ => 'jpg',
    };
  }

  String _describe(PostgrestException error, String fallback) {
    final String message = error.message.toLowerCase();

    if (message.contains('row-level security') || error.code == '42501') {
      return '$fallback Your account is not permitted to do that yet - '
          'this usually means a database policy is missing.';
    }
    if (message.contains('duplicate key') || error.code == '23505') {
      return '$fallback You have already added that.';
    }
    if (message.contains('foreign key')) {
      return '$fallback Your profile could not be found.';
    }
    return '$fallback Please try again.';
  }

  void _log(String action, Object error) {
    if (kDebugMode) {
      if (error is PostgrestException) {
        debugPrint(
          'TechnicianRegistrationService.$action failed: '
          '[${error.code}] ${error.message}'
          '${error.details != null ? ' | ${error.details}' : ''}',
        );
      } else {
        debugPrint('TechnicianRegistrationService.$action failed: $error');
      }
    }
  }
}

/// What `submit-assessment` reported back for one specialisation.
class AssessmentOutcome {
  const AssessmentOutcome({
    required this.passed,
    required this.score,
    required this.correctCount,
    required this.totalQuestions,
    required this.attemptNumber,
    this.track,
    this.specializationsVerified = 0,
    this.skillLevel,
    this.retakeAvailableAt,
  });

  factory AssessmentOutcome.fromJson(Map<String, dynamic> json) {
    return AssessmentOutcome(
      passed: json['passed'] as bool? ?? false,
      score: (json['score'] as num?)?.toDouble() ?? 0,
      correctCount: json['correct_count'] as int? ?? 0,
      totalQuestions: json['total_questions'] as int? ?? 0,
      attemptNumber: json['attempt_number'] as int? ?? 1,
      track: AssessmentTrack.fromWire(json['track'] as String?),
      specializationsVerified: json['specializations_verified'] as int? ?? 0,
      skillLevel: SkillLevel.fromWire(json['skill_level'] as String?),
      retakeAvailableAt: DateTime.tryParse(
        json['retake_available_at'] as String? ?? '',
      ),
    );
  }

  final bool passed;
  final double score;
  final int correctCount;
  final int totalQuestions;
  final int attemptNumber;

  /// Which track was sat.
  final AssessmentTrack? track;

  /// How many (device, brand) rows this one pass verified. The number that
  /// makes the grouping worth having.
  final int specializationsVerified;

  /// Awarded only on a pass: 90+ expert, 70-89 intermediate.
  final SkillLevel? skillLevel;

  /// When a failed attempt may be retried.
  final DateTime? retakeAvailableAt;

  String get scoreLabel => '${score.round()}%';

  /// How far short a failed attempt fell.
  int get pointsShort =>
      passed ? 0 : (SkillLevel.passMark - score).ceil().clamp(0, 100);
}
