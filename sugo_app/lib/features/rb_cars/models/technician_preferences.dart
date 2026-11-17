import 'package:flutter/foundation.dart';

import '../../../core/utils/formatters.dart';
import 'device_category.dart';
import 'json_utils.dart';
import 'trust_badge.dart';

export 'trust_badge.dart' show TrustBadge;

/// The client's minimum requirements for their technician (2026-11-15).
///
/// Every field is a **hard gate** chosen from fixed options: a technician who
/// fails one is removed before RB-CARS ranks anyone, not ranked lower. Every
/// field is also optional - null is "No preference" and filters nobody, so a
/// job that sets nothing is matched exactly as before this feature existed.
///
/// What is deliberately *not* here: weights or percentages. How much distance
/// matters against rating stays the engine's decision, re-weighted by the
/// job's context. The client says what they will not accept; the engine
/// decides who is best among the rest.
///
/// Stored as six `pref_*` columns on `jobs` (migration 20261115000001), each
/// with a CHECK constraint, and read by `match-technician/scoring/
/// preferences.ts`. The wire values here and there are one contract.
@immutable
class TechnicianPreferences {
  const TechnicianPreferences({
    this.specialization,
    this.maxDistance,
    this.minRating,
    this.availability,
    this.availableOn,
    this.minTrust,
  });

  /// Nothing set. The default for every new job.
  static const TechnicianPreferences none = TechnicianPreferences();

  /// Reads the `pref_*` columns of a `jobs` row. A value outside the fixed
  /// options reads as "No preference" - the same rule the engine applies.
  factory TechnicianPreferences.fromJson(Map<String, dynamic> json) {
    final AvailabilityPreference? availability =
        AvailabilityPreference.fromWire(json['pref_availability'] as String?);
    final DateTime? availableOn = asDate(json['pref_available_on']);

    return TechnicianPreferences(
      specialization: PreferredSpecialization.fromWire(
        json['pref_specialization'] as String?,
      ),
      maxDistance: MaxDistance.fromKm(
        asNullableDouble(json['pref_max_distance_km']),
      ),
      minRating: MinRating.fromValue(asNullableDouble(json['pref_min_rating'])),
      // A date preference without its date cannot be checked; it is dropped
      // rather than kept half-set.
      availability:
          availability == AvailabilityPreference.onDate && availableOn == null
          ? null
          : availability,
      availableOn: availability == AvailabilityPreference.onDate
          ? availableOn
          : null,
      minTrust: TrustBadge.fromWire(json['pref_min_trust'] as String?),
    );
  }

  final PreferredSpecialization? specialization;
  final MaxDistance? maxDistance;
  final MinRating? minRating;
  final AvailabilityPreference? availability;

  /// The day for [AvailabilityPreference.onDate]; null otherwise.
  final DateTime? availableOn;

  /// The minimum Progressive Trust Badge rung, for THIS job: the engine
  /// counts a technician as skill verified only for a device this job needs.
  final TrustBadge? minTrust;

  /// The preferences that are set, in the order the step shows them.
  List<PreferenceField> get active => <PreferenceField>[
    if (specialization != null) PreferenceField.specialization,
    if (maxDistance != null) PreferenceField.maxDistance,
    if (minRating != null) PreferenceField.minRating,
    if (availability != null) PreferenceField.availability,
    if (minTrust != null) PreferenceField.minTrust,
  ];

  bool get hasAny => active.isNotEmpty;

  /// "Pick a date" with no date yet. The step will not continue past it.
  bool get isMissingDate =>
      availability == AvailabilityPreference.onDate && availableOn == null;

  /// The six columns, always all six. Unset ones are written as null, so an
  /// edit that clears a preference really clears it on the job.
  Map<String, dynamic> toColumns() {
    final bool onDate =
        availability == AvailabilityPreference.onDate && availableOn != null;
    return <String, dynamic>{
      'pref_specialization': specialization?.wire,
      'pref_max_distance_km': maxDistance?.km,
      'pref_min_rating': minRating?.value,
      // Never write `on_date` without its date: the CHECK constraint requires
      // both or neither.
      'pref_availability': availability == AvailabilityPreference.now
          ? AvailabilityPreference.now.wire
          : onDate
          ? AvailabilityPreference.onDate.wire
          : null,
      'pref_available_on': onDate ? _isoDate(availableOn!) : null,
      'pref_min_trust': minTrust?.wire,
    };
  }

