import 'issue_catalog.dart';
import 'job_enums.dart';

/// One selectable symptom in the guided classification step.
///
/// The catalog is the rule base behind RB-CARS' first decision: given a device
/// type, a symptom and a yes/no on physical damage, which service path should
/// we suggest? Keeping it as data (rather than a pile of `if`s in the widget)
/// means the defence panel can read the whole rule set on one screen.
class ProblemSymptom {
  const ProblemSymptom({
    required this.code,
    required this.label,
    required this.deviceType,
    required this.pathWhenIntact,
    required this.pathWhenDamaged,
    this.isAmbiguous = false,
    this.hint,
  });

  /// Stored in `jobs.problem_symptom`.
  final String code;

  final String label;
  final DeviceType deviceType;

  /// Suggested path when the client answers "no physical damage".
  final ServicePath pathWhenIntact;

  /// Suggested path when the client answers "yes, there is damage".
  final ServicePath pathWhenDamaged;

  /// True when the symptom alone cannot separate a software fault from a
  /// hardware fault. Ambiguous symptoms go to the IT community first and are
  /// written with `classification_confidence = 'low'`.
  final bool isAmbiguous;

  final String? hint;
}

/// The full rule base, grouped by device type.
class ProblemCatalog {
  const ProblemCatalog._();

  /// Sentinel the UI offers as the last option in every list.
  static const String notSureCode = 'not_sure';

  static const List<ProblemSymptom> all = <ProblemSymptom>[
    // ---------------------------------------------------------------- laptop
    ProblemSymptom(
      code: 'laptop_wont_power_on',
      label: 'Will not power on',
      deviceType: DeviceType.laptop,
      pathWhenIntact: ServicePath.homeService,
      pathWhenDamaged: ServicePath.pickup,
      isAmbiguous: true,
      hint: 'Could be the charger, the battery or the board.',
    ),
    ProblemSymptom(
      code: 'laptop_slow_or_freezing',
      label: 'Very slow or freezing',
      deviceType: DeviceType.laptop,
      pathWhenIntact: ServicePath.homeService,
      pathWhenDamaged: ServicePath.pickup,
      hint: 'Usually software, cleanable on site.',
    ),
    ProblemSymptom(
      code: 'laptop_overheating',
      label: 'Overheating or loud fan',
      deviceType: DeviceType.laptop,
      pathWhenIntact: ServicePath.homeService,
      pathWhenDamaged: ServicePath.pickup,
      hint: 'Cleaning and thermal paste can be done at your place.',
    ),
    ProblemSymptom(
      code: 'laptop_screen_broken',
      label: 'Cracked or blank screen',
      deviceType: DeviceType.laptop,
      pathWhenIntact: ServicePath.pickup,
      pathWhenDamaged: ServicePath.pickup,
      hint: 'Panel swaps need shop tools and a matching part.',
    ),
    ProblemSymptom(
      code: 'laptop_liquid_damage',
      label: 'Liquid spill',
      deviceType: DeviceType.laptop,
      pathWhenIntact: ServicePath.pickup,
      pathWhenDamaged: ServicePath.pickup,
      hint: 'Board-level cleaning, shop only.',
    ),
    ProblemSymptom(
      code: 'laptop_no_os',
      label: 'Windows will not boot',
      deviceType: DeviceType.laptop,
      pathWhenIntact: ServicePath.homeService,
      pathWhenDamaged: ServicePath.pickup,
    ),

    // ----------------------------------------------------------------- phone
    ProblemSymptom(
      code: 'phone_screen_cracked',
      label: 'Cracked screen',
      deviceType: DeviceType.phone,
      pathWhenIntact: ServicePath.pickup,
      pathWhenDamaged: ServicePath.pickup,
    ),
    ProblemSymptom(
      code: 'phone_battery_drain',
      label: 'Battery drains fast',
      deviceType: DeviceType.phone,
      pathWhenIntact: ServicePath.homeService,
      pathWhenDamaged: ServicePath.pickup,
    ),
    ProblemSymptom(
      code: 'phone_charging_port',
      label: 'Will not charge',
      deviceType: DeviceType.phone,
      pathWhenIntact: ServicePath.pickup,
      pathWhenDamaged: ServicePath.pickup,
      isAmbiguous: true,
      hint: 'Could be the cable, the port or the battery.',
    ),
    ProblemSymptom(
      code: 'phone_water_damage',
      label: 'Water damage',
      deviceType: DeviceType.phone,
      pathWhenIntact: ServicePath.pickup,
      pathWhenDamaged: ServicePath.pickup,
    ),
    ProblemSymptom(
      code: 'phone_software_stuck',
      label: 'Stuck on logo or bootloop',
      deviceType: DeviceType.phone,
      pathWhenIntact: ServicePath.homeService,
      pathWhenDamaged: ServicePath.pickup,
      isAmbiguous: true,
    ),

    // ------------------------------------------------------------- appliance
    ProblemSymptom(
      code: 'appliance_not_cooling',
      label: 'Aircon or ref not cooling',
      deviceType: DeviceType.appliance,
      pathWhenIntact: ServicePath.homeService,
      pathWhenDamaged: ServicePath.homeService,
      hint: 'Large units are always serviced where they stand.',
    ),
    ProblemSymptom(
      code: 'appliance_no_power',
      label: 'No power at all',
      deviceType: DeviceType.appliance,
      pathWhenIntact: ServicePath.homeService,
      pathWhenDamaged: ServicePath.homeService,
      isAmbiguous: true,
    ),
    ProblemSymptom(
      code: 'appliance_water_leak',
      label: 'Leaking water',
      deviceType: DeviceType.appliance,
      pathWhenIntact: ServicePath.homeService,
      pathWhenDamaged: ServicePath.homeService,
    ),
    ProblemSymptom(
      code: 'appliance_strange_noise',
      label: 'Strange noise or vibration',
      deviceType: DeviceType.appliance,
      pathWhenIntact: ServicePath.homeService,
      pathWhenDamaged: ServicePath.pickup,
      isAmbiguous: true,
    ),
    ProblemSymptom(
      code: 'appliance_small_unit_dead',
      label: 'Small appliance stopped working',
      deviceType: DeviceType.appliance,
      pathWhenIntact: ServicePath.pickup,
      pathWhenDamaged: ServicePath.pickup,
      hint: 'Blenders, fans and microwaves travel well.',
    ),

    // --------------------------------------------------------------- network
    ProblemSymptom(
      code: 'network_no_internet',
      label: 'No internet connection',
      deviceType: DeviceType.network,
      pathWhenIntact: ServicePath.homeService,
      pathWhenDamaged: ServicePath.homeService,
    ),
    ProblemSymptom(
      code: 'network_weak_signal',
      label: 'Weak Wi-Fi in some rooms',
      deviceType: DeviceType.network,
      pathWhenIntact: ServicePath.homeService,
      pathWhenDamaged: ServicePath.homeService,
      hint: 'Coverage problems can only be measured on site.',
    ),
    ProblemSymptom(
      code: 'network_router_dead',
      label: 'Router will not turn on',
      deviceType: DeviceType.network,
      pathWhenIntact: ServicePath.homeService,
      pathWhenDamaged: ServicePath.pickup,
      isAmbiguous: true,
    ),
    ProblemSymptom(
      code: 'network_cctv_offline',
      label: 'CCTV or NVR offline',
      deviceType: DeviceType.network,
      pathWhenIntact: ServicePath.homeService,
      pathWhenDamaged: ServicePath.homeService,
    ),
  ];

