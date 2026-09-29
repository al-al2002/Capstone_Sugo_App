import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/session/session_state.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../models/assessment.dart';

/// Result of validating a picked ID file before it is uploaded.
class IdValidation {
  const IdValidation.valid() : error = null;
  const IdValidation.invalid(this.error);

  final String? error;

  bool get isValid => error == null;
}

/// Registration -> role selection -> ID -> specialization -> quiz.
///
/// ## Where each write goes, and why
///
/// * **Role choice** - direct update on `profiles`. The existing owner policy
///   already restricts it to `auth.uid()`, so no function is needed.
/// * **ID upload** - direct insert into the private `technicians-ids` bucket
///   plus a direct update on `technicians`. `technicians_update_own` allows
///   the columns involved, and the guard trigger only blocks the privileged
///   ones.
/// * **Quiz submission** - the `submit-assessment` edge function, and it has
///   to be. The client cannot read `correct_choice_index` (revoked in
///   20260906000002) so it cannot mark itself, and it cannot set `is_verified`
///   (blocked by the guard trigger in 20260905000002) so it cannot activate
///   itself either. Both restrictions are deliberate.
class OnboardingService {
  OnboardingService({SupabaseClient? client})
    : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  /// One private bucket for both roles - see migration 20260906000004.
  static const String idBucket = 'identity-documents';
  static const String _cancelFunction = 'cancel-registration';
  static const String _completeFunction = 'complete-registration';

  /// Max ID file size. Mirrors the bucket's own 5 MB limit so the client fails
  /// fast with a readable message instead of after a wasted upload.
  static const int maxIdBytes = 5 * 1024 * 1024;

  static const Set<String> _allowedExtensions = <String>{
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
  };

  /// Maps an extension to the MIME type sent with the upload.
  ///
  /// Set explicitly rather than left to inference. Supabase rejects an upload
  /// whose content type is not on the bucket's allow-list, and an inferred type
  /// can come back as `application/octet-stream` for a file the picker wrote
  /// without a clean extension - which is what made uploads fail on device with
  /// nothing but a generic error to show for it.
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

  // ---------------------------------------------------------- role selection

