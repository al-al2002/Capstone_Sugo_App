import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../models/technician.dart';
import '../models/technician_profile_details.dart';
import 'rb_cars_service.dart';

/// Reads the technician directory through the `technician-directory` edge
/// function.
///
/// It has to go through a function rather than a plain select: the
/// `technicians_select_own` policy restricts the table to `id = auth.uid()`, so
/// a direct query from a client returns nothing. The function runs on the
/// service role, returns only verified technicians, and strips the fields a
/// browsing client should not see - `current_workload`, and `phone` unless the
/// caller actually has a booking with that technician.
class TechnicianDirectoryService {
  TechnicianDirectoryService({SupabaseClient? client})
    : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  static const String _function = 'technician-directory';

  /// Technicians for the dashboard's "Recommended" row: the general best
  /// performers, ranked rating DESC then completed jobs DESC.
  ///
  /// [latitude] and [longitude] are the *client's* position and are used for
  /// display only. They do not filter and they do not sort - the RPC's ORDER BY
  /// does not mention distance. Pass neither and the cards simply carry no
  /// distance line, which is the correct outcome when we do not know where the
  /// client is.
  ///
  /// THERE IS NO `deviceType` PARAMETER, and that is deliberate. This row
  /// answers "who is good?", not "who can fix my laptop?" - the second question
  /// is [forJob]. The parameter used to exist and is removed rather than left
  /// unused so the dashboard cannot be filtered by specialisation by accident.
  Future<List<Technician>> recommended({
    int limit = 10,
    double? latitude,
    double? longitude,
  }) async {
    final List<dynamic> rows = await _rpc('recommended_technicians', <String, dynamic>{
      'p_client_lat': latitude,
      'p_client_lng': longitude,
      'p_limit': limit,
    });

    return _withAwayStatus(
      rows
          .whereType<Map<String, dynamic>>()
          .map(Technician.fromJson)
          .toList(growable: false),
    );
  }

  /// Every verified technician, for the "Find a technician" directory.
  ///
  /// Uses the `technician-directory` edge function's `list` action, which has
  /// existed since the function was written but had no caller in the app once
  /// the dashboard row moved to the thresholded RPC. Unlike [recommended] it
  /// applies no job-count bar - a newcomer is listed, ranked below the
  /// established - which is what a directory a client *searches* should do.
  ///
  /// [deviceType] narrows to one specialisation server-side. Distance is
  /// computed by the function from the coordinates passed, and the client's
  /// own position never leaves the request.
  Future<List<Technician>> browse({
    String? deviceType,
    int limit = 50,
    double? latitude,
    double? longitude,
  }) async {
    final bool hasOrigin = latitude != null && longitude != null;
    final Map<String, dynamic> data = await _invoke(<String, dynamic>{
      'action': 'list',
      'limit': limit,
      if (deviceType != null) 'device_type': deviceType,
      if (hasOrigin) 'latitude': latitude,
      if (hasOrigin) 'longitude': longitude,
    });

    final List<dynamic> rows =
        (data['technicians'] as List<dynamic>?) ?? const <dynamic>[];
    return _withAwayStatus(
      rows
          .whereType<Map<String, dynamic>>()
          .map(Technician.fromJson)
          .toList(growable: false),
    );
  }

  /// Technicians qualified for one posted job.
  ///
  /// The first three carry `isTopMatch` and ranks 1-3: near, well rated, and
  /// matching the job's device. Everyone else with the same specialisation
  /// follows at rank 4+, including technicians with few or no completed jobs -
  /// they are ranked lower, never filtered out.
  ///
  /// Distance is measured from the *job* address, not from wherever the client
  /// happens to be browsing, so no coordinates are passed: the RPC reads them
  /// from the job row it already loaded.
  ///
  /// The caller must own [jobId]. The RPC re-checks this itself - it runs as
  /// its owner and so cannot rely on `jobs_client_select_own` - and raises if
  /// the job belongs to someone else.
  Future<List<Technician>> forJob(String jobId, {int limit = 20}) async {
    final List<dynamic> rows = await _rpc(
      'match_technicians_for_job',
      <String, dynamic>{'p_job_id': jobId, 'p_limit': limit},
    );

    return _withAwayStatus(
      rows
          .whereType<Map<String, dynamic>>()
          .map(Technician.fromJson)
          .toList(growable: false),
    );
  }

