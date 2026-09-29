import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../rb_cars/models/json_utils.dart';

/// A road route to a job's destination, from the `job-route` edge function.
class RouteResult {
  const RouteResult({
    required this.available,
    this.reason,
    this.points = const <LatLng>[],
    this.distanceMeters,
    this.travelSeconds,
    this.trafficDelaySeconds = 0,
    this.destination,
    this.destinationLabel,
  });

  /// A route that could not be produced, with the server's reason code.
  const RouteResult.unavailable(String this.reason)
    : available = false,
      points = const <LatLng>[],
      distanceMeters = null,
      travelSeconds = null,
      trafficDelaySeconds = 0,
      destination = null,
      destinationLabel = null;

  factory RouteResult.fromJson(Map<String, dynamic> json) {
    if (json['available'] != true) {
      return RouteResult.unavailable(json['reason'] as String? ?? 'unknown');
    }

    final List<LatLng> points = <LatLng>[
      for (final Object? pair in json['points'] as List<dynamic>? ?? const [])
        if (pair is List && pair.length >= 2)
          LatLng(asDouble(pair[0]), asDouble(pair[1])),
    ];

    final Map<String, dynamic>? dest =
        json['destination'] as Map<String, dynamic>?;

    return RouteResult(
      available: points.length >= 2,
      reason: points.length >= 2 ? null : 'no_route',
      points: points,
      distanceMeters: asNullableDouble(json['distance_m']),
      travelSeconds: asNullableDouble(json['travel_s']),
      trafficDelaySeconds: asDouble(json['traffic_delay_s']),
      destination: dest == null
          ? null
          : LatLng(asDouble(dest['latitude']), asDouble(dest['longitude'])),
      destinationLabel: dest?['label'] as String?,
    );
  }

  final bool available;

  /// `no_destination`, `too_far`, `no_route`, `not_configured`,
  /// `provider_unavailable`, or `no_location` from the device side.
  final String? reason;

  final List<LatLng> points;
  final double? distanceMeters;
  final double? travelSeconds;
  final double trafficDelaySeconds;
  final LatLng? destination;
  final String? destinationLabel;

  /// e.g. `3.4 km`, `850 m`.
  String? get distanceLabel {
    final double? m = distanceMeters;
    if (m == null) return null;
    if (m < 1000) return '${(m / 10).round() * 10} m';
    return '${(m / 1000).toStringAsFixed(1)} km';
  }

  /// e.g. `12 min`, `1 h 5 min`. Includes traffic: TomTom's travel time is
  /// already traffic-aware.
  String? get etaLabel {
    final double? s = travelSeconds;
    if (s == null) return null;
    final int minutes = math.max(1, (s / 60).round());
    if (minutes < 60) return '$minutes min';
    return '${minutes ~/ 60} h ${minutes % 60} min';
  }

  /// Only worth mentioning once it is a real slowdown. A 20-second delay
  /// printed as "+0 min traffic" is noise that makes the road look worse than
  /// it is.
  bool get hasMeaningfulTrafficDelay => trafficDelaySeconds >= 60;

  String get trafficDelayLabel =>
      '+${(trafficDelaySeconds / 60).round()} min traffic';

  /// A human sentence for [reason], for when there is no route to draw.
  String get unavailableMessage => switch (reason) {
    'no_location' =>
      'Turn on location so we can route you from where you are.',
    'no_destination' =>
      'This destination has no location on record yet. Message the other '
          'person for the address.',
    'too_far' =>
      'You seem to be very far from the destination. Check that your '
          'location is correct.',
    'no_route' => 'No road route could be found to this destination.',
    'not_configured' => 'In-app routing is not set up on this server yet.',
    _ => 'Could not load the route right now. Try again in a moment.',
  };
}

/// Geometry for deciding when a route has to be recalculated.
///
/// Kept separate from the screen and free of Flutter so it can be tested
/// directly: whether someone is "off route" decides when the app spends a
/// TomTom call, so it is worth pinning with numbers rather than eyeballing on a
/// map.
class RouteGeometry {
  const RouteGeometry._();

  static const double _earthRadiusM = 6371000;

  /// Shortest distance in metres from [point] to the polyline [line].
  ///
  /// Uses an equirectangular projection centred on [point]. Over the few
  /// hundred metres that matter for an off-route check its error is well under
  /// a metre, and it avoids great-circle maths on every GPS fix. Returns
  /// infinity for an empty line, so "no route" is always treated as off route.
  static double distanceToPolylineMeters(LatLng point, List<LatLng> line) {
    if (line.isEmpty) return double.infinity;

    final double cosLat = math.cos(point.latitude * math.pi / 180);

    // Project to local metres, with [point] at the origin.
    math.Point<double> project(LatLng p) => math.Point<double>(
      (p.longitude - point.longitude) * math.pi / 180 * _earthRadiusM * cosLat,
      (p.latitude - point.latitude) * math.pi / 180 * _earthRadiusM,
    );

    if (line.length == 1) {
      final math.Point<double> only = project(line.first);
      return math.sqrt(only.x * only.x + only.y * only.y);
    }

    double best = double.infinity;
    math.Point<double> a = project(line.first);

    for (int i = 1; i < line.length; i++) {
      final math.Point<double> b = project(line[i]);
      final double dx = b.x - a.x;
      final double dy = b.y - a.y;
      final double lengthSq = dx * dx + dy * dy;

      // Parameter of the closest point on segment ab to the origin, clamped
      // so it stays on the segment rather than its infinite extension.
      double t = lengthSq == 0 ? 0 : -(a.x * dx + a.y * dy) / lengthSq;
      t = t.clamp(0.0, 1.0);

      final double cx = a.x + t * dx;
      final double cy = a.y + t * dy;
      final double d = math.sqrt(cx * cx + cy * cy);
      if (d < best) best = d;

      a = b;
    }

    return best;
  }
}
