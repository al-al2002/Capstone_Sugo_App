import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../models/job_tracking.dart';
import '../models/route_result.dart';
import '../models/tracking_weather.dart';

/// Reads and writes live job tracking.
///
/// ## Two directions, two mechanisms
///
/// The **technician** pushes: `geolocator` reports a new position and the row
/// is updated. The **client** subscribes: Supabase Realtime delivers each
/// change straight to the map.
///
/// Realtime rather than polling because a delivery can run half an hour, and
/// polling every few seconds would drain both batteries to learn nothing most
/// of the time. Realtime still enforces RLS per subscriber, so a client only
/// ever receives rows for their own jobs - the subscription is not a way around
/// the policies.
///
/// A polling fallback exists for the case where the realtime publication is not
/// enabled on a project, because a tracking screen that silently never updates
/// is worse than one that updates slowly.
class TrackingService {
  TrackingService({SupabaseClient? client})
    : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  static const String _table = 'job_tracking';

  /// How often the fallback poller re-reads when realtime is unavailable.
  static const Duration pollInterval = Duration(seconds: 15);

  /// Minimum movement before a new position is pushed. Below this the fix is
  /// mostly GPS jitter, and writing it would burn quota to move a dot by a
  /// metre.
  static const int _minimumDistanceMetres = 15;