  /// Full profile behind a card tap: specialisation badges, portfolio, star
  /// breakdown, the first page of reviews and the total job count.
  Future<TechnicianProfileDetails> profile(
    String technicianId, {
    double? latitude,
    double? longitude,
    int reviewLimit = 20,
  }) async {
    final Object? data = await _rpcRaw('technician_profile', <String, dynamic>{
      'p_technician_id': technicianId,
      'p_client_lat': latitude,
      'p_client_lng': longitude,
      'p_review_limit': reviewLimit,
    });

    if (data is! Map<String, dynamic>) {
      throw const RbCarsFailure('That technician is no longer listed.');
    }
    final TechnicianProfileDetails details = TechnicianProfileDetails.fromJson(
      data,
    );
    final List<Technician> merged = await _withAwayStatus(<Technician>[
      details.technician,
    ]);
    return details.withTechnician(merged.single);
  }

  /// The next page of reviews, oldest-ward of [before].
  ///
  /// Keyset paging, not offset: pass the `createdAt` of the last review already
  /// on screen. A profile that receives a new review mid-scroll would, under
  /// OFFSET, shift every later page by one and show the reader a duplicate.
  Future<List<TechnicianReview>> reviews(
    String technicianId, {
    DateTime? before,
    int limit = 20,
  }) async {
    final List<dynamic> rows = await _rpc(
      'technician_reviews',
      <String, dynamic>{
        'p_technician_id': technicianId,
        'p_before': before?.toUtc().toIso8601String(),
        'p_limit': limit,
      },
    );

    return rows
        .whereType<Map<String, dynamic>>()
        .map(TechnicianReview.fromJson)
        .toList(growable: false);
  }

  /// One technician's public profile, for the detail screen.
  ///
  /// Returns the technician plus whether their phone number was released,
  /// which the UI uses to decide if the call button is live.
  Future<TechnicianProfile> byId(
    String technicianId, {
    double? latitude,
    double? longitude,
  }) async {
    final bool hasOrigin = latitude != null && longitude != null;

    final Map<String, dynamic> data = await _invoke(<String, dynamic>{
      'action': 'get',
      'technician_id': technicianId,
      if (hasOrigin) 'latitude': latitude,
      if (hasOrigin) 'longitude': longitude,
    });

    final Map<String, dynamic>? row =
        data['technician'] as Map<String, dynamic>?;

    if (row == null) {
      throw const RbCarsFailure('That technician is no longer listed.');
    }

    final List<Technician> merged = await _withAwayStatus(<Technician>[
      Technician.fromJson(row),
    ]);
    return TechnicianProfile(
      technician: merged.single,
      contactUnlocked: data['contact_unlocked'] as bool? ?? false,
    );
  }