  /// Records the explicit role choice.
  ///
  /// `role_chosen_at` is what actually unblocks the router. `role` alone
  /// defaults to 'client', so writing it without the timestamp would leave a
  /// brand-new account indistinguishable from someone who chose Client.
  Future<void> chooseRole(UserRole role) async {
    try {
      await _client
          .from('profiles')
          .update(<String, dynamic>{
            'role': role.wire,
            'role_chosen_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', _uid);

      // A technician needs a row to hang the ID and assessment off. Created
      // here rather than at the ID step so the rest of the flow can assume it
      // exists. Defaults leave them unverified and offline, which is correct.
      if (role == UserRole.technician) {
        await _client.from('technicians').upsert(<String, dynamic>{
          'id': _uid,
        }, onConflict: 'id');
      }
    } on PostgrestException catch (error) {
      _log('chooseRole', error);
      throw RbCarsFailure(_describe(error, 'Could not save your choice.'));
    }
  }

  // -------------------------------------------------------------- ID upload

  /// Format and size checks on a picked file.
  ///
  /// Takes an [XFile] rather than a `dart:io` File, and is async as a result.
  /// That is not stylistic. On Flutter Web there is no filesystem, so
  /// `File(xfile.path)` throws at runtime and `lengthSync()` does not exist.
  /// `XFile` is the one handle that behaves the same on web, Android, iOS and
  /// desktop, reading bytes through whatever the platform actually provides.
  ///
  /// TODO(production): replace with real ID verification - OCR the document,
  /// check it against a government registry, and route it to a human reviewer.
  /// This only confirms that *something* of the right shape was submitted; it
  /// cannot tell a driver's licence from a photo of a cat.
  Future<IdValidation> validateIdFile(XFile file) async {
    final int bytes;
    try {
      bytes = await file.length();
    } catch (error) {
      _log('validateIdFile', error);
      return const IdValidation.invalid('That file could not be read.');
    }

    if (bytes == 0) {
      return const IdValidation.invalid('That file is empty.');
    }
    if (bytes > maxIdBytes) {
      final double mb = bytes / (1024 * 1024);
      return IdValidation.invalid(
        'That image is ${mb.toStringAsFixed(1)} MB. The limit is 5 MB.',
      );
    }

    if (!_allowedExtensions.contains(_extensionOf(file))) {
      return const IdValidation.invalid(
        'Only JPG and PNG images are accepted.',
      );
    }

    return const IdValidation.valid();
  }

  /// Best available extension for a picked file.
  ///
  /// On web the path is a `blob:` URL with no extension at all, so the
  /// picker's reported name and MIME type are used instead.
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

  /// Uploads an identity document and records it against the account.
  ///
  /// Written to `profiles` for every role, because a client has no
  /// `technicians` row to hang it off and identity belongs to the person rather
  /// than to what they do here. For a technician the same values are mirrored
  /// onto their `technicians` row so the two never disagree.
  ///
  /// Uploads **bytes**, not a file handle. `uploadBinary` is the only Supabase
  /// upload that works on web, where there is no filesystem for `upload()` to
  /// read from.
  ///
  /// Stores the object *path*, not a URL: the bucket is private, so nothing
  /// about an ID is readable from a guessable link.
  Future<String> uploadIdDocument(
    XFile file, {
    bool alsoTechnician = false,
  }) async {
    final IdValidation validation = await validateIdFile(file);
    if (!validation.isValid) {
      throw RbCarsFailure(validation.error!);
    }

    final String uid = _uid;
    final String extension = _extensionOf(file);
    final String contentType = _mimeTypes[extension] ?? 'image/jpeg';
    final String objectPath =
        '$uid/id_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final String submittedAt = DateTime.now().toUtc().toIso8601String();

    try {
      final Uint8List bytes = await file.readAsBytes();

      await _client.storage
          .from(idBucket)
          .uploadBinary(
            objectPath,
            bytes,
            fileOptions: FileOptions(upsert: true, contentType: contentType),
          );

      await _client
          .from('profiles')
          .update(<String, dynamic>{
            'id_document_url': objectPath,
            'id_submitted_at': submittedAt,
          })
          .eq('id', uid);

      if (alsoTechnician) {
        await _client.from('technicians').upsert(<String, dynamic>{
          'id': uid,
          'id_document_url': objectPath,
          'id_submitted_at': submittedAt,
        }, onConflict: 'id');
      }

      // TODO(production): enqueue for admin review here. For now the flow
      // continues straight on, which is what auto-approval means in practice.
      return objectPath;
    } on StorageException catch (error) {
      _log('uploadIdDocument', error);
      throw RbCarsFailure(_describeStorage(error));
    } on PostgrestException catch (error) {
      _log('uploadIdDocument', error);
      throw RbCarsFailure(_describe(error, 'Could not save your ID.'));
    }
  }

  /// Turns a storage failure into something actionable.
  String _describeStorage(StorageException error) {
    final String message = error.message.toLowerCase();

    if (message.contains('mime') || message.contains('content type')) {
      return 'That image format is not accepted. Use a JPG or PNG.';
    }
    if (message.contains('exceeded') || message.contains('too large')) {
      return 'That image is too large. The limit is 5 MB.';
    }
    if (message.contains('row-level security') ||
        message.contains('unauthorized') ||
        error.statusCode == '403') {
      return 'You are not permitted to upload right now. Sign out and back in, '
          'then try again.';
    }
    if (message.contains('not found') || error.statusCode == '404') {
      return 'The upload location is missing. Please contact support.';
    }
    return 'Could not upload that image. Check your connection and try again.';
  }

  /// Fetches the question bank for a specialisation.
  ///
  /// The select list has no `correct_choice_index` because that column's grant
  /// was revoked from `authenticated` in migration 20260906000002 - asking for
  /// it returns `permission denied` rather than the answer key.
  ///
  /// This is the only database call the registration flow makes before it
  /// commits, and it reads public reference data: no row belonging to the
  /// person being registered is created by it.
  Future<List<AssessmentQuestion>> fetchQuestions(
    Specialization specialization,
  ) async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('assessment_questions')
          .select('id, specialization, question, choices')
          .eq('specialization', specialization.wire)
          .order('created_at', ascending: true);

      return rows.map(AssessmentQuestion.fromJson).toList(growable: false);
    } on PostgrestException catch (error) {
      _log('fetchQuestions', error);
      throw const RbCarsFailure('Could not load the assessment questions.');
    }
  }

  /// Removes an uploaded ID that is no longer wanted.
  ///
  /// Storage is not part of the database transaction, so the file has to go up
  /// before the commit. When the commit then fails - a failed assessment, a
  /// dropped connection - this deletes the orphan so retries do not leave a
  /// pile of abandoned documents in the bucket.
  Future<void> discardIdDocument(String objectPath) async {
    try {
      await _client.storage.from(idBucket).remove(<String>[objectPath]);
    } catch (error) {
      // Best effort. A leftover object is untidy, not harmful: the bucket is
      // private and nothing references the path.
      _log('discardIdDocument', error);
    }
  }

  /// Commits the entire registration in one call.
  ///
  /// Everything the flow collected is sent together, and the
  /// `complete-registration` edge function writes it inside a single database
  /// transaction - or, for a technician who fails the assessment, writes
  /// nothing at all and reports the score back for a retry.
  Future<RegistrationOutcome> completeRegistration({
    required UserRole role,
    required String idDocumentUrl,
    String? fullName,
    String? phone,
    Specialization? specialization,
    Map<String, int> answers = const <String, int>{},
  }) async {
    try {
      final FunctionResponse response = await _client.functions.invoke(
        _completeFunction,
        body: <String, dynamic>{
          'role': role.wire,
          'id_document_url': idDocumentUrl,
          if (fullName != null) 'full_name': fullName,
          if (phone != null) 'phone': phone,
          if (specialization != null) 'specialization': specialization.wire,
          if (answers.isNotEmpty) 'answers': answers,
        },
      );

      final Object? data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const RbCarsFailure('The server returned an unexpected reply.');
      }
      if (data['error'] != null) {
        throw RbCarsFailure(data['error'].toString());
      }

      return RegistrationOutcome(
        completed: data['completed'] as bool? ?? false,
        result: data.containsKey('score')
            ? AssessmentResult.fromJson(data)
            : null,
      );
    } on FunctionException catch (error) {
      _log('completeRegistration', error);
      final Object? details = error.details;
      if (details is Map && details['error'] is String) {
        throw RbCarsFailure(details['error'] as String);
      }
      throw const RbCarsFailure('Could not finish your registration.');
    } on RbCarsFailure {
      rethrow;
    } catch (error) {
      _log('completeRegistration', error);
      throw const RbCarsFailure(
        'Could not reach the server. Check your connection and try again.',
      );
    }
  }

  // ------------------------------------------------- finishing / abandoning

  /// Stamps `onboarding_completed_at` the first time an account reaches a
  /// dashboard.
  ///
  /// This is what takes the account out of the purge set. Written from the
  /// client rather than inferred server-side because "finished" differs by
  /// role, and the router already knows which dashboard it is about to show -
  /// re-deriving that in SQL would be a second copy of the same rule.
  ///
  /// Idempotent: the update only touches rows where the column is still null,
  /// so a returning user does not have their original completion time
  /// overwritten on every launch.
  Future<void> markOnboardingComplete() async {
    try {
      await _client
          .from('profiles')
          .update(<String, dynamic>{
            'onboarding_completed_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', _uid)
          .isFilter('onboarding_completed_at', null);
    } on PostgrestException catch (error) {
      // Never fatal. Failing to stamp completion means the account stays in
      // the purge set for now, and the next launch retries - far better than
      // blocking someone from their dashboard over bookkeeping.
      _log('markOnboardingComplete', error);
    }
  }

  /// Deletes the caller's own account, while registration is still unfinished.
  ///
  /// Goes through the `cancel-registration` edge function because removing an
  /// `auth.users` row needs the admin API, which only the service role has.
  /// The function refuses if onboarding is already complete, and the database's
  /// own foreign keys refuse if any bookings are attached.
  Future<void> cancelRegistration() async {
    try {
      final FunctionResponse response = await _client.functions.invoke(
        _cancelFunction,
      );

      final Object? data = response.data;
      if (data is Map<String, dynamic> && data['error'] != null) {
        throw RbCarsFailure(data['error'].toString());
      }

      // The account is gone, so the local session is meaningless. Signing out
      // clears it and drops the app back to the auth screen.
      await _client.auth.signOut();
    } on FunctionException catch (error) {
      _log('cancelRegistration', error);
      final Object? details = error.details;
      if (details is Map && details['error'] is String) {
        throw RbCarsFailure(details['error'] as String);
      }
      throw const RbCarsFailure('Could not cancel your registration.');
    } on RbCarsFailure {
      rethrow;
    } catch (error) {
      _log('cancelRegistration', error);
      throw const RbCarsFailure(
        'Could not reach the server. Check your connection and try again.',
      );
    }
  }

  // ------------------------------------------------------------- portfolio

  /// Adds a portfolio item. Optional and skippable - it never gates access.
  ///
  /// Photos go in the public `job-photos` bucket rather than a third bucket,
  /// since portfolio work is promotional and meant to be seen by clients.
  Future<void> addPortfolioItem({XFile? photo, String? description}) async {
    final String uid = _uid;
    String? photoUrl;

    try {
      if (photo != null) {
        final String extension = _extensionOf(photo);
        final String objectPath =
            '$uid/portfolio_${DateTime.now().millisecondsSinceEpoch}.$extension';

        await _client.storage
            .from(RbCarsService.photoBucket)
            .uploadBinary(
              objectPath,
              await photo.readAsBytes(),
              fileOptions: FileOptions(
                contentType: _mimeTypes[extension] ?? 'image/jpeg',
              ),
            );

        photoUrl = _client.storage
            .from(RbCarsService.photoBucket)
            .getPublicUrl(objectPath);
      }

      await _client.from('technician_portfolio').insert(<String, dynamic>{
        'technician_id': uid,
        'photo_url': photoUrl,
        'description': description,
      });
    } on StorageException catch (error) {
      _log('addPortfolioItem', error);
      throw const RbCarsFailure('Could not upload that photo.');
    } on PostgrestException catch (error) {
      _log('addPortfolioItem', error);
      throw const RbCarsFailure('Could not save that portfolio item.');
    }
  }

  /// Turns a Postgres error into something a user can act on.
  ///
  /// The generic "please retry" message that used to be thrown here hid a real
  /// bug for a whole test cycle: `technicians` had no INSERT policy, so
  /// choosing the technician role failed with a permission error that looked
  /// like a network blip. Naming the failure class makes that visible.
  String _describe(PostgrestException error, String fallback) {
    final String message = error.message.toLowerCase();

    if (message.contains('row-level security') ||
        message.contains('violates row-level security policy') ||
        error.code == '42501') {
      return '$fallback Your account is not permitted to do that yet - '
          'this usually means a database policy is missing.';
    }
    if (message.contains('violates check constraint')) {
      return '$fallback Some of those values are not valid.';
    }
    if (message.contains('duplicate key')) {
      return '$fallback That record already exists.';
    }
    if (message.contains('foreign key')) {
      return '$fallback Your profile could not be found.';
    }
    return '$fallback Please try again.';
  }

  void _log(String action, Object error) {
    if (kDebugMode) {
      // The full Postgres message, including the policy name, so a failure is
      // diagnosable from the debug console rather than only from the UI copy.
      if (error is PostgrestException) {
        debugPrint(
          'OnboardingService.$action failed: [${error.code}] ${error.message}'
          '${error.details != null ? ' | ${error.details}' : ''}',
        );
      } else {
        debugPrint('OnboardingService.$action failed: $error');
      }
    }
  }
}

/// What `complete-registration` reported back.
class RegistrationOutcome {
  const RegistrationOutcome({required this.completed, this.result});

  /// True when the account now exists. False means nothing was written -
  /// currently only when a technician fails the assessment.
  final bool completed;

  /// The score, present for any technician submission, pass or fail.
  final AssessmentResult? result;
}
