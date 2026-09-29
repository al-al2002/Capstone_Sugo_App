import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../models/job_dispute.dart';

/// Reports a problem with a booking, and reads back what SUGO decided.
///
/// ## The rules live in the database
///
/// `open_job_dispute()` (migration 20260928000001) is the only way in: it
/// checks that the caller is the client or the assigned technician, that the
/// job has been taken and is not more than 7 days past completion, and that
/// they have no report already open. When it refuses, its message is written
/// for the person reading it, so this service passes it through unchanged
/// rather than replacing it with a vaguer one.
class DisputeService {
  DisputeService({SupabaseClient? client})
    : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  static const String _bucket = 'dispute-photos';
  static const int _maxPhotoBytes = 5 * 1024 * 1024;
  static const int _signedUrlSeconds = 3600;

  /// Every report on [jobId] the caller may see - theirs and the other
  /// side's - newest first. RLS limits it to the two people on the job.
  Future<List<JobDispute>> forJob(String jobId) async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('job_disputes')
          .select()
          .eq('job_id', jobId)
          .order('created_at', ascending: false);
      return rows.map(JobDispute.fromJson).toList(growable: false);
    } catch (error) {
      _log('forJob', error);
      // Reading reports is never allowed to break the booking screen.
      return const <JobDispute>[];
    }
  }

  /// Uploads [photos], then opens the report. Returns the new row.
  Future<JobDispute> open({
    required String jobId,
    required DisputeReason reason,
    required String details,
    List<XFile> photos = const <XFile>[],
  }) async {
    final List<String> paths = <String>[];
    for (final XFile photo in photos) {
      paths.add(await _upload(jobId, photo));
    }

    try {
      final dynamic row = await _client.rpc(
        'open_job_dispute',
        params: <String, dynamic>{
          'p_job_id': jobId,
          'p_reason': reason.wire,
          'p_details': details.trim(),
          'p_photo_paths': paths,
        },
      );
      return JobDispute.fromJson(Map<String, dynamic>.from(row as Map));
    } on PostgrestException catch (error) {
      _log('open', error);
      // P0001 is a `raise exception` from the function: already written for
      // a person to read.
      if (error.code == 'P0001') throw RbCarsFailure(error.message);
      if (error.code == 'PGRST202' || error.code == '42883') {
        throw const RbCarsFailure(
          'Reporting a problem is not set up on the server yet. Apply the '
          'latest database migration and try again.',
        );
      }
      throw const RbCarsFailure('Could not send your report. Try again.');
    } catch (error) {
      _log('open', error);
      throw const RbCarsFailure(
        'Could not send your report. Check your connection and try again.',
      );
    }
  }

  /// A short-lived signed URL for one of a report's photos.
  Future<String> photoUrl(String path) =>
      _client.storage.from(_bucket).createSignedUrl(path, _signedUrlSeconds);

  /// `<job_id>/<timestamp>-<n>.<ext>`: the job id first, because the storage
  /// policy reads it back to decide who may upload and read.
  Future<String> _upload(String jobId, XFile file) async {
    final Uint8List bytes = await file.readAsBytes();
    if (bytes.lengthInBytes > _maxPhotoBytes) {
      throw const RbCarsFailure(
        'A photo is larger than 5 MB. Try taking it again at a lower quality.',
      );
    }

    final String extension = _extensionOf(file.name);
    final String path =
        '$jobId/${DateTime.now().microsecondsSinceEpoch}.$extension';

    try {
      await _client.storage
          .from(_bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: extension == 'png' ? 'image/png' : 'image/jpeg',
              upsert: false,
            ),
          );
      return path;
    } on StorageException catch (error) {
      _log('upload', error);
      throw const RbCarsFailure(
        'Could not upload a photo. Check your connection, or send the report '
        'without it.',
      );
    }
  }

  static String _extensionOf(String name) {
    final String lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'png';
    return 'jpg';
  }

  void _log(String action, Object error) {
    if (kDebugMode) debugPrint('DisputeService.$action failed: $error');
  }
}
