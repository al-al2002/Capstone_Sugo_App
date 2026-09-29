import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/session/session_state.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../../technician/services/onboarding_service.dart';
import '../models/identity_verification.dart';
import '../models/registration_status.dart';

/// Uploads and files the mandatory ID + selfie submission, for both roles.
///
/// ## Why this is one service and not two
///
/// The technician and client flows submit the identical thing to the identical
/// table. Splitting it per role is how the two would end up with different
/// validation rules, and "the client check was weaker than the technician one"
/// is not a sentence anyone wants to say at a defence.
///
/// ## What it does not do
///
/// **It does not verify anything.** It checks that two images of a plausible
/// size and format were supplied and files them for a human to look at. It
/// cannot tell whether the face in the selfie matches the face on the ID, or
/// whether the ID is real. Those judgements are the reviewer's, and the
/// `pending` status exists precisely because the app cannot make them.
///
/// A production system would add an automated pre-screen here - a face-match
/// API and document OCR - to reject the obvious failures before they reach a
/// human. That is a deliberate omission, not an oversight: see the TODO on
/// [submit].
class IdentityVerificationService {
  IdentityVerificationService({SupabaseClient? client})
    : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  /// The private bucket from migration 20260906000004. Shared with the
  /// existing [OnboardingService] deliberately - a selfie holding an ID is
  /// exactly as sensitive as the ID, so it belongs under the same policies.
  static const String bucket = OnboardingService.idBucket;

  /// Matches the bucket's cap, raised to 10 MB in migration 20260907000002
  /// because a camera selfie is larger than a scanned document.
  static const int maxBytes = 10 * 1024 * 1024;

  /// How long a signed URL for a private document stays valid.
  ///
  /// Five minutes: long enough to load the image on a slow connection, short
  /// enough that a URL copied out of a debug log or a screen recording is dead
  /// before it is useful.
  static const int signedUrlTtlSeconds = 300;

  static const Set<String> _allowedExtensions = <String>{
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
  };

  static const Map<String, String> _mimeTypes = <String, String>{
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'heic': 'image/heic',
  };