  /// Marks the technicians who are on vacation today.
  ///
  /// One extra call per screen, to `technicians_away()`, rather than a new
  /// column on the listing functions: those rank and filter, were tuned and
  /// verified already, and should not be rewritten to carry a label. The
  /// call returns only the away ones and only their end date.
  ///
  /// Never fatal. If it fails, the list shows without vacation badges - and a
  /// booking attempt is still refused by `job-response`, which checks the
  /// database itself rather than trusting this label.
  Future<List<Technician>> _withAwayStatus(List<Technician> technicians) async {
    if (technicians.isEmpty) return technicians;

    // The function caps a request at 100 ids; no screen shows more.
    final List<String> ids = technicians
        .map((Technician t) => t.id)
        .where((String id) => id.isNotEmpty)
        .take(100)
        .toList(growable: false);

    try {
      final Object? data = await _client.rpc<Object?>(
        'technicians_away',
        params: <String, dynamic>{'p_ids': ids},
      );
      if (data is! List || data.isEmpty) return technicians;

      final Map<String, DateTime> away = <String, DateTime>{};
      for (final Map<String, dynamic> row in data.whereType<Map<String, dynamic>>()) {
        final String? id = row['technician_id'] as String?;
        final DateTime? until = DateTime.tryParse(row['away_until'] as String? ?? '');
        if (id != null && until != null) {
          away[id] = DateTime(until.year, until.month, until.day);
        }
      }

      return technicians
          .map((Technician t) => away.containsKey(t.id) ? t.copyWith(awayUntil: away[t.id]) : t)
          .toList(growable: false);
    } on Exception catch (error) {
      // Offline, a timeout, or the function refusing: all mean "no badges".
      debugPrint('technicians_away failed: $error');
      return technicians;
    }
  }

  /// Calls a SECURITY DEFINER listing function and expects a row set back.
  Future<List<dynamic>> _rpc(String name, Map<String, dynamic> params) async {
    final Object? data = await _rpcRaw(name, params);
    return data is List ? data : const <dynamic>[];
  }

  /// Shared RPC plumbing and error translation.
  ///
  /// The functions raise rather than return empty on the three cases the UI has
  /// to tell apart, and Postgres error codes are how that survives the wire:
  ///
  /// * `42501` - not signed in, or the job belongs to someone else. Both are
  ///   "you may not see this", and neither should be shown as a network error.
  /// * `P0002` - the job or technician does not exist.
  ///
  /// Anything else is a genuine fault and gets the generic message, because a
  /// raw Postgres string is not something to put in front of a client.
  Future<Object?> _rpcRaw(String name, Map<String, dynamic> params) async {
    try {
      return await _client.rpc<Object?>(name, params: params);
    } on PostgrestException catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('RPC $name failed [${error.code}]: ${error.message}');
        debugPrintStack(stackTrace: stackTrace, maxFrames: 6);
      }
      throw switch (error.code) {
        '42501' => const RbCarsFailure(
          'Please sign in again to continue.',
        ),
        'P0002' => const RbCarsFailure(
          'That technician is no longer listed.',
        ),
        _ => const RbCarsFailure('Could not load technicians right now.'),
      };
    } catch (error) {
      if (kDebugMode) debugPrint('RPC $name failed: $error');
      throw const RbCarsFailure(
        'Could not reach the technician directory. Check your connection.',
      );
    }
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final FunctionResponse response = await _client.functions.invoke(
        _function,
        body: body,
      );

      final Object? data = response.data;
      if (data is Map<String, dynamic>) {
        if (data['error'] != null) {
          throw RbCarsFailure(data['error'].toString());
        }
        return data;
      }
      return <String, dynamic>{};
    } on FunctionException catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('TechnicianDirectoryService failed: ${error.details}');
        debugPrintStack(stackTrace: stackTrace, maxFrames: 6);
      }
      if (error.status == 401) {
        throw const RbCarsFailure('Please sign in again to continue.');
      }
      throw const RbCarsFailure('Could not load technicians right now.');
    } on RbCarsFailure {
      rethrow;
    } catch (error) {
      throw const RbCarsFailure(
        'Could not reach the technician directory. Check your connection.',
      );
    }
  }
}

/// A technician plus whether the caller has earned their contact details.
class TechnicianProfile {
  const TechnicianProfile({
    required this.technician,
    required this.contactUnlocked,
  });

  final Technician technician;

  /// True when the caller has a confirmed, in-progress or completed job with
  /// this technician. Gates the call button on the detail screen.
  final bool contactUnlocked;
}