  /// A copy with some fields replaced. Each argument is a getter so a field
  /// can be set back to null ("No preference"), which a plain nullable
  /// parameter cannot express.
  TechnicianPreferences copyWith({
    ValueGetter<PreferredSpecialization?>? specialization,
    ValueGetter<MaxDistance?>? maxDistance,
    ValueGetter<MinRating?>? minRating,
    ValueGetter<AvailabilityPreference?>? availability,
    ValueGetter<DateTime?>? availableOn,
    ValueGetter<TrustBadge?>? minTrust,
  }) {
    final AvailabilityPreference? nextAvailability = availability != null
        ? availability()
        : this.availability;
    return TechnicianPreferences(
      specialization: specialization != null
          ? specialization()
          : this.specialization,
      maxDistance: maxDistance != null ? maxDistance() : this.maxDistance,
      minRating: minRating != null ? minRating() : this.minRating,
      availability: nextAvailability,
      // A date only survives alongside "Pick a date".
      availableOn: nextAvailability == AvailabilityPreference.onDate
          ? (availableOn != null ? availableOn() : this.availableOn)
          : null,
      minTrust: minTrust != null ? minTrust() : this.minTrust,
    );
  }

  /// This set with one preference back to "No preference" - what a chip's
  /// close button does on the "try relaxing them" screen.
  TechnicianPreferences without(PreferenceField field) {
    return switch (field) {
      PreferenceField.specialization => copyWith(specialization: () => null),
      PreferenceField.maxDistance => copyWith(maxDistance: () => null),
      PreferenceField.minRating => copyWith(minRating: () => null),
      PreferenceField.availability => copyWith(availability: () => null),
      PreferenceField.minTrust => copyWith(minTrust: () => null),
    };
  }

  /// One preference as the client chose it, e.g. "Within 5 km".
  String labelFor(PreferenceField field) {
    return switch (field) {
      PreferenceField.specialization =>
        specialization?.label ?? 'Any specialization',
      PreferenceField.maxDistance => maxDistance?.label ?? 'Any distance',
      PreferenceField.minRating =>
        minRating == null ? 'Any rating' : '${minRating!.label} rating',
      PreferenceField.availability => switch (availability) {
        AvailabilityPreference.now => 'Available now',
        AvailabilityPreference.onDate =>
          availableOn == null
              ? 'Pick a date'
              : 'Free ${Fmt.dayDate(availableOn!)}',
        null => 'Any time',
      },
      PreferenceField.minTrust => minTrust?.label ?? 'Any trust badge',
    };
  }

  /// Every set preference on one line, for the review step and the job card.
  String get summary {
    if (!hasAny) return 'No preference';
    return active.map(labelFor).join(' · ');
  }

  static String _isoDate(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is TechnicianPreferences &&
      other.specialization == specialization &&
      other.maxDistance == maxDistance &&
      other.minRating == minRating &&
      other.availability == availability &&
      other.availableOn == availableOn &&
      other.minTrust == minTrust;

  @override
  int get hashCode => Object.hash(
    specialization,
    maxDistance,
    minRating,
    availability,
    availableOn,
    minTrust,
  );
}

/// One preference. [wire] matches the engine's `PreferenceKey`, which is how
/// the "remove this and N would qualify" hints find their chip.
enum PreferenceField {
  specialization('specialization'),
  maxDistance('max_distance_km'),
  minRating('min_rating'),
  availability('availability'),
  minTrust('min_trust');

  const PreferenceField(this.wire);

  final String wire;

  static PreferenceField? fromWire(String? value) {
    for (final PreferenceField f in PreferenceField.values) {
      if (f.wire == value) return f;
    }
    return null;
  }
}

/// Must offer this specialisation. The engine maps each onto the
/// `technician_specializations.device_type` values in its comment.
enum PreferredSpecialization {
  computer('computer', 'Computer/Laptop', 'Laptops and desktop PCs'),
  pcBuilding('pc_building', 'PC Building', 'Desktop PCs only'),
  phoneTablet('phone_tablet', 'Phone/Tablet', 'Smartphones and tablets'),
  networkSetup(
    'network_setup',
    'Network & Device Setup',
    'Routers, CCTV and printers',
  ),
  appliance(
    'appliance',
    'Appliance Service',
    'Aircon, fridge, washer, TV, microwave',
  );

  const PreferredSpecialization(this.wire, this.label, this.blurb);

  final String wire;
  final String label;
  final String blurb;

  /// The `technician_specializations.device_type` values this covers. The
  /// same table as `specialization_devices()` in SQL and
  /// `SPECIALIZATION_DEVICES` in the engine.
  List<String> get deviceTypes => switch (this) {
    computer => const <String>['laptop', 'desktop'],
    pcBuilding => const <String>['desktop'],
    phoneTablet => const <String>['smartphone', 'tablet'],
    networkSetup => const <String>['router', 'cctv', 'printer'],
    appliance => const <String>[
      'aircon',
      'refrigerator',
      'washing_machine',
      'television',
      'microwave',
    ],
  };

