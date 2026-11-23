import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../models/job_evidence.dart';

/// A location fix for the stamp, or null when location is off or slow.
typedef EvidenceLocator = Future<({double latitude, double longitude, double accuracy})?> Function();

/// Reads and adds to a job's work record (in-task documentation, migration
/// 20261122000002).
///
/// ## The rules live in the database
///
/// `add_job_evidence()` is the only way in: the assigned technician, while the
/// job is under way, 1-4 photos already uploaded into this job's folder, the
/// unit-as-found step before "after". Its refusals are written for a person,
/// so they are passed through unchanged. `job_evidence_missing()` says which
/// required steps are left, and `job-response` will not complete the job
/// until there are none.
class JobEvidenceService {
  JobEvidenceService({SupabaseClient? client, EvidenceLocator? locate})
    : _injectedClient = client,
      _locate = locate ?? _deviceLocation;

  final SupabaseClient? _injectedClient;
  final EvidenceLocator _locate;

  /// Resolved on first use, inside each call's error handling, so a screen
  /// that never touches the work record - or a test without Supabase - is
  /// never broken by constructing this service.
  SupabaseClient get _client => _injectedClient ?? SupabaseService.client;

  static const String bucket = 'job-evidence';
  static const int _maxPhotoBytes = 5 * 1024 * 1024;
  static const int _signedUrlSeconds = 3600;

  /// Every checkpoint on [jobId], oldest first. RLS limits it to the client
  /// and the technician on the job. Never throws: a failed read shows an
  /// empty record rather than breaking the booking screen.
  Future<List<JobEvidence>> forJob(String jobId) async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('job_evidence')
          .select()
          .eq('job_id', jobId)
          .order('captured_at');
      return rows.map(JobEvidence.fromJson).toList(growable: false);
    } catch (error) {
      _log('forJob', error);
      return const <JobEvidence>[];
    }
  }

  /// The required steps still missing on [jobId], from the server. Empty when
  /// done or exempt; null when it could not be checked (then the server's
  /// own check at completion is the safety net).
  Future<List<EvidenceMilestone>?> missing(String jobId) async {
    try {
      final dynamic result = await _client.rpc(
        'job_evidence_missing',
        params: <String, dynamic>{'p_job_id': jobId},
      );
      if (result is! List) return null;
      return <EvidenceMilestone>[
        for (final Object? m in result)
          if (EvidenceMilestone.fromWire(m) case final EvidenceMilestone step) step,
      ];
    } catch (error) {
      _log('missing', error);
      return null;
    }
  }

  /// Uploads [photos], stamps the location, and saves the checkpoint.
  Future<JobEvidence> add({
    required String jobId,
    required EvidenceMilestone milestone,
    required List<XFile> photos,
    String? note,
  }) async {
    if (photos.isEmpty || photos.length > 4) {
      throw const RbCarsFailure('Add between 1 and 4 photos.');
    }

    // The location stamp, taken before uploading. It has its own 8-second
    // limit, so a slow GPS fix cannot hold the save up for long.
    final ({double latitude, double longitude, double accuracy})? fix =
        await _locate();

    final List<String> paths = <String>[];
    for (final XFile photo in photos) {
      paths.add(await _upload(jobId, photo));
    }

    try {
      final dynamic row = await _client.rpc(
        'add_job_evidence',
        params: <String, dynamic>{
          'p_job_id': jobId,
          'p_milestone': milestone.wire,
          'p_photo_paths': paths,
          'p_note': (note?.trim().isEmpty ?? true) ? null : note!.trim(),
          'p_latitude': fix?.latitude,
          'p_longitude': fix?.longitude,
          'p_accuracy_m': fix?.accuracy,
        },
      );
      return JobEvidence.fromJson(Map<String, dynamic>.from(row as Map));
    } on PostgrestException catch (error) {
      _log('add', error);
      // P0001 is a `raise exception` from the function, already written for
      // the person reading it.
      if (error.code == 'P0001') throw RbCarsFailure(error.message);
      if (error.code == 'PGRST202' || error.code == '42883') {
        throw const RbCarsFailure(
          'The work record is not set up on the server yet. Apply the latest '
          'database migration and try again.',
        );
      }
      throw const RbCarsFailure('Could not save the photos. Try again.');
    } catch (error) {
      _log('add', error);
      throw const RbCarsFailure(
        'Could not save the photos. Check your connection and try again.',
      );
    }
  }

  /// A short-lived signed URL for one of the record's photos.
  Future<String> photoUrl(String path) async =>
      _client.storage.from(bucket).createSignedUrl(path, _signedUrlSeconds);

  /// `<job_id>/<micros>.<ext>`: the job id first, because the storage policy
  /// reads it back to decide who may upload and read.
  Future<String> _upload(String jobId, XFile file) async {
    final Uint8List bytes = await file.readAsBytes();
    if (bytes.lengthInBytes > _maxPhotoBytes) {
      throw const RbCarsFailure(
        'A photo is larger than 5 MB. Take it again at a lower quality.',
      );
    }

    final String extension = file.name.toLowerCase().endsWith('.png')
        ? 'png'
        : 'jpg';
    final String path =
        '$jobId/${DateTime.now().microsecondsSinceEpoch}.$extension';

    try {
      await _client.storage
          .from(bucket)
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
        'Could not upload a photo. Check your connection and try again.',
      );
    }
  }

  /// The phone's position, asking for permission once if needed. Null - not
  /// an error - when location is off, refused, or slower than 8 seconds: the
  /// record still saves, and says the location was not recorded.
  static Future<({double latitude, double longitude, double accuracy})?>
  _deviceLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return (
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );
    } catch (error) {
      if (kDebugMode) debugPrint('JobEvidenceService.location failed: $error');
      return null;
    }
  }

  void _log(String action, Object error) {
    if (kDebugMode) debugPrint('JobEvidenceService.$action failed: $error');
  }
}
