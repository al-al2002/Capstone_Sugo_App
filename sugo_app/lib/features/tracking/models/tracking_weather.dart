import '../../rb_cars/models/json_utils.dart';

/// Conditions at the destination of the current tracking leg.
///
/// Comes from the `job-weather` edge function, which holds the OpenWeatherMap
/// key server-side and resolves which coordinate matters from the leg. The app
/// never calls the provider directly and never learns the key.
class TrackingWeather {
  const TrackingWeather({
    required this.available,
    this.condition,
    this.description,
    this.tempC,
    this.severity,
    this.label,
    this.destinationLabel,
    this.outbound = false,
  });

  factory TrackingWeather.fromJson(Map<String, dynamic> json) {
    return TrackingWeather(
      available: json['available'] as bool? ?? false,
      condition: json['condition'] as String?,
      description: json['description'] as String?,
      tempC: asNullableDouble(json['temp_c']),
      severity: asNullableDouble(json['severity']),
      label: json['label'] as String?,
      destinationLabel: json['destination_label'] as String?,
      outbound: json['outbound'] as bool? ?? false,
    );
  }

  /// False when the key is unset, the provider failed, the job has no transport
  /// leg, or no destination coordinate is known. All four are the same thing to
  /// the UI: draw nothing.
  final bool available;

  /// e.g. `Rain`, `Clouds`.
  final String? condition;

  /// e.g. `light rain`.
  final String? description;

  final double? tempC;

  /// 0..1, the same severity Stage 2 uses to discount acceptance likelihood.
  /// 0 is clear.
  final double? severity;

  final String? label;

  /// e.g. `the drop-off`, `the workshop`.
  final String? destinationLabel;

  /// True while the unit is travelling back to the client.
  final bool outbound;

  /// Sentence for the chip, e.g. `Light rain at the drop-off`.
  ///
  /// Capitalises the provider's lowercase description rather than shipping a
  /// separate display string, so a condition the catalogue does not know about
  /// still reads properly.
  String get sentence {
    final String text = (description ?? label ?? 'Current conditions').trim();
    final String head = text.isEmpty
        ? 'Current conditions'
        : text[0].toUpperCase() + text.substring(1);
    final String where = destinationLabel ?? 'the destination';
    return '$head at $where';
  }

  /// Rounded temperature, e.g. `29°C`. Null when the provider omitted it.
  String? get temperatureLabel {
    final double? temp = tempC;
    return temp == null ? null : '${temp.round()}°C';
  }

  /// Conditions bad enough that a client should expect the leg to run slow.
  ///
  /// 0.4 is chosen to sit in the gap in the matcher's own severity table
  /// (`WEATHER_SEVERITY` in scoring/constants.ts) between drizzle at 0.35 and
  /// rain at 0.55. So the chip turns amber for rain, heavy rain, snow and
  /// thunderstorms, and stays neutral for drizzle, mist, haze and cloud.
  ///
  /// It is a display threshold only - Stage 2 uses the continuous severity and
  /// has no cut-off of its own, so this number decides a colour and nothing
  /// about how anyone is ranked.
  static const double adverseThreshold = 0.4;

  bool get isAdverse => (severity ?? 0) >= adverseThreshold;
}
