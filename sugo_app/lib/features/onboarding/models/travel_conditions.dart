/// Will a technician still travel to a client in the rain, or in heavy
/// traffic? (2026-11-22, migration 20261122000001.)
///
/// Asked at registration, on the "What work do you take?" step, and editable
/// in Edit profile. Matching uses the answers while it is raining or the
/// traffic is heavy at the job: a technician who said they go ranks above one
/// who has not answered, who ranks above one who said they do not. Null means
/// "not answered" - every technician registered before the question existed -
/// and is scored exactly as before, from the weather and the trip.
library;

/// `technicians.rain_travel`.
enum RainTravel {
  any('any', 'Yes, even in heavy rain or a storm', 'Even in heavy rain'),
  notHeavy(
    'not_heavy',
    'Yes, but not in heavy rain or a storm',
    'In rain, not heavy rain',
  ),
  never('never', 'No, I do not travel in the rain', 'Not in the rain');

  const RainTravel(this.wire, this.label, this.shortLabel);

  /// The value stored in `technicians.rain_travel`.
  final String wire;

  /// The full answer, as the question offers it.
  final String label;

  /// A few words, for the registration recap.
  final String shortLabel;

  static RainTravel? fromWire(Object? value) {
    for (final RainTravel option in RainTravel.values) {
      if (option.wire == value) return option;
    }
    return null;
  }
}

/// `technicians.heavy_traffic_travel`, as a choice rather than a bare bool so
/// "not answered" (null) cannot be mistaken for "no".
enum TrafficTravel {
  goes(true, 'Yes, I still go in heavy traffic', 'Goes in heavy traffic'),
  avoids(false, 'No, I avoid heavy traffic', 'Avoids heavy traffic');

  const TrafficTravel(this.wire, this.label, this.shortLabel);

  /// The value stored in `technicians.heavy_traffic_travel`.
  final bool wire;

  final String label;
  final String shortLabel;

  static TrafficTravel? fromWire(Object? value) => switch (value) {
    true => TrafficTravel.goes,
    false => TrafficTravel.avoids,
    _ => null,
  };
}
