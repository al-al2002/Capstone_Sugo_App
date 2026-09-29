import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/app_env.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../models/client_onboarding_models.dart';

/// Address search and reverse geocoding via Nominatim, plus device location.
///
/// ## Why Nominatim and not MapTiler's geocoder
///
/// MapTiler already supplies the tiles, and it sells geocoding too - but that
/// call is billed per request and the key ships inside the app, so a typing
/// user would burn quota on every keystroke against a key anyone can extract.
/// Nominatim is free and its terms are satisfiable by a mobile app.
///
/// ## The rules Nominatim imposes, and how this class meets them
///
/// The public instance has a usage policy, and ignoring it gets an application
/// blocked by IP rather than throttled. Three requirements matter here:
///
///   1. **At most one request per second.** Enforced by [_minRequestGap] plus
///      the debounce in the search field, so a fast typist cannot outrun it.
///   2. **A genuine User-Agent identifying the application.** Sent on every
///      request as [_userAgent]. A default Dart agent is explicitly refused.
///   3. **No heavy or automated bulk use.** This is interactive search only.
///
/// TODO(production): move these calls behind a Supabase edge function with a
/// server-side cache. The policy limit is per-IP, so on a mobile network many
/// SUGO users share one carrier NAT address and can collectively exceed it
/// while each behaves perfectly. Self-hosting Nominatim removes the limit
/// entirely and is the real answer at scale.
class GeocodingService {
  GeocodingService({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final http.Client _http;

  static const String _host = 'nominatim.openstreetmap.org';

  /// Identifies the app, as the usage policy requires. The contact address
  /// matters: it is how OSM reaches a maintainer before blocking an app that
  /// starts misbehaving.
  static const String _userAgent =
      'SUGO/1.0 (capstone project; contact: support@sugo.app)';

  /// One request per second, per the policy. Tracked across the whole service
  /// rather than per call site so search and reverse geocoding share the
  /// budget.
  static const Duration _minRequestGap = Duration(milliseconds: 1100);

  /// Nominatim can be slow under load. Ten seconds is generous enough to
  /// tolerate that without leaving the user watching a spinner indefinitely.
  static const Duration _timeout = Duration(seconds: 10);

  /// Bias results towards the Philippines.
  ///
  /// SUGO operates in Davao City. Without this, searching "San Pedro" returns
  /// results in Paraguay and California before the street two blocks away.
  static const String _countryCodes = 'ph';

  static DateTime? _lastRequestAt;

  /// Blocks until the next request is allowed.
  Future<void> _respectRateLimit() async {
    final DateTime? last = _lastRequestAt;
    if (last != null) {
      final Duration since = DateTime.now().difference(last);
      if (since < _minRequestGap) {
        await Future<void>.delayed(_minRequestGap - since);
      }
    }
    _lastRequestAt = DateTime.now();
  }

  // ----------------------------------------------------------- forward search

  /// Searches for an address.
  ///
  /// Returns an empty list rather than throwing when nothing matches, because
  /// "no results" is an ordinary outcome of typing, not an error. Genuine
  /// failures - no network, a blocked key - do throw, since those need
  /// different words in front of the user.
  Future<List<GeoPlace>> search(String query, {int limit = 6}) async {
    final String trimmed = query.trim();

    // Below three characters every query matches half the country, which
    // wastes a request against a rate limit measured in single digits.
    if (trimmed.length < 3) return const <GeoPlace>[];

    await _respectRateLimit();

    final Uri uri = Uri.https(_host, '/search', <String, String>{
      'q': trimmed,
      'format': 'jsonv2',
      'addressdetails': '1',
      'limit': '$limit',
      'countrycodes': _countryCodes,
    });

    try {
      final http.Response response = await _http
          .get(uri, headers: <String, String>{'User-Agent': _userAgent})
          .timeout(_timeout);

      if (response.statusCode == 429 || response.statusCode == 403) {
        // The policy limit, hit. Named explicitly because the generic
        // "search failed" would send debugging towards the network layer.
        throw const RbCarsFailure(
          'Address search is busy right now. Wait a moment, or drop the pin '
          'on the map instead.',
        );
      }
      if (response.statusCode != 200) {
        throw const RbCarsFailure('Address search is unavailable right now.');
      }

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! List) return const <GeoPlace>[];

      return decoded
          .whereType<Map<String, dynamic>>()
          .map(GeoPlace.fromNominatim)
          .where((GeoPlace p) => p.hasCoordinates)
          .toList(growable: false);
    } on RbCarsFailure {
      rethrow;
    } on TimeoutException {
      throw const RbCarsFailure(
        'Address search timed out. You can still drop the pin on the map.',
      );
    } catch (error) {
      _log('search', error);
      throw const RbCarsFailure(
        'Could not search for that address. Check your connection.',
      );
    }
  }

  // ----------------------------------------------------------- reverse lookup

  /// Turns a pin into a readable address.
  ///
  /// Returns null rather than throwing on any failure. Reverse geocoding is a
  /// convenience - it fills the address box after a tap - and the coordinates
  /// are already captured, so a failure must never block the step. The map step
  /// falls back to showing the coordinate pair.
  Future<GeoPlace?> reverse(double latitude, double longitude) async {
    await _respectRateLimit();

    final Uri uri = Uri.https(_host, '/reverse', <String, String>{
      'lat': '$latitude',
      'lon': '$longitude',
      'format': 'jsonv2',
      'addressdetails': '1',
      // 18 is building level. The default is coarser and would label a pinned
      // house with the name of its barangay.
      'zoom': '18',
    });

    try {
      final http.Response response = await _http
          .get(uri, headers: <String, String>{'User-Agent': _userAgent})
          .timeout(_timeout);

      if (response.statusCode != 200) return null;

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['error'] != null) return null;

      final GeoPlace place = GeoPlace.fromNominatim(decoded);

      // Nominatim echoes the query coordinates back for an unmapped location.
      // Keep the caller's exact pin rather than the rounded echo.
      return GeoPlace(
        latitude: latitude,
        longitude: longitude,
        addressText: place.addressText,
        shortLabel: place.shortLabel,
      );
    } catch (error) {
      _log('reverse', error);
      return null;
    }
  }