  static List<ProblemSymptom> forDevice(DeviceType device) {
    return all
        .where((ProblemSymptom s) => s.deviceType == device)
        .toList(growable: false);
  }

  static ProblemSymptom? byCode(String? code) {
    for (final ProblemSymptom s in all) {
      if (s.code == code) return s;
    }
    return null;
  }

  /// Human label for a stored `problem_symptom` code, including the sentinel.
  ///
  /// Checks [IssueCatalog] first because that is what the picker writes now,
  /// then this catalog, which still holds codes from jobs posted before the
  /// issue catalog existed. A stored code must never render as raw wire text.
  static String labelFor(String? code) {
    if (code == notSureCode) return 'Not sure yet';
    return IssueCatalog.byCode(code)?.label ??
        byCode(code)?.label ??
        _humanise(code);
  }

  /// Last resort for a code neither catalog knows.
  ///
  /// The fallback used to print the stored value, so a job whose symptom
  /// predates the current catalog rendered as `appliance_aircon_not_cooling`
  /// on the dashboard, in chat subtitles and on the booking itself. This turns
  /// it into "Aircon not cooling": the device prefix is dropped because the
  /// device is already named beside it, underscores become spaces, and the
  /// first letter is capitalised.
  ///
  /// It is a display nicety, not a substitute for adding the code to the
  /// catalog - only the catalog carries the routing and the hint text.
  static String _humanise(String? code) {
    final String raw = (code ?? '').trim();
    if (raw.isEmpty) return 'Unknown problem';

    const List<String> prefixes = <String>[
      'laptop_',
      'phone_',
      'appliance_',
      'network_',
      'cctv_',
    ];
    String rest = raw;
    for (final String prefix in prefixes) {
      if (rest.startsWith(prefix)) {
        rest = rest.substring(prefix.length);
        break;
      }
    }

    final String spaced = rest.replaceAll('_', ' ').trim();
    if (spaced.isEmpty) return 'Unknown problem';
    return spaced[0].toUpperCase() + spaced.substring(1);
  }
}

