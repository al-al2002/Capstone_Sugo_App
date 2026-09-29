import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../rb_cars/services/rb_cars_service.dart';

/// Reads and writes what the one-time profile setup collects.
///
/// Every write here is a plain PostgREST call under the account's own session:
///
///   * `profiles` - "Profiles are updatable by their owner". The guard trigger
///     on that table freezes registration status, role and completion time, so
///     nothing written here can move an account's standing.
///   * `technicians` - `technicians_update_own`. Its guard freezes verification,
///     tier, badge, rating, job count and workload, and leaves the shop columns
///     writable, which is exactly the split this needs.
///   * `avatars` storage - own `<uid>/` folder only (20260917000003).
///
/// No function is needed because no rule here is stronger than "your own row".
class ProfileSetupService {
  ProfileSetupService({SupabaseClient? client})
    : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  static const String _bucket = 'avatars';

  String get _uid {
    final String? id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const RbCarsFailure('Please sign in again to continue.');
    }
    return id;
  }

  /// The technician's current workshop, to prefill the form. Null for a client.
  Future<({String? name, double? latitude, double? longitude})?> workshop() async {
    try {
      final Map<String, dynamic>? row = await _client
          .from('technicians')
          .select('shop_name, shop_latitude, shop_longitude')
          .eq('id', _uid)
          .maybeSingle();
      if (row == null) return null;
      return (
        name: row['shop_name'] as String?,
        latitude: (row['shop_latitude'] as num?)?.toDouble(),
        longitude: (row['shop_longitude'] as num?)?.toDouble(),
      );
    } catch (error) {
      _log('workshop', error);
      return null;
    }
  }

  /// Uploads [photo] as the account's avatar and returns its public URL.
  ///
  /// Always the same path, `<uid>/avatar.<ext>`, overwritten on change: an
  /// account has one photo, and a timestamped path would leave every previous
  /// photo behind in the bucket forever.
  ///
  /// The returned URL carries a `?v=` version because the path does not change.
  /// Without it, every `Image.network` that already showed the old photo keeps
  /// serving it from cache and the new one seems not to have saved.
  Future<String> uploadAvatar(XFile photo) async {
    final String uid = _uid;
    final String ext = _extension(photo);
    final String path = '$uid/avatar.$ext';

    try {
      await _client.storage.from(_bucket).uploadBinary(
        path,
        await photo.readAsBytes(),
        fileOptions: FileOptions(upsert: true, contentType: _mime(ext)),
      );
    } on StorageException catch (error) {
      _log('uploadAvatar', error);
      throw RbCarsFailure(
        error.statusCode == '413'
            ? 'That photo is too large. Choose one under 2 MB.'
            : 'Could not upload your photo. Please try again.',
      );
    }

    final String url = _client.storage.from(_bucket).getPublicUrl(path);
    return '$url?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Saves what the form collected. Any argument left null is left unchanged.
  ///
  /// [markComplete] stamps `profile_setup_completed_at`, which is what stops the
  /// router sending the account back here. The edit screen passes false: it is
  /// reached from Profile by someone who already finished the step.
  Future<void> save({
    String? avatarUrl,
    String? shopName,
    double? shopLatitude,
    double? shopLongitude,
    required bool isTechnician,
    required bool markComplete,
  }) async {
    final String uid = _uid;

    try {
      final Map<String, dynamic> profile = <String, dynamic>{
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (markComplete)
          'profile_setup_completed_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (profile.isNotEmpty) {
        await _client.from('profiles').update(profile).eq('id', uid);
      }

      if (isTechnician) {
        final String? trimmed = shopName?.trim();
        final Map<String, dynamic> shop = <String, dynamic>{
          if (trimmed != null) 'shop_name': trimmed.isEmpty ? null : trimmed,
          if (shopLatitude != null && shopLongitude != null) ...<String, dynamic>{
            'shop_latitude': shopLatitude,
            'shop_longitude': shopLongitude,
          },
        };
        if (shop.isNotEmpty) {
          await _client.from('technicians').update(shop).eq('id', uid);
        }
      }
    } on PostgrestException catch (error) {
      _log('save', error);
      throw const RbCarsFailure('Could not save your profile. Please try again.');
    }
  }

  static String _extension(XFile file) {
    final String name = file.name.isNotEmpty ? file.name : file.path;
    final String candidate =
        name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return switch (candidate) {
      'png' => 'png',
      'webp' => 'webp',
      // Everything else is labelled JPEG. The screen picks with an
      // `imageQuality`, which makes image_picker re-encode to JPEG on Android
      // and iOS, so a HEIC original normally arrives as JPEG bytes. The bucket
      // does not accept HEIC, so it is never labelled as such.
      _ => 'jpg',
    };
  }

  static String _mime(String ext) => switch (ext) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };

  void _log(String action, Object error) {
    if (kDebugMode) debugPrint('ProfileSetupService.$action failed: $error');
  }
}
