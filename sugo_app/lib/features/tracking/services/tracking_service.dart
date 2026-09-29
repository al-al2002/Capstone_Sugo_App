import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
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

  /// The road route of the trip happening now, from the traveller's last
  /// reported position to where that leg is going (`job-route`, live mode,
  /// 2026-09-29). For the person WATCHING a trip - the client following their
  /// technician, the technician waiting for a collecting client - so no
  /// origin is sent: the server reads it from `job_tracking`.
  ///
  /// Never throws; an unavailable route comes back with the server's reason.
  Future<RouteResult> liveRoute(String jobId) async {
    try {
      final FunctionResponse response = await _client.functions.invoke(
        'job-route',
        body: <String, dynamic>{'job_id': jobId, 'live': true},
      );
      final Object? data = response.data;
      if (data is! Map<String, dynamic>) {
        return const RouteResult.unavailable('provider_unavailable');
      }
      return RouteResult.fromJson(data);
    } catch (error) {
      _log('liveRoute', error);
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

  // ------------------------------------------- the client's collection trip
  //
  // The client travels on one leg: to the workshop, to collect the repaired
  // unit. These go through database functions rather than an update, because
  // the client cannot write `job_tracking` - see 20260929000001.

  /// "I'm on my way." Starts the trip and tells the technician.
  Future<void> startCollectionTrip(String jobId) async {
    try {
      await _client.rpc(
        'start_collection_trip',
        params: <String, dynamic>{'p_job_id': jobId},
      );
    } on PostgrestException catch (error) {
      _log('startCollectionTrip', error);
      // 23514 is a sentence written for the client ("once it is ready for
      // collection"), so it is shown as is.
      throw RbCarsFailure(
        error.code == '23514'
            ? error.message
            : 'Could not start sharing your trip.',
      );
    }
  }

  /// One position fix on the client's trip. Never throws, like
  /// [pushPosition]: a dropped fix is normal while moving.
  Future<void> shareCollectionPosition(String jobId, Position position) async {
    try {
      await _client.rpc(
        'share_collection_position',
        params: <String, dynamic>{
          'p_job_id': jobId,
          'p_latitude': position.latitude,
          'p_longitude': position.longitude,
          'p_accuracy_m': position.accuracy,
        },
      );
    } on PostgrestException catch (error) {
      _log('shareCollectionPosition', error);
    }
  }

  /// "I've arrived." Ends the trip; the server drops the client's position.
  Future<void> endCollectionTrip(String jobId) async {
    try {
      await _client.rpc(
        'end_collection_trip',
        params: <String, dynamic>{'p_job_id': jobId},
      );
    } on PostgrestException catch (error) {
      _log('endCollectionTrip', error);
      throw const RbCarsFailure('Could not mark that you have arrived.');
    }
  }

  /// The signed-in technician's workshop: where a collecting client is
  /// heading. Same order as `leg_destination.ts` on the server - the shop,
  /// then the registered base, then the last live position - so the pin on
  /// the map is the place the ETA counts down to. Null when none is recorded.
  Future<LatLng?> myWorkshop() async {
    try {
      final Map<String, dynamic>? row = await _client
          .from('technicians')
          .select(
            'shop_latitude, shop_longitude, base_latitude, base_longitude, '
            'latitude, longitude',
          )
          .eq('id', _uid)
          .maybeSingle();
      if (row == null) return null;
      double? at(String key) => (row[key] as num?)?.toDouble();
      final double? lat =
          at('shop_latitude') ?? at('base_latitude') ?? at('latitude');
      final double? lon =
          at('shop_longitude') ?? at('base_longitude') ?? at('longitude');
      return lat == null || lon == null ? null : LatLng(lat, lon);
    } catch (error) {
      _log('myWorkshop', error);
      return null;
    }
  }

  // ------------------------------------------------------- device location

  /// Gets the device ready to share a position, doing as much of it for the
  /// person as the platform allows.
  ///
  /// ## Why it switches location on rather than complaining (2026-09-29)
  ///
  /// This used to stop at the first obstacle with a sentence - "Location
  /// services are switched off" - and leave the person to find the setting,
  /// come back and tap again. Mid-trip, with the client waiting, a forgotten
  /// GPS toggle became "the map never showed him". Now:
  ///
  /// * **Permission** is requested on the spot, as before.
  /// * **Location switched off, on Android**: one position is requested, and
  ///   Google Play services answers with its own "Turn on location?" dialog
  ///   inside the app (geolocator's `startResolutionForResult`). One tap and
  ///   the trip carries on.
  /// * **Anything that cannot be fixed from here** - the dialog declined,
  ///   permission refused for good, iOS or the web, which cannot switch it
  ///   for you - comes back with [LocationReadiness.fix], so the screen can
  ///   offer a button straight to the right settings page.
  ///
  /// Permission is asked before the switch, because the switch dialog only
  /// appears for an app that is allowed to use location at all.
  Future<LocationReadiness> prepareLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      return const LocationReadiness.blocked(
        'Location permission was declined, so your position cannot be '
        'shared on this trip.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      return const LocationReadiness.blocked(
        'Location is blocked for SUGO. Allow it in the app settings to share '
        'your position.',
        fix: LocationFix.appSettings,
      );
    }

    if (await Geolocator.isLocationServiceEnabled()) {
      return const LocationReadiness.ready();
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        // The request is the point, not the fix: it is what makes Android
        // show "Turn on location?". The limit only stops a slow first fix,
        // after the person said yes, from holding the button forever.
        await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 20),
          ),
        );
        return const LocationReadiness.ready();
      } on LocationServiceDisabledException {
        // They said no to the dialog. Fall through to the settings button.
      } catch (error) {
        // A timeout after saying yes is still a yes.
        _log('prepareLocation', error);
        if (await Geolocator.isLocationServiceEnabled()) {
          return const LocationReadiness.ready();
        }
      }
    }

    return const LocationReadiness.blocked(
      'Location is switched off on this phone. Turn it on to share your '
      'position.',
      fix: LocationFix.locationSettings,
    );
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

/// Where the person has to go to fix what [TrackingService.prepareLocation]
/// could not.
enum LocationFix {
  /// Nothing to open: they declined the permission prompt and can simply
  /// tap again to see it again.
  none,

  /// The phone's location switch.
  locationSettings,

  /// SUGO's own permissions page, after "don't ask again".
  appSettings,
}

/// Whether the device can report a position, and why not if it cannot.
class LocationReadiness {
  const LocationReadiness.ready() : reason = null, fix = LocationFix.none;
  const LocationReadiness.blocked(this.reason, {this.fix = LocationFix.none});

  final String? reason;
  final LocationFix fix;

  bool get isReady => reason == null;

  /// Opens the settings page that [fix] names. False when there is none, or
  /// the platform would not open it.
  Future<bool> openFix() async {
    try {
      return switch (fix) {
        LocationFix.none => false,
        LocationFix.locationSettings => await Geolocator.openLocationSettings(),
        LocationFix.appSettings => await Geolocator.openAppSettings(),
      };
    } catch (_) {
      return false;
    }
  }
}
