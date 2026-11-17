import 'job_tracking.dart';
import 'tracking_weather.dart';

/// Who is looking at the trip card. The facts are the same; the wording is
/// not ("Your technician arrives" / "You arrive").
enum TripViewer { client, technician }

/// Traffic on the way, in the five steps the matcher already names.
///
/// The bands are `describe()` in `match-technician/clients/tomtom.ts`, so a
/// level here is always the same words the server used. Moderate and heavy
/// are the levels the server will blame a delay on (congestion 0.35 and up).
enum TrafficLevel {
  clear('Clear', 'roads are clear'),
  light('Light', 'traffic is light'),
  moderate('Moderate', 'traffic is moderate'),
  heavy('Heavy', 'traffic is heavy'),
  closed('Road closure', 'there is a road closure nearby');

  const TrafficLevel(this.headline, this.phrase);

  /// One word for the tile, e.g. "Light".
  final String headline;

  /// For the sentence, e.g. "traffic is light".
  final String phrase;

  /// 0..1 how slow the little cars on the card drive (1 = standstill).
  double get slowness => switch (this) {
    clear => 0.05,
    light => 0.25,
    moderate => 0.5,
    heavy => 0.82,
    closed => 1.0,
  };

  bool get isBad => this == heavy || this == closed;

  /// From the server's label first (it is the server's own decision), then
  /// from the number, with the same cut-offs as `describe()`.
  static TrafficLevel? from({String? label, double? congestion}) {
    switch (label?.toLowerCase()) {
      case 'clear roads':
        return clear;
      case 'light traffic':
        return light;
      case 'moderate traffic':
        return moderate;
      case 'heavy traffic':
        return heavy;
      case 'road closure nearby':
        return closed;
    }
    final double? c = congestion;
    if (c == null) return null;
    if (c < 0.15) return clear;
    if (c < 0.35) return light;
    if (c < 0.6) return moderate;
    return heavy;
  }
}

/// Weather on the way, in three bands of the matcher's 0..1 severity
/// (`WEATHER_SEVERITY` in `scoring/constants.ts`).
///
/// * good - clear (0.0), clouds (0.1), unknown (0.2)
/// * fair - mist/haze (0.3), drizzle (0.35)
/// * bad  - [TrackingWeather.adverseThreshold] (0.4) and up: rain, heavy
///   rain, snow, storms. The same line the server uses to blame a delay on
///   the weather, so "Bad" here and "delayed by bad weather" agree.
enum WeatherLevel {
  good('Good'),
  fair('Fair'),
  bad('Bad');

  const WeatherLevel(this.headline);

  final String headline;

  static const double fairFrom = 0.3;

  static WeatherLevel? fromSeverity(double? severity) {
    if (severity == null) return null;
    if (severity >= TrackingWeather.adverseThreshold) return bad;
    if (severity >= fairFrom) return fair;
    return good;
  }
}

/// What the trip card says, worked out from one `job_tracking` row.
///
/// Pure: everything comes from the row and [now], so it is unit-tested
/// without a widget.
class TripConditions {
  TripConditions.of(this.tracking, {DateTime? now})
    : now = now ?? DateTime.now();

  final JobTracking tracking;
  final DateTime now;

  TrafficLevel? get traffic => TrafficLevel.from(
    label: tracking.trafficLabel,
    congestion: tracking.trafficCongestion,
  );

  WeatherLevel? get weather =>
      WeatherLevel.fromSeverity(tracking.weatherSeverity);

  /// The server has sampled this leg at least once.
  bool get sampled => tracking.etaSampledAt != null;

  /// Minutes until the current estimated arrival; null before the first
  /// sample. Never negative.
  int? get minutesLeft {
    final DateTime? eta = tracking.projectedArrivalAt;
    if (eta == null) return null;
    final int seconds = eta.difference(now).inSeconds;
    return seconds <= 0 ? 0 : (seconds / 60).ceil();
  }

  /// "20 min", "1 h 5 min", "Now"; null before the first sample.
  String? get etaLabel {
    final int? minutes = minutesLeft;
    if (minutes == null) return null;
    if (minutes <= 0) return 'Now';
    if (minutes < 60) return '$minutes min';
    final int rest = minutes % 60;
    return rest == 0 ? '${minutes ~/ 60} h' : '${minutes ~/ 60} h $rest min';
  }

  /// "Clear weather", "Light rain" - the provider's words, capitalised.
  String? get weatherDetail => _capitalised(tracking.weatherLabel);

  /// "Light traffic", "Road closure nearby".
  String? get trafficDetail => _capitalised(tracking.trafficLabel);

  /// The one-line summary the user asked for, e.g. "Weather is good and
  /// traffic is light." Says only what was measured.
  String? get summary {
    final WeatherLevel? w = weather;
    final TrafficLevel? t = traffic;
    final String? weatherPart = switch (w) {
      WeatherLevel.good => 'Weather is good',
      WeatherLevel.fair || WeatherLevel.bad => weatherDetail,
      null => null,
    };
    if (weatherPart == null && t == null) return null;
    if (weatherPart == null) return '${_capitalised(t!.phrase)}.';
    if (t == null) return '$weatherPart.';
    return '$weatherPart and ${t.phrase}.';
  }

  /// Good weather, flowing traffic, not late.
  bool get looksClear =>
      !tracking.isDelayed &&
      weather != WeatherLevel.bad &&
      !(traffic?.isBad ?? false);

  /// "Updated just now" / "Updated 3 min ago", from the last sample.
  String? get freshness {
    final DateTime? at = tracking.etaSampledAt;
    if (at == null) return null;
    final int minutes = now.difference(at).inMinutes;
    if (minutes < 1) return 'Updated just now';
    if (minutes < 60) return 'Updated $minutes min ago';
    return 'Updated ${minutes ~/ 60} h ago';
  }

  /// The client, not the technician, is the one travelling: dropping the
  /// unit off or collecting it (2026-11-17). Every sentence below flips on
  /// this - the traveller reads "you", the person waiting reads "they".
  bool get clientTravels => tracking.stage.isClientTrip;

  /// Whether [viewer] is the one on the road.
  bool isTravelling(TripViewer viewer) => clientTravels
      ? viewer == TripViewer.client
      : viewer == TripViewer.technician;

  /// Where this leg ends, for [viewer]: "to your home", "to the workshop".
  String destinationFor(TripViewer viewer) {
    if (clientTravels) {
      return viewer == TripViewer.client ? 'to the shop' : 'to your shop';
    }
    if (!tracking.stage.headsToClient) return 'to the workshop';
    return viewer == TripViewer.client ? 'to your home' : 'to the client';
  }

  /// The headline over the countdown.
  String arrivalTitle(TripViewer viewer) {
    if (clientTravels) {
      return viewer == TripViewer.client
          ? 'You arrive in'
          : 'Your client arrives in';
    }
    return viewer == TripViewer.client
        ? (tracking.stage.headsToClient
              ? 'Your technician arrives in'
              : 'At the workshop in')
        : 'You arrive in';
  }

  static String? _capitalised(String? text) {
    final String? t = text?.trim();
    if (t == null || t.isEmpty) return null;
    return t[0].toUpperCase() + t.substring(1);
  }
}
