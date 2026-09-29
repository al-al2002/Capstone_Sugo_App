import 'package:flutter/material.dart';

/// Top-level split, mirroring the `technician_specializations.category` check.
enum ServiceCategory {
  itDevice('it_device', 'IT devices', Icons.laptop_mac_rounded),
  appliance('appliance', 'Appliances', Icons.kitchen_rounded);

  const ServiceCategory(this.wire, this.label, this.icon);

  final String wire;
  final String label;
  final IconData icon;

  static ServiceCategory? fromWire(String? value) {
    for (final ServiceCategory c in ServiceCategory.values) {
      if (c.wire == value) return c;
    }
    return null;
  }

  List<DeviceType> get deviceTypes => SpecializationCatalog.forCategory(this);
}

/// A body of repair knowledge that one assessment covers.
///
/// ## Why assessments are grouped, and not one per brand
///
/// A specialisation is a (device, brand) pair, so a technician who repairs
/// laptops and desktops for Apple, Dell and HP declares six of them. Testing
/// each separately would mean sitting the *same* quiz six times - the question
/// bank never differed by brand in the first place.
///
/// So competence is measured per track. Passing one verifies every
/// specialisation the technician declared inside it, whatever the brand. Worst
/// case falls from 10 devices x 7 brands = 70 assessments to 6.
///
/// Brand is deliberately not assessed. What is being measured is whether
/// someone can diagnose a compressor or a dead mainboard, and that does not
/// change between Samsung and LG. Brand still matters for *matching* - it is
/// what pairs a client's LG aircon with a technician who declared LG - but
/// testing it would be brand trivia, not skill.
///
/// Mirrors `public.assessment_track()` in migration 20260907000008. The
/// database is the authority; this copy exists so the UI can group the list
/// without a round trip.
enum AssessmentTrack {
  computerRepair(
    'computer_repair',
    'Computer repair',
    'Boards, storage, power supplies and operating systems.',
    Icons.laptop_chromebook_rounded,
    <String>['laptop', 'desktop'],
  ),
  mobileRepair(
    'mobile_repair',
    'Phone and tablet repair',
    'Screens, batteries, charging ports and water damage.',
    Icons.smartphone_rounded,
    <String>['smartphone', 'tablet'],
  ),
  printerRepair(
    'printer_repair',
    'Printer repair',
    'Paper paths, print heads, fusers and drivers.',
    Icons.print_rounded,
    <String>['printer'],
  ),
  refrigeration(
    'refrigeration',
    'Refrigeration',
    'Sealed systems, compressors and refrigerant. An aircon and a '
        'refrigerator are the same machine in a different box.',
    Icons.ac_unit_rounded,
    <String>['aircon', 'refrigerator'],
  ),
  laundryAppliance(
    'laundry_appliance',
    'Laundry appliances',
    'Motors, pumps, belts, water and drainage.',
    Icons.local_laundry_service_rounded,
    <String>['washing_machine'],
  ),
  homeElectronics(
    'home_electronics',
    'Home electronics',
    'Mains electronics with dangerous stored charge.',
    Icons.tv_rounded,
    <String>['television', 'microwave'],
  ),
  networkSurveillance(
    'network_surveillance',
    'Network and CCTV',
    'Routers, cabling, IP cameras and recorders. A camera system is a '
        'network before it is a camera, which is why one track covers both.',
    Icons.videocam_rounded,
    <String>['router', 'cctv'],
  );

  const AssessmentTrack(
    this.wire,
    this.label,
    this.blurb,
    this.icon,
    this.deviceTypes,
  );

  /// Selects the question bank in `assessment_questions.specialization` and is
  /// the value sent to `record_assessment_result`.
  final String wire;

  final String label;
  final String blurb;
  final IconData icon;

  /// The device types this track covers.
  final List<String> deviceTypes;

  static AssessmentTrack? fromWire(String? value) {
    for (final AssessmentTrack t in AssessmentTrack.values) {
      if (t.wire == value) return t;
    }
    return null;
  }

  /// The track a device belongs to.
  ///
  /// Returns null for a device the catalogue does not place, matching the SQL
  /// function's fallback of giving it a track of its own. That surfaces as
  /// "no questions available" rather than quietly verifying someone against
  /// somebody else's bank.
  static AssessmentTrack? forDevice(String deviceType) {
    for (final AssessmentTrack t in AssessmentTrack.values) {
      if (t.deviceTypes.contains(deviceType)) return t;
    }
    return null;
  }
}

/// One device a technician can declare, with the brands offered for it.
class DeviceType {
  const DeviceType({
    required this.wire,
    required this.label,
    required this.icon,
    required this.category,
    required this.brands,
  });

  /// Stored in `technician_specializations.device_type`.
  final String wire;

  final String label;
  final IconData icon;
  final ServiceCategory category;

  /// The brands offered for this device. Not exhaustive by design - the picker
  /// always appends an "Others" entry that takes free text, because the column
  /// is plain `text` with no foreign key precisely so an unlisted brand is
  /// still expressible.
  final List<String> brands;