/// The output of the guided classification step.
class ClassificationResult {
  const ClassificationResult({
    required this.servicePath,
    required this.confidence,
    required this.reason,
  });

  final ServicePath servicePath;
  final ClassificationConfidence confidence;

  /// Plain-language justification shown to the client, so the suggestion never
  /// looks like a black box.
  final String reason;

  /// Applies the rule base.
  ///
  /// * "Not sure" always routes to the IT community with low confidence.
  /// * An ambiguous symptom with no visible damage does the same, because a
  ///   wrong path costs the client a wasted visit.
  /// * Otherwise the symptom's own mapping decides, keyed on physical damage.
  static ClassificationResult evaluate({
    required String symptomCode,
    required bool hasPhysicalDamage,
  }) {
    if (symptomCode == ProblemCatalog.notSureCode) {
      return const ClassificationResult(
        servicePath: ServicePath.itCommunity,
        confidence: ClassificationConfidence.low,
        reason:
            'You are not sure what is wrong yet, so the IT community will '
            'narrow it down before anyone is dispatched.',
      );
    }

    // The issue catalog is canonical for anything chosen in the current
    // picker. The symptom list below is kept for rows already in the database.
    final IssueOption? issue = IssueCatalog.byCode(symptomCode);
    if (issue != null) return _fromIssue(issue, hasPhysicalDamage);

    final ProblemSymptom? symptom = ProblemCatalog.byCode(symptomCode);
    if (symptom == null) {
      return const ClassificationResult(
        servicePath: ServicePath.itCommunity,
        confidence: ClassificationConfidence.low,
        reason:
            'We could not classify that symptom, so it goes to the IT '
            'community for a first look.',
      );
    }

    if (symptom.isAmbiguous && !hasPhysicalDamage) {
      return ClassificationResult(
        servicePath: ServicePath.itCommunity,
        confidence: ClassificationConfidence.low,
        reason:
            '${symptom.label} can be either a software or a hardware fault. '
            'The IT community will confirm which before we send anyone.',
      );
    }

    final ServicePath path = hasPhysicalDamage
        ? symptom.pathWhenDamaged
        : symptom.pathWhenIntact;

    return ClassificationResult(
      servicePath: path,
      confidence: ClassificationConfidence.high,
      reason: hasPhysicalDamage
          ? 'Visible damage with ${symptom.label.toLowerCase()} normally needs '
                '${path.label.toLowerCase()}.'
          : '${symptom.label} with no visible damage is normally solved by '
                '${path.label.toLowerCase()}.',
    );
  }

  /// Turns a picked issue into a stored path plus a confidence.
  ///
  /// Visible damage overrides any route that avoids a visit: nobody can talk a
  /// client through a cracked panel, and "needs diagnosis" is moot once the
  /// fault is something you can see. Appliances are the standing exception -
  /// they are too big to travel, so they are serviced where they stand no
  /// matter what state they are in.
  static ClassificationResult _fromIssue(
    IssueOption issue,
    bool hasPhysicalDamage,
  ) {
    final ServiceRoute route = issue.suggestedRoute;

    if (hasPhysicalDamage && route != ServiceRoute.pickup) {
      if (issue.deviceType == DeviceType.appliance) {
        return ClassificationResult(
          servicePath: ServicePath.homeService,
          confidence: ClassificationConfidence.high,
          reason:
              'Damaged appliances are still repaired in place - they are too '
              'big to move for a ${issue.label.toLowerCase()}.',
        );
      }

      return ClassificationResult(
        servicePath: ServicePath.pickup,
        confidence: ClassificationConfidence.high,
        reason:
            'Visible damage with ${issue.label.toLowerCase()} needs shop '
            'tools and a matching part, so the unit is collected.',
      );
    }

    return ClassificationResult(
      servicePath: route.servicePath,
      confidence: route.confidence,
      reason:
          '${issue.label} normally means '
          '${route.label.toLowerCase()}. ${route.blurb}',
    );
  }
}