  String get _uid {
    final String? id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const RbCarsFailure('Please sign in again to continue.');
    }
    return id;
  }

  // ------------------------------------------------------------- validation

  /// Checks both images and reports per-image errors.
  ///
  /// Both are validated even when the first already failed, so the user fixes
  /// everything in one pass instead of discovering the second problem only
  /// after correcting the first.
  Future<IdentityValidation> validate(IdentityCapture capture) async {
    return IdentityValidation(
      idDocumentError: await _validateOne(capture.idDocument, 'ID photo'),
      selfieError: await _validateOne(capture.selfie, 'selfie'),
    );
  }

  Future<String?> _validateOne(XFile? file, String noun) async {
    if (file == null) return null; // Absence is handled by the step's gate.

    final int bytes;
    try {
      bytes = await file.length();
    } catch (error) {
      _log('validate', error);
      return 'That $noun could not be read. Try picking it again.';
    }

    if (bytes == 0) return 'That $noun is empty.';
    if (bytes > maxBytes) {
      final double mb = bytes / (1024 * 1024);
      return 'That $noun is ${mb.toStringAsFixed(1)} MB. The limit is 10 MB.';
    }

    // A file this small cannot hold a legible photo of a document. The check
    // catches a placeholder or a broken capture before a reviewer wastes a
    // queue slot rejecting it.
    if (bytes < 15 * 1024) {
      return 'That $noun looks too small to be readable. Take a clearer photo.';
    }

    if (!_allowedExtensions.contains(_extensionOf(file))) {
      return 'Only JPG and PNG images are accepted for your $noun.';
    }

    return null;
  }

  /// Best available extension. On web the path is a `blob:` URL with no
  /// extension, so the picker's reported name and MIME type are used instead.
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
      _ => 'jpg',
    };
  }

  // ----------------------------------------------------------------- submit

  /// Uploads both images and files one submission for review.
  ///
  /// ## Ordering, and what happens when it goes wrong
  ///
  /// Storage is not part of the database transaction. Both images therefore go
  /// up first, and only then is the row inserted. If the insert fails, both
  /// objects are deleted before the error is rethrown - otherwise a user
  /// retrying on a bad connection leaves a pile of orphaned identity documents
  /// in a bucket nobody ever cleans.
  ///
  /// The reverse order would be worse: a row pointing at an object that failed
  /// to upload puts a broken image in front of a reviewer, who would reject an
  /// applicant for an infrastructure fault.
  ///
  /// TODO(production): pre-screen before this reaches a human. Run a face-match
  /// between the selfie and the ID portrait, and OCR the document to confirm it
  /// is a recognised Philippine government ID that has not expired. Reject the
  /// obvious failures automatically so the review queue only sees genuine
  /// judgement calls.
  Future<IdentityVerification> submit({
    required IdentityCapture capture,
    required UserRole role,
  }) async {
    if (!capture.isComplete) {
      // Defence in depth. The UI gate should make this unreachable, and the
      // `not null` columns would reject it anyway - but failing here gives a
      // readable message instead of a Postgres constraint violation.
      throw RbCarsFailure(capture.missingLabel ?? 'Both images are required.');
    }

    final IdentityValidation validation = await validate(capture);
    if (!validation.isValid) {
      throw RbCarsFailure(
        validation.idDocumentError ?? validation.selfieError!,
      );
    }

    final String uid = _uid;
    final int stamp = DateTime.now().millisecondsSinceEpoch;
    final List<String> uploaded = <String>[];

    try {
      final String idPath = await _upload(
        capture.idDocument!,
        '$uid/id_$stamp',
      );
      uploaded.add(idPath);

      final String selfiePath = await _upload(
        capture.selfie!,
        '$uid/selfie_$stamp',
      );
      uploaded.add(selfiePath);

      final Map<String, dynamic> row = await _client
          .from('identity_verifications')
          .insert(<String, dynamic>{
            'user_id': uid,
            'role': role.wire,
            'id_document_url': idPath,
            'selfie_with_id_url': selfiePath,
            // `status` is omitted rather than sent as 'pending'. The insert
            // policy requires it to be 'pending', and letting the column
            // default supply it means the app has no say in the matter at all.
          })
          .select()
          .single();

      return IdentityVerification.fromJson(row);
    } on StorageException catch (error) {
      await _cleanUp(uploaded);
      _log('submit', error);
      throw RbCarsFailure(_describeStorage(error));
    } on PostgrestException catch (error) {
      await _cleanUp(uploaded);
      _log('submit', error);

      // The partial unique index from migration 20260907000002. Hitting it
      // means a submission is already queued, which is a success from the
      // user's point of view rather than a failure.
      if (error.code == '23505') {
        throw const RbCarsFailure(
          'You already have an ID submission waiting for review.',
        );
      }
      throw RbCarsFailure(_describe(error, 'Could not submit your ID.'));
    } catch (error) {
      await _cleanUp(uploaded);
      _log('submit', error);
      throw const RbCarsFailure(
        'Could not submit your ID. Check your connection and try again.',
      );
    }
  }

  Future<String> _upload(XFile file, String basePath) async {
    final String extension = _extensionOf(file);
    final String objectPath = '$basePath.$extension';

    // `uploadBinary`, not `upload`: on web there is no filesystem for a
    // path-based upload to read from.
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

    return objectPath;
  }

  /// Best-effort removal of objects whose database row never landed.
  ///
  /// Deliberately swallows its own errors: this runs while another failure is
  /// already propagating, and replacing a meaningful error with "cleanup
  /// failed" would hide the real problem.
  Future<void> _cleanUp(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await _client.storage.from(bucket).remove(paths);
    } catch (error) {
      _log('cleanUp', error);
    }
  }

  // ------------------------------------------------------------------ reads

  /// The most recent submission, or null if there has never been one.
  Future<IdentityVerification?> latest() async {
    try {
      final Map<String, dynamic>? row = await _client
          .from('identity_verifications')
          .select()
          .eq('user_id', _uid)
          .order('submitted_at', ascending: false)
          .limit(1)
          .maybeSingle();

      return row == null ? null : IdentityVerification.fromJson(row);
    } on PostgrestException catch (error) {
      _log('latest', error);
      throw const RbCarsFailure('Could not load your verification status.');
    }
  }

  /// Every attempt, newest first. Used by the review screen to explain a
  /// repeated rejection.
  Future<List<IdentityVerification>> history() async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('identity_verifications')
          .select()
          .eq('user_id', _uid)
          .order('submitted_at', ascending: false);

      return rows.map(IdentityVerification.fromJson).toList(growable: false);
    } on PostgrestException catch (error) {
      _log('history', error);
      return const <IdentityVerification>[];
    }
  }

  /// A short-lived URL for a private object, so the user can review what they
  /// submitted without the bucket ever becoming public.
  Future<String?> signedUrl(String objectPath) async {
    if (objectPath.isEmpty) return null;
    try {
      return await _client.storage
          .from(bucket)
          .createSignedUrl(objectPath, signedUrlTtlSeconds);
    } catch (error) {
      _log('signedUrl', error);
      return null;
    }
  }

  // --------------------------------------------------------- status writing

  /// Records how far through the stepper the user has got.
  ///
  /// Never fatal. Failing to save a resume point costs the user a step or two
  /// of re-navigation on their next visit; blocking them from continuing over
  /// it would cost far more.
  Future<void> saveStep(OnboardingStepId step) async {
    try {
      await _client
          .from('profiles')
          .update(<String, dynamic>{'registration_step': step.wire})
          .eq('id', _uid);
    } on PostgrestException catch (error) {
      _log('saveStep', error);
    }
  }

  /// Reads the account status and resume point in one round trip.
  Future<({RegistrationStatus status, OnboardingStepId? step})>
  loadProgress() async {
    try {
      final Map<String, dynamic> row = await _client
          .from('profiles')
          .select('registration_status, registration_step')
          .eq('id', _uid)
          .single();

      return (
        status: RegistrationStatus.fromWire(
          row['registration_status'] as String?,
        ),
        step: OnboardingStepId.fromWire(row['registration_step'] as String?),
      );
    } on PostgrestException catch (error) {
      _log('loadProgress', error);
      // Falling back to "incomplete, no saved step" restarts the stepper from
      // the beginning, which is recoverable. Assuming `active` on a read
      // failure would let an unverified account into the app.
      return (status: RegistrationStatus.incomplete, step: null);
    }
  }

  String _describeStorage(StorageException error) {
    final String message = error.message.toLowerCase();

    if (message.contains('mime') || message.contains('content type')) {
      return 'That image format is not accepted. Use a JPG or PNG.';
    }
    if (message.contains('exceeded') || message.contains('too large')) {
      return 'That image is too large. The limit is 10 MB.';
    }
    if (message.contains('row-level security') ||
        message.contains('unauthorized') ||
        error.statusCode == '403') {
      return 'You are not permitted to upload right now. Sign out and back '
          'in, then try again.';
    }
    return 'Could not upload your photos. Check your connection and try again.';
  }

  String _describe(PostgrestException error, String fallback) {
    final String message = error.message.toLowerCase();

    if (message.contains('row-level security') || error.code == '42501') {
      return '$fallback Your account is not permitted to do that yet - '
          'this usually means a database policy is missing.';
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
          'IdentityVerificationService.$action failed: '
          '[${error.code}] ${error.message}'
          '${error.details != null ? ' | ${error.details}' : ''}',
        );
      } else {
        debugPrint('IdentityVerificationService.$action failed: $error');
      }
    }
  }
}