  /// Which assessment covers this device. Several devices share one.
  AssessmentTrack? get track => AssessmentTrack.forDevice(wire);
}

/// The category -> device -> brand tree behind the specialisation step.
///
/// Kept in Dart rather than in a database table on purpose. These are the
/// *options a user is offered*, not data the app owns: the brand column is
/// free text, so nothing here constrains what can be stored. Putting the list
/// in a table would add a network round trip and a migration to every wording
/// change, and would imply a referential integrity the schema deliberately
/// does not have.
///
/// The trade-off, stated plainly: adding a brand means shipping an app update.
/// That is acceptable while the list is curated. If brands ever need to change
/// without a release, this is the thing to move server-side.
class SpecializationCatalog {
  const SpecializationCatalog._();

  /// Shown at the end of every brand list.
  static const String othersBrand = 'Others';

  static const List<String> _computerBrands = <String>[
    'Apple',
    'Dell',
    'HP',
    'Lenovo',
    'Asus',
    'Acer',
    'MSI',
  ];

  static const List<String> _phoneBrands = <String>[
    'Apple',
    'Samsung',
    'Xiaomi',
    'Oppo',
    'Vivo',
    'Realme',
    'Huawei',
  ];

  static const List<String> _applianceBrands = <String>[
    'LG',
    'Samsung',
    'Panasonic',
    'Sharp',
    'Whirlpool',
    'Condura',
    'Carrier',
  ];

  /// Router brands, including the units the local ISPs actually hand out -
  /// most Philippine households never bought their own.
  static const List<String> _routerBrands = <String>[
    'PLDT',
    'Globe',
    'Converge',
    'TP-Link',
    'D-Link',
    'Tenda',
    'Cisco',
    'Ubiquiti',
    'Mikrotik',
    'Huawei',
  ];

  static const List<String> _cctvBrands = <String>[
    'Hikvision',
    'Dahua',
    'Uniview',
    'Ezviz',
    'TP-Link',
    'Imou',
  ];

  static const List<DeviceType> devices = <DeviceType>[
    // --------------------------------------------------------- IT devices
    DeviceType(
      wire: 'laptop',
      label: 'Laptop',
      icon: Icons.laptop_chromebook_rounded,
      category: ServiceCategory.itDevice,
      brands: _computerBrands,
    ),
    DeviceType(
      wire: 'desktop',
      label: 'Desktop PC',
      icon: Icons.desktop_windows_rounded,
      category: ServiceCategory.itDevice,
      brands: _computerBrands,
    ),
    DeviceType(
      wire: 'router',
      label: 'Router / Wi-Fi',
      icon: Icons.router_rounded,
      category: ServiceCategory.itDevice,
      brands: _routerBrands,
    ),
    DeviceType(
      wire: 'cctv',
      label: 'CCTV / IP camera',
      icon: Icons.videocam_rounded,
      category: ServiceCategory.itDevice,
      brands: _cctvBrands,
    ),
    DeviceType(
      wire: 'smartphone',
      label: 'Smartphone',
      icon: Icons.smartphone_rounded,
      category: ServiceCategory.itDevice,
      brands: _phoneBrands,
    ),
    DeviceType(
      wire: 'tablet',
      label: 'Tablet',
      icon: Icons.tablet_mac_rounded,
      category: ServiceCategory.itDevice,
      brands: _phoneBrands,
    ),
    DeviceType(
      wire: 'printer',
      label: 'Printer',
      icon: Icons.print_rounded,
      category: ServiceCategory.itDevice,
      brands: <String>['Epson', 'Canon', 'HP', 'Brother'],
    ),

    // --------------------------------------------------------- Appliances
    DeviceType(
      wire: 'aircon',
      label: 'Aircon',
      icon: Icons.ac_unit_rounded,
      category: ServiceCategory.appliance,
      brands: _applianceBrands,
    ),
    DeviceType(
      wire: 'refrigerator',
      label: 'Refrigerator',
      icon: Icons.kitchen_rounded,
      category: ServiceCategory.appliance,
      brands: _applianceBrands,
    ),
    DeviceType(
      wire: 'washing_machine',
      label: 'Washing machine',
      icon: Icons.local_laundry_service_rounded,
      category: ServiceCategory.appliance,
      brands: _applianceBrands,
    ),
    DeviceType(
      wire: 'television',
      label: 'Television',
      icon: Icons.tv_rounded,
      category: ServiceCategory.appliance,
      brands: <String>['LG', 'Samsung', 'Sony', 'TCL', 'Devant'],
    ),
    DeviceType(
      wire: 'microwave',
      label: 'Microwave',
      icon: Icons.microwave_rounded,
      category: ServiceCategory.appliance,
      brands: _applianceBrands,
    ),
  ];

  static List<DeviceType> forCategory(ServiceCategory category) {
    return devices
        .where((DeviceType d) => d.category == category)
        .toList(growable: false);
  }

  static DeviceType? deviceByWire(String? wire) {
    for (final DeviceType d in devices) {
      if (d.wire == wire) return d;
    }
    return null;
  }