  /// Every specialisation a verified device row proves - a desktop proves
  /// both Computer/Laptop and PC Building.
  static List<PreferredSpecialization> provenBy(Iterable<String> devices) {
    final Set<String> set = devices.toSet();
    return PreferredSpecialization.values
        .where((PreferredSpecialization s) => s.deviceTypes.any(set.contains))
        .toList(growable: false);
  }

  static PreferredSpecialization? fromWire(String? value) {
    for (final PreferredSpecialization s in PreferredSpecialization.values) {
      if (s.wire == value) return s;
    }
    return null;
  }

  /// The options that make sense for the device picked on step 1.
  ///
  /// Offering "Appliance Service" on a laptop job could only ever produce an
  /// empty list, so the choice is never shown. With no device yet, all five.
  static List<PreferredSpecialization> forCategory(DeviceCategory? category) {
    return switch (category) {
      DeviceCategory.laptop => const <PreferredSpecialization>[
        computer,
        pcBuilding,
      ],
      DeviceCategory.phone => const <PreferredSpecialization>[phoneTablet],
      DeviceCategory.appliance => const <PreferredSpecialization>[appliance],
      DeviceCategory.network ||
      DeviceCategory.cctv => const <PreferredSpecialization>[networkSetup],
      null => PreferredSpecialization.values,
    };
  }
}

/// Straight-line distance from the technician's base to the job pin.
enum MaxDistance {
  km3(3),
  km5(5),
  km10(10);

  const MaxDistance(this.km);

  final int km;

  String get label => 'Within $km km';

  static MaxDistance? fromKm(double? value) {
    for (final MaxDistance d in MaxDistance.values) {
      if (d.km == value) return d;
    }
    return null;
  }
}

/// Minimum `technicians.rating`.
enum MinRating {
  r30(3.0),
  r40(4.0),
  r45(4.5);

  const MinRating(this.value);

  final double value;

  String get label => '${value.toStringAsFixed(1)}+';

  static MinRating? fromValue(double? value) {
    for (final MinRating r in MinRating.values) {
      if (r.value == value) return r;
    }
    return null;
  }
}

/// When the technician must be free. "No preference" is null.
enum AvailabilityPreference {
  /// Not on time off today and not on another unfinished job.
  now('now', 'Available now'),

  /// Not on time off on [TechnicianPreferences.availableOn].
  onDate('on_date', 'Pick a date');

  const AvailabilityPreference(this.wire, this.label);

  final String wire;
  final String label;

  static AvailabilityPreference? fromWire(String? value) {
    for (final AvailabilityPreference a in AvailabilityPreference.values) {
      if (a.wire == value) return a;
    }
    return null;
  }
}

/// What each trust rung means when a CLIENT asks for it as a minimum.
///
/// Worded for this job rather than the account: skill verification counts
/// only for a device this job needs. The ladder itself is [TrustBadge], the
/// same one the profile shows and RB-CARS scores (2026-11-15). Choosing a
/// rung keeps that rung and every rung above it.
String trustPreferenceBlurb(TrustBadge badge) => switch (badge) {
  TrustBadge.idVerified =>
    'Identity checked by SUGO. Every technician with a badge has this.',
  TrustBadge.skillVerified =>
    'Proven on your type of device: a passed assessment or an approved '
        'certificate.',
  TrustBadge.communityTrusted =>
    'Proven on your device, plus 50+ jobs, a 4.5+ rating and a clean record.',
};

/// "Remove this one preference and [wouldMatch] technicians would qualify",
/// from the engine's `relax_hints`.
@immutable
class RelaxHint {
  const RelaxHint({required this.field, required this.wouldMatch});

  final PreferenceField field;
  final int wouldMatch;

  /// Reads `preference_filter.relax_hints`. Unknown keys are skipped, so a
  /// newer engine with a sixth preference does not break an older app.
  static List<RelaxHint> listFrom(Object? value) {
    if (value is! List) return const <RelaxHint>[];
    final List<RelaxHint> hints = <RelaxHint>[];
    for (final Object? item in value) {
      if (item is! Map<String, dynamic>) continue;
      final PreferenceField? field = PreferenceField.fromWire(
        item['preference'] as String?,
      );
      if (field == null) continue;
      hints.add(
        RelaxHint(field: field, wouldMatch: asInt(item['would_match'])),
      );
    }
    return List<RelaxHint>.unmodifiable(hints);
  }
}