  String get _uid {
    final String? id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const RbCarsFailure('Please sign in again to continue.');
    }
    return id;
  }

  // ------------------------------------------------------------------- read

  /// Current tracking state for a job, or null when it has no transport leg.
  Future<JobTracking?> fetch(String jobId) async {
    try {
      final Map<String, dynamic>? row = await _client
          .from(_table)
          .select()
          .eq('job_id', jobId)
          .maybeSingle();

      return row == null ? null : JobTracking.fromJson(row);
    } on PostgrestException catch (error) {
      _log('fetch', error);
      throw const RbCarsFailure('Could not load tracking for this job.');
    }
  }

  /// Asks the server to resample the ETA for this leg and decide whether it is
  /// running late.
  ///
  /// Called by the TECHNICIAN's app, never the client's. Detection has to work
  /// while the client is not looking - that is the whole point - and the
  /// travelling phone is the one that is definitely awake. The client reads the
  /// result off the same realtime row the map already subscribes to.
  ///
  /// Throttled here to [etaSampleInterval], and again on the server, because a
  /// client-side throttle is a request and a server-side one is a rule.
  ///
  /// Returns true when a sample was actually taken. Never throws: this runs on
  /// a moving vehicle beside `pushPosition`, and a failed ETA must not be
  /// louder than a failed position.
  Future<bool> sampleEta(String jobId) async {
    try {
      final FunctionResponse response = await _client.functions.invoke(
        'tracking-eta',
        body: <String, dynamic>{'job_id': jobId},
      );
      final Object? data = response.data;
      if (data is! Map<String, dynamic>) return false;
      return data['sampled'] as bool? ?? false;
    } catch (error) {
      _log('sampleEta', error);
      return false;
    }
  }

  /// How often the technician's app asks for a fresh ETA.
  ///
  /// Two minutes, against the server's 90-second floor so an on-time call is
  /// never wasted. A 30-minute delivery is ~15 TomTom calls; sampling per GPS
  /// fix instead would be thousands.
  static const Duration etaSampleInterval = Duration(minutes: 2);

  /// A road route from [originLatitude],[originLongitude] to this job's
  /// destination, for drawing inside the app.
  ///
  /// Only the ORIGIN is sent. The destination is resolved by the `job-route`
  /// function from the job itself, so the app cannot be used to route anywhere
  /// a booking does not entitle the caller to go.
  ///
  /// Never throws: a route that cannot be produced comes back as
  /// [RouteResult.unavailable] with a reason the screen can explain.
  Future<RouteResult> routeFor(
    String jobId, {
    required double originLatitude,
    required double originLongitude,
  }) async {
    try {
      final FunctionResponse response = await _client.functions.invoke(
        'job-route',
        body: <String, dynamic>{
          'job_id': jobId,
          'origin_latitude': originLatitude,
          'origin_longitude': originLongitude,
        },
      );
      final Object? data = response.data;
      if (data is! Map<String, dynamic>) {
        return const RouteResult.unavailable('provider_unavailable');
      }
      return RouteResult.fromJson(data);
    } catch (error) {
      _log('routeFor', error);
      return const RouteResult.unavailable('provider_unavailable');
    }
  }

  /// One position fix now, for the start of a route. Null when location is off
  /// or no fix arrives in time.
  Future<Position?> currentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (error) {
      _log('currentPosition', error);
      return null;
    }
  }

  /// Conditions at the destination of the current leg.
  ///
  /// Goes through the `job-weather` edge function rather than calling
  /// OpenWeatherMap directly: the API key is a Supabase secret, and calling the
  /// provider from Flutter would ship that key inside the APK.
  ///
  /// NEVER call this from the tracking stream. That stream emits on every GPS
  /// fix - a few seconds apart for the length of a delivery - and one forecast
  /// request per fix would exhaust the free tier in a day. Callers fetch once
  /// per leg; `WeatherChip` refetches only when the leg flips.
  ///
  /// Returns null instead of throwing. The chip is supplementary to a screen
  /// whose job is showing a moving van, so a failed forecast disappears rather
  /// than becoming an error the client has to dismiss.
  Future<TrackingWeather?> weatherFor(String jobId) async {
    try {
      final FunctionResponse response = await _client.functions.invoke(
        'job-weather',
        body: <String, dynamic>{'job_id': jobId},
      );

      final Object? data = response.data;
      if (data is! Map<String, dynamic>) return null;

      final TrackingWeather weather = TrackingWeather.fromJson(data);
      return weather.available ? weather : null;
    } catch (error) {
      _log('weatherFor', error);
      return null;
    }
  }

  /// Live stream of tracking updates for one job.
  ///
  /// Emits immediately with whatever is already stored, then again on every
  /// change, so the map has something to draw before the first update arrives.
  Stream<JobTracking?> watch(String jobId) {
    final StreamController<JobTracking?> controller =
        StreamController<JobTracking?>.broadcast();

    RealtimeChannel? channel;
    Timer? poller;

    Future<void> emitCurrent() async {
      try {
        final JobTracking? current = await fetch(jobId);
        if (!controller.isClosed) controller.add(current);
      } catch (error) {
        if (!controller.isClosed) controller.addError(error);
      }
    }

    controller.onListen = () {
      unawaited(emitCurrent());

      channel = _client
          .channel('job_tracking:$jobId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: _table,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'job_id',
              value: jobId,
            ),
            callback: (PostgresChangePayload payload) {
              final Map<String, dynamic> record = payload.newRecord;
              if (record.isEmpty) return;
              if (!controller.isClosed) {
                controller.add(JobTracking.fromJson(record));
              }
            },
          )
          .subscribe();

      // Belt and braces: if the publication is missing, realtime never fires
      // and this keeps the screen truthful.
      poller = Timer.periodic(pollInterval, (_) => emitCurrent());
    };

    controller.onCancel = () async {
      poller?.cancel();
      final RealtimeChannel? open = channel;
      if (open != null) await _client.removeChannel(open);
    };

    return controller.stream;
  }

  // ------------------------------------------------------------------ write

  /// Makes sure the tracking row for a job exists, and returns it as it
  /// stands. Safe to call twice - the row is unique per job.
  ///
  /// **Resuming, not restarting.** An existing row is returned untouched. This
  /// was previously an `upsert` with `onConflict: 'job_id'`, which is
  /// `insert ... on conflict do update` - so every re-entry to the delivery
  /// screen rewrote `stage` back to `heading_to_pickup`. A technician who had
  /// already collected the unit and was driving to the shop would reopen the
  /// screen and be told to mark it collected again, and because the client
  /// watches this same row over realtime, their timeline jumped backwards too.
  ///
  /// [stage] is the caller asserting a stage rather than asking for one. Only
  /// pass it when something really has moved the job - a fresh reroute, say.
  /// Omitting it means "resume", and resuming must never rewrite what is
  /// already there.
  Future<JobTracking> start(String jobId, {TrackingStage? stage}) async {
    try {
      final JobTracking? existing = await fetch(jobId);

      if (existing != null) {
        return stage == null ? existing : await setStage(jobId, stage);
      }

      final Map<String, dynamic> row = await _client
          .from(_table)
          .insert(<String, dynamic>{
            'job_id': jobId,
            'technician_id': _uid,
            'stage': (stage ?? TrackingStage.headingToPickup).wire,
          })
          .select()
          .single();

      return JobTracking.fromJson(row);
    } on PostgrestException catch (error) {
      // 23505 is the `unique (job_id)` constraint: something created the row
      // between the read above and this insert. The row now exists, which is
      // all the caller ever wanted, so read it back rather than failing.
      if (error.code == '23505') {
        final JobTracking? raced = await fetch(jobId);
        if (raced != null) return raced;
      }

      _log('start', error);
      throw const RbCarsFailure('Could not start tracking for this job.');
    }
  }

  /// Moves the job to a new stage.
  Future<JobTracking> setStage(String jobId, TrackingStage stage) async {
    try {
      final Map<String, dynamic> row = await _client
          .from(_table)
          .update(<String, dynamic>{'stage': stage.wire})
          .eq('job_id', jobId)
          .select()
          .single();

      return JobTracking.fromJson(row);
    } on PostgrestException catch (error) {
      _log('setStage', error);
      // 23514 is a rule the database enforces with a sentence written for
      // the technician - "The client is picking this up at your shop..." -
      // so it is shown as is rather than replaced with a generic failure.
      throw RbCarsFailure(
        error.code == '23514'
            ? error.message
            : 'Could not update the delivery stage.',
      );
    }
  }

  // --------------------------------------------------------- return method

  /// How the client wants [jobId] back. [ReturnMethod.delivery] when they
  /// have not said, which is the default. Never throws: an unknown choice
  /// reads as the default, and the server still enforces the real one.
  Future<ReturnMethod> returnMethod(String jobId) async =>
      await returnChoice(jobId) ?? ReturnMethod.delivery;

  /// The client's recorded choice, or null when there is none yet.
  ///
  /// [returnMethod] flattens null to delivery, because that is what the
  /// server does and what the trip will be. This keeps the difference, so a
  /// technician's screen can say "they have not chosen yet — delivery is the
  /// default" rather than attributing a decision to somebody who has not made
  /// one.
  Future<ReturnMethod?> returnChoice(String jobId) async {
    try {
      final Map<String, dynamic>? row = await _client
          .from('job_return_preferences')
          .select('method')
          .eq('job_id', jobId)
          .maybeSingle();

      final String? wire = row?['method'] as String?;
      return wire == null ? null : ReturnMethod.fromWire(wire);
    } catch (error) {
      _log('returnChoice', error);
      return null;
    }
  }

  /// The same for several jobs at once, keyed by job id - for a list of cards.
  /// Jobs with no choice are simply absent.
  Future<Map<String, ReturnMethod>> returnMethods(List<String> jobIds) async {
    if (jobIds.isEmpty) return const <String, ReturnMethod>{};
    try {
      final List<dynamic> rows = await _client
          .from('job_return_preferences')
          .select('job_id, method')
          .inFilter('job_id', jobIds);
      return <String, ReturnMethod>{
        for (final Map<String, dynamic> row
            in rows.whereType<Map<String, dynamic>>())
          row['job_id'] as String: ReturnMethod.fromWire(row['method'] as String?),
      };
    } catch (error) {
      _log('returnMethods', error);
      return const <String, ReturnMethod>{};
    }
  }

  /// The client choosing delivery, or collecting it themselves.
  ///
  /// Through `set_return_method()`, which holds the rules: only the client,
  /// only a pickup job a technician has, and not once the unit is already on
  /// its way back. Its refusals are sentences, and are shown as such.
  Future<ReturnMethod> setReturnMethod(String jobId, ReturnMethod method) async {
    try {
      await _client.rpc<Object?>(
        'set_return_method',
        params: <String, dynamic>{'p_job_id': jobId, 'p_method': method.wire},
      );
      return method;
    } on PostgrestException catch (error) {
      _log('setReturnMethod', error);
      throw RbCarsFailure(
        error.code == '23514' || error.code == '42501'
            ? error.message
            : 'Could not save your choice. Please try again.',
      );
    }
  }

  /// Pushes one position fix.
  Future<void> pushPosition(String jobId, Position position) async {
    try {
      await _client
          .from(_table)
          .update(<String, dynamic>{
            'latitude': position.latitude,
            'longitude': position.longitude,
            'accuracy_m': position.accuracy,
            'heading': position.heading,
          })
          .eq('job_id', jobId);
    } on PostgrestException catch (error) {
      // Never surfaced to the technician: a dropped fix is normal on a moving
      // vehicle and the next one is seconds away. Failing loudly here would
      // make driving feel broken.
      _log('pushPosition', error);
    }
  }

  // ------------------------------------------------------- device location

  /// Asks for location permission, explaining the outcome rather than
  /// returning a bare bool.
  Future<LocationReadiness> prepareLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationReadiness.blocked(
        'Location services are switched off on this device. Turn them on to '
        'share your position with the client.',
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      return const LocationReadiness.blocked(
        'Location permission was declined. The client will not be able to see '
        'where their appliance is.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      return const LocationReadiness.blocked(
        'Location permission is permanently denied. Enable it for SUGO in '
        'your device settings.',
      );
    }

    return const LocationReadiness.ready();
  }

  /// Continuous position updates while a leg is in progress.
  ///
  /// Filtered by distance rather than time: a stationary van in traffic should
  /// not generate a write every second.
  Stream<Position> positionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _minimumDistanceMetres,
      ),
    );
  }

  void _log(String action, Object error) {
    if (kDebugMode) debugPrint('TrackingService.$action failed: $error');
  }
}

/// Whether the device can report a position, and why not if it cannot.
class LocationReadiness {
  const LocationReadiness.ready() : reason = null;
  const LocationReadiness.blocked(this.reason);

  final String? reason;

  bool get isReady => reason == null;
}