  /// Human label for a stored device wire value, falling back to the raw value.
  ///
  /// A row can outlive its catalogue entry - a device removed in a later
  /// release still has technicians qualified on it - so this must degrade to
  /// something readable rather than throwing or showing an empty cell.
  static String deviceLabel(String wire) =>
      deviceByWire(wire)?.label ?? _titleCase(wire);

  static IconData deviceIcon(String wire) =>
      deviceByWire(wire)?.icon ?? Icons.build_rounded;

  static String _titleCase(String wire) {
    return wire
        .split('_')
        .where((String part) => part.isNotEmpty)
        .map((String p) => p[0].toUpperCase() + p.substring(1))
        .join(' ');
  }
}

/// A declared device + brand pair, before or after it reaches the database.
///
/// The same type serves the picker's local selection and the persisted row.
/// [id] being null is what distinguishes "chosen but not saved" from "saved",
/// which the review screen and the assessment list both need to tell apart.
class TechnicianSpecialization {
  const TechnicianSpecialization({
    required this.category,
    required this.deviceType,
    required this.brand,
    this.id,
    this.skillLevel,
    this.verified = false,
    this.lastAttemptAt,
    this.lastScore,
    this.attemptCount = 0,
  });

  factory TechnicianSpecialization.fromJson(Map<String, dynamic> json) {
    return TechnicianSpecialization(
      id: json['id'] as String?,
      category:
          ServiceCategory.fromWire(json['category'] as String?) ??
          ServiceCategory.itDevice,
      deviceType: json['device_type'] as String? ?? '',
      brand: json['brand'] as String? ?? '',
      skillLevel: SkillLevel.fromWire(json['skill_level'] as String?),
      verified: json['verified'] as bool? ?? false,
    );
  }

  final String? id;
  final ServiceCategory category;
  final String deviceType;
  final String brand;

  /// Null until the assessment for this pair has been passed.
  final SkillLevel? skillLevel;

  final bool verified;

  /// Populated from `technician_assessment_results` when the assessment list
  /// is loaded, so the UI can show a cooldown without a second query per row.
  final DateTime? lastAttemptAt;
  final double? lastScore;
  final int attemptCount;

  bool get isSaved => id != null;

  String get deviceLabel => SpecializationCatalog.deviceLabel(deviceType);

  /// The assessment that qualifies this row. Shared with every other brand of
  /// the same device, and with the other devices in the track - which is why
  /// one sitting can verify several specialisations at once.
  AssessmentTrack? get track => AssessmentTrack.forDevice(deviceType);

  /// "Aircon - LG". The identity a technician recognises their own row by.
  String get displayLabel => '$deviceLabel — $brand';

  /// Stable identity for a pair that has no database id yet, matching the
  /// `uniq_technician_specialization` index (technician, device, brand).
  String get localKey => '$deviceType::$brand';

  Map<String, dynamic> toInsertJson(String technicianId) {
    return <String, dynamic>{
      'technician_id': technicianId,
      'category': category.wire,
      'device_type': deviceType,
      'brand': brand,
      // `verified` and `skill_level` are deliberately omitted. The insert
      // policy in migration 20260907000003 requires them at their defaults, so
      // sending them at all can only fail.
    };
  }

  TechnicianSpecialization copyWith({
    String? id,
    SkillLevel? skillLevel,
    bool? verified,
    DateTime? lastAttemptAt,
    double? lastScore,
    int? attemptCount,
  }) {
    return TechnicianSpecialization(
      id: id ?? this.id,
      category: category,
      deviceType: deviceType,
      brand: brand,
      skillLevel: skillLevel ?? this.skillLevel,
      verified: verified ?? this.verified,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastScore: lastScore ?? this.lastScore,
      attemptCount: attemptCount ?? this.attemptCount,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TechnicianSpecialization &&
      other.deviceType == deviceType &&
      other.brand == brand;

  @override
  int get hashCode => Object.hash(deviceType, brand);
}

/// Mirrors `technician_specializations.skill_level`.
///
/// The bands are defined once in SQL, by `assessment_skill_level(numeric)`.
/// The thresholds are repeated here only to render a preview before a score is
/// submitted; the server's answer always wins.
enum SkillLevel {
  beginner('beginner', 'Beginner'),
  intermediate('intermediate', 'Intermediate'),
  expert('expert', 'Expert');

  const SkillLevel(this.wire, this.label);

  final String wire;
  final String label;

  static SkillLevel? fromWire(String? value) {
    for (final SkillLevel s in SkillLevel.values) {
      if (s.wire == value) return s;
    }
    return null;
  }

  /// Mirror of `public.assessment_skill_level`. Returns null below the pass
  /// mark, which is what "failed, no level awarded" means.
  static SkillLevel? fromScore(double score) {
    if (score >= 90) return SkillLevel.expert;
    if (score >= 70) return SkillLevel.intermediate;
    return null;
  }

  /// The pass mark, as a percentage. Stricter than the older account-wide
  /// quiz's 60 because a per-brand claim is a narrower promise to a client.
  static const double passMark = 70;
}