  // --------------------------------------------------------- device location

  /// The device's current position, for the "Use current location" button.
  ///
  /// Every failure mode is turned into a sentence that says what the user can
  /// do about it. "Location unavailable" next to a button that just did
  /// nothing is the least useful message an app can show.
  Future<GeoPlace> currentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const RbCarsFailure(
          'Location services are switched off. Turn them on, or drop the pin '
          'on the map instead.',
        );
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        // Distinct from a plain denial: this one cannot be re-prompted, so
        // sending the user back to the button would loop them forever.
        throw const RbCarsFailure(
          'Location access is blocked for SUGO. Enable it in your device '
          'settings, or drop the pin on the map instead.',
        );
      }
      if (permission == LocationPermission.denied) {
        throw const RbCarsFailure(
          'Location access was declined. Drop the pin on the map instead.',
        );
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          // A GPS fix indoors can take a long time. Fifteen seconds, then fall
          // back to asking the user to place the pin themselves.
          timeLimit: Duration(seconds: 15),
        ),
      );

      // Reverse geocoding is best-effort; the coordinates alone are enough to
      // move the pin, which is what the button promised.
      final GeoPlace? resolved = await reverse(
        position.latitude,
        position.longitude,
      );

      return resolved ??
          GeoPlace(
            latitude: position.latitude,
            longitude: position.longitude,
            addressText: '',
          );
    } on RbCarsFailure {
      rethrow;
    } on TimeoutException {
      throw const RbCarsFailure(
        'Could not get a location fix. Move somewhere with a clearer view of '
        'the sky, or drop the pin on the map.',
      );
    } catch (error) {
      _log('currentLocation', error);
      throw const RbCarsFailure(
        'Could not read your location. Drop the pin on the map instead.',
      );
    }
  }

  /// Where the map opens before anything is chosen - Davao City centre,
  /// shared with the RB-CARS job picker via [AppEnv].
  static GeoPlace get fallbackPlace => const GeoPlace(
    latitude: AppEnv.defaultLatitude,
    longitude: AppEnv.defaultLongitude,
    addressText: '',
  );

  void dispose() => _http.close();

  void _log(String action, Object error) {
    if (kDebugMode) {
      debugPrint('GeocodingService.$action failed: $error');
    }
  }
}
