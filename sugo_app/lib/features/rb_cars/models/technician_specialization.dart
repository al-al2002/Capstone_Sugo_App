import '../../onboarding/models/specialization_catalog.dart' as catalog;

/// One row of `technician_specializations`: a device type, a brand, and how
/// well proven the technician is on it.
///
/// ## Why this exists alongside `Technician.specialization`
///
/// `technicians.specialization` and `technicians.skill_tags` are coarse text
/// arrays - "laptop", "appliance" - and nothing guarantees which vocabulary
/// wrote them. `technician_specializations` is the table the registration flow
/// actually fills in, one row per device + brand, with `verified` set only by a
/// passed assessment.
///
/// That is the difference between a card that says "General repair technician"
/// and one that says "Laptop Repair", which is the whole point of showing it.
class TechnicianSpecialization {
  const TechnicianSpecialization({
    required this.deviceType,
    required this.brand,
    this.skillLevel,
    this.verified = false,
    this.category,
  });

  factory TechnicianSpecialization.fromJson(Map<String, dynamic> json) {
    return TechnicianSpecialization(
      deviceType: json['device_type'] as String? ?? '',
      brand: json['brand'] as String? ?? '',
      skillLevel: json['skill_level'] as String?,
      verified: json['verified'] as bool? ?? false,
      category: json['category'] as String?,
    );
  }

  /// Catalogue wire value, e.g. `laptop`, `aircon`, `washing_machine`.
  final String deviceType;

  /// Manufacturer, e.g. `Lenovo`. Never null in the table, but may be the
  /// picker's "Others" placeholder.
  final String brand;

  /// `beginner` | `intermediate` | `expert`, or null when the assessment for
  /// this track has not been passed. Null is meaningful: "declared but
  /// unproven" is a real state, not missing data.
  final String? skillLevel;

  /// True only when an assessment awarded it. A technician may declare any
  /// specialisation they like, so this is what separates a claim from a
  /// qualification.
  final bool verified;

  /// `it_device` | `appliance`.
  final String? category;

  /// Reads a `specializations` jsonb array as returned by the listing RPCs.
  static List<TechnicianSpecialization> listFrom(Object? value) {
    if (value is! List) return const <TechnicianSpecialization>[];
    return value
        .whereType<Map<String, dynamic>>()
        .map(TechnicianSpecialization.fromJson)
        .toList(growable: false);
  }

  /// `laptop` -> `Laptop`. Degrades to a title-cased wire value rather than
  /// throwing, because a row can outlive its catalogue entry.
  String get deviceLabel => catalog.SpecializationCatalog.deviceLabel(deviceType);

  /// What the card prints under the name, e.g. `Laptop Repair`.
  String get repairLabel => '$deviceLabel Repair';

  /// What a profile badge prints, e.g. `Laptop · Lenovo`.
  ///
  /// The brand is dropped when it is the picker's "Others" placeholder: that
  /// value means "I did not say", and printing it would read as a brand named
  /// Others.
  String get badgeLabel {
    final String trimmed = brand.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'others') return deviceLabel;
    return '$deviceLabel · $trimmed';
  }

  /// `Expert`, `Intermediate`, `Beginner`, or null when unproven.
  String? get skillLabel =>
      catalog.SkillLevel.fromWire(skillLevel)?.label;
}
