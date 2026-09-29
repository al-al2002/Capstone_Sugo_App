import 'job_enums.dart';

/// What kind of help an issue points at, before anyone has looked at it.
///
/// ## Four routes, three storable paths
///
/// `jobs.service_path` is frozen at `('home_service','pickup','it_community')`
/// by the RB-CARS migration, and the schema is not moving. So this enum is a
/// **suggestion vocabulary**, not a column: it says what the rule base thinks
/// should happen, and [servicePath] is how that gets written down.
///
/// Two routes collapse onto `it_community`, and the pair is still
/// distinguishable because they disagree about [confidence]:
///
/// * [remoteAssist] - we are confident nobody needs to travel. High confidence.
/// * [needsDiagnosis] - nobody can tell yet what this is. Low confidence.
///
/// That is the same distinction the original catalog drew with its `isAmbiguous`
/// flag, so nothing about how RB-CARS reasons has changed; the vocabulary just
/// names it out loud instead of leaving it implied by a boolean.
enum ServiceRoute {
  homeService(
    'Home service',
    'A technician comes to you and fixes it on site.',
    ServicePath.homeService,
    ClassificationConfidence.high,
  ),
  pickup(
    'Shop pickup',
    'We collect the unit, repair it in the shop, and return it.',
    ServicePath.pickup,
    ClassificationConfidence.high,
  ),
  remoteAssist(
    'Remote assist',
    'This can usually be talked through without a visit.',
    ServicePath.itCommunity,
    ClassificationConfidence.high,
  ),
  needsDiagnosis(
    'Needs diagnosis',
    'The symptom alone does not say what is wrong. It gets a look first.',
    ServicePath.itCommunity,
    ClassificationConfidence.low,
  );

  const ServiceRoute(this.label, this.blurb, this.servicePath, this.confidence);

  final String label;
  final String blurb;

  /// The value actually written to `jobs.service_path`.
  final ServicePath servicePath;

  /// What this route implies about how sure the rule base is.
  final ClassificationConfidence confidence;
}

/// One selectable answer to "What is it doing?".
///
/// Richer than the symptom rows it replaces in the picker: it carries the
/// route it suggests, the hint shown under the dropdown, whether it should
/// jump the queue, and whether choosing it already answers the physical-damage
/// question.
class IssueOption {
  const IssueOption({
    required this.code,
    required this.label,
    required this.deviceType,
    required this.suggestedRoute,
    required this.hintText,
    this.isUrgent = false,
    this.impliesPhysicalDamage = false,
  });

  /// Stored in `jobs.problem_symptom`.
  ///
  /// Codes already used by the original catalog are reused deliberately, so
  /// jobs posted before this catalog existed still resolve to a label.
  final String code;

  final String label;
  final DeviceType deviceType;
  final ServiceRoute suggestedRoute;

  /// Shown under the dropdown once this option is picked. It explains the
  /// suggested route in the client's terms, so the routing never looks
  /// arbitrary.
  final String hintText;

  /// Safety or spoilage issues that should not sit in a queue. Drives the
  /// urgency default, not the price.
  final bool isUrgent;

  /// True when picking this option has already answered "is there physical
  /// damage?". A cracked screen is damage by definition, and making someone
  /// tick a box to confirm what they just said is a question with one answer.
  final bool impliesPhysicalDamage;
}

/// The selectable issues, grouped by device type.
///
/// Kept as data rather than branching inside the widget so the whole rule set
/// reads on one screen - the same reason the original catalog was written this
/// way.
class IssueCatalog {
  const IssueCatalog._();

  static const List<IssueOption> all = <IssueOption>[
    // ------------------------------------------------------------ laptop / PC
    IssueOption(
      code: 'laptop_slow_or_freezing',
      label: 'Very slow or freezing',
      deviceType: DeviceType.laptop,
      suggestedRoute: ServiceRoute.homeService,
      hintText: 'Usually software. A technician can clean it up at your place.',
    ),
    IssueOption(
      code: 'laptop_wont_power_on',
      label: 'Will not turn on',
      deviceType: DeviceType.laptop,
      suggestedRoute: ServiceRoute.needsDiagnosis,
      hintText:
          'Could be the charger, the battery or the board. It needs a '
          'look before anyone can quote it.',
    ),
    IssueOption(
      code: 'laptop_blue_screen',
      label: 'Blue screen or random crashes',
      deviceType: DeviceType.laptop,
      suggestedRoute: ServiceRoute.needsDiagnosis,
      hintText:
          'Crashes can be a driver, the memory or a failing drive. '
          'Guessing wrong costs you a wasted visit.',
    ),
    IssueOption(
      code: 'laptop_screen_broken',
      label: 'Screen cracked or display issue',
      deviceType: DeviceType.laptop,
      suggestedRoute: ServiceRoute.pickup,
      hintText: 'Panel swaps need shop tools and a matching part.',
      impliesPhysicalDamage: true,
    ),
    IssueOption(
      code: 'laptop_battery_not_charging',
      label: 'Battery not charging',
      deviceType: DeviceType.laptop,
      suggestedRoute: ServiceRoute.needsDiagnosis,
      hintText:
          'The charger, the port and the battery all look the same from '
          'the outside.',
    ),
    IssueOption(
      code: 'laptop_overheating',
      label: 'Overheating or loud fan',
      deviceType: DeviceType.laptop,
      suggestedRoute: ServiceRoute.homeService,
      hintText: 'Cleaning and thermal paste can be done where it stands.',
    ),
    IssueOption(
      code: 'laptop_input_dead',
      label: 'Keyboard or trackpad not working',
      deviceType: DeviceType.laptop,
      suggestedRoute: ServiceRoute.homeService,
      hintText: 'Often a driver or a loose ribbon, both fixable on site.',
    ),
    IssueOption(
      code: 'laptop_malware',
      label: 'Virus or malware',
      deviceType: DeviceType.laptop,
      suggestedRoute: ServiceRoute.homeService,
      hintText: 'Cleaned in place, so your files never leave the house.',
    ),
    IssueOption(
      code: 'laptop_no_os',
      label: 'Will not boot, or data recovery',
      deviceType: DeviceType.laptop,
      suggestedRoute: ServiceRoute.pickup,
      hintText: 'Recovery work needs bench equipment and time.',
    ),

    // --------------------------------------------------------- phone / tablet
    IssueOption(
      code: 'phone_screen_cracked',
      label: 'Screen cracked or LCD issue',
      deviceType: DeviceType.phone,
      suggestedRoute: ServiceRoute.pickup,
      hintText: 'Screen replacement is shop work.',
      impliesPhysicalDamage: true,
    ),
    IssueOption(
      code: 'phone_battery_drain',
      label: 'Battery draining or will not charge',
      deviceType: DeviceType.phone,
      suggestedRoute: ServiceRoute.pickup,
      hintText: 'Battery swaps mean opening the unit.',
    ),
    IssueOption(
      code: 'phone_wont_power_on',
      label: 'Will not turn on',
      deviceType: DeviceType.phone,
      suggestedRoute: ServiceRoute.pickup,
      hintText: 'Needs bench power and tools to tell what died.',
    ),
    IssueOption(
      code: 'phone_charging_port',
      label: 'Charging port broken',
      deviceType: DeviceType.phone,
      suggestedRoute: ServiceRoute.pickup,
      hintText: 'The port is soldered to the board, so this is shop work.',
      impliesPhysicalDamage: true,
    ),
    IssueOption(
      code: 'phone_camera_dead',
      label: 'Camera not working',
      deviceType: DeviceType.phone,
      suggestedRoute: ServiceRoute.pickup,
      hintText: 'Module replacement needs the unit opened.',
    ),
    IssueOption(
      code: 'phone_water_damage',
      label: 'Water damage',
      deviceType: DeviceType.phone,
      suggestedRoute: ServiceRoute.pickup,
      hintText:
          'Corrosion spreads while the unit sits. The sooner it is '
          'cleaned, the more survives.',
      isUrgent: true,
      impliesPhysicalDamage: true,
    ),
    IssueOption(
      code: 'phone_software_stuck',
      label: 'Software glitch',
      deviceType: DeviceType.phone,
      suggestedRoute: ServiceRoute.remoteAssist,
      hintText: 'Usually solvable by walking through it. No visit needed.',
    ),
    IssueOption(
      code: 'phone_audio_dead',
      label: 'Speaker or mic not working',
      deviceType: DeviceType.phone,
      suggestedRoute: ServiceRoute.pickup,
      hintText:
          'Could be a blocked grille or a dead module. Both are bench '
          'work.',
    ),

    // --------------------------------------------------------------- appliance
    IssueOption(
      code: 'appliance_no_power',
      label: 'Not turning on',
      deviceType: DeviceType.appliance,
      suggestedRoute: ServiceRoute.needsDiagnosis,
      hintText: 'Could be the outlet, the cord or the control board.',
    ),
    IssueOption(
      code: 'appliance_strange_noise',
      label: 'Unusual noise',
      deviceType: DeviceType.appliance,
      suggestedRoute: ServiceRoute.homeService,
      hintText: 'A technician needs to hear it running to place the sound.',
    ),
    IssueOption(
      code: 'appliance_not_cooling',
      label: 'Not cooling or heating properly',
      deviceType: DeviceType.appliance,
      suggestedRoute: ServiceRoute.homeService,
      hintText: 'Large units are always serviced where they stand.',
    ),
    IssueOption(
      code: 'appliance_water_leak',
      label: 'Leaking water or gas',
      deviceType: DeviceType.appliance,
      suggestedRoute: ServiceRoute.homeService,
      hintText:
          'A leak damages the room around it, and a gas leak is a '
          'safety matter. This is treated as urgent.',
      isUrgent: true,
      impliesPhysicalDamage: true,
    ),
    IssueOption(
      code: 'appliance_electrical_fault',
      label: 'Electrical issue or tripping breaker',
      deviceType: DeviceType.appliance,
      suggestedRoute: ServiceRoute.homeService,
      hintText:
          'A breaker tripping is the house protecting itself. Stop using '
          'the unit until someone checks it.',
      isUrgent: true,
    ),
    IssueOption(
      code: 'appliance_part_replacement',
      label: 'Part replacement needed',
      deviceType: DeviceType.appliance,
      suggestedRoute: ServiceRoute.needsDiagnosis,
      hintText:
          'The part has to be identified and sourced before a visit is '
          'worth booking.',
    ),

    // ----------------------------------------------------------- network / WiFi
    IssueOption(
      code: 'network_no_internet',
      label: 'No internet connection',
      deviceType: DeviceType.network,
      suggestedRoute: ServiceRoute.remoteAssist,
      hintText:
          'Most outages are settings or the provider. Worth trying '
          'remotely before anyone travels.',
    ),
    IssueOption(
      code: 'network_weak_signal',
      label: 'Slow or intermittent connection',
      deviceType: DeviceType.network,
      suggestedRoute: ServiceRoute.homeService,
      hintText: 'Coverage can only be measured in the rooms where it drops.',
    ),
    IssueOption(
      code: 'network_router_dead',
      label: 'Router will not turn on',
      deviceType: DeviceType.network,
      suggestedRoute: ServiceRoute.pickup,
      hintText: 'A dead router is small enough to travel to the bench.',
    ),
    IssueOption(
      code: 'network_new_install',
      label: 'Router or Wi-Fi installation',
      deviceType: DeviceType.network,
      suggestedRoute: ServiceRoute.homeService,
      hintText: 'Cabling and placement are decided in the building itself.',
    ),
    // ------------------------------------------------------------ CCTV
    //
    // Filed under `network` because `jobs.device_type` is checked against
    // ('laptop','phone','appliance','network') and that constraint is frozen.
    // A camera system is a network before it is a camera, so this is where it
    // belongs anyway - `job_device_candidates()` maps the category onto the
    // `router` and `cctv` specialisations.
    IssueOption(
      code: 'cctv_new_install',
      label: 'CCTV: new installation',
      deviceType: DeviceType.network,
      suggestedRoute: ServiceRoute.homeService,
      hintText:
          'Camera placement and cable runs are decided in the building '
          'itself, so this always starts with a visit.',
    ),
    IssueOption(
      code: 'cctv_no_video',
      label: 'Camera not recording, or no video',
      deviceType: DeviceType.network,
      suggestedRoute: ServiceRoute.needsDiagnosis,
      hintText:
          'The camera, the cable and the recorder all produce this same '
          'symptom. It needs a look before anyone can quote it.',
    ),
    IssueOption(
      code: 'cctv_offline',
      label: 'Camera offline, or not connecting to the app',
      deviceType: DeviceType.network,
      suggestedRoute: ServiceRoute.remoteAssist,
      hintText:
          'Usually the network settings or the app account. Worth '
          'trying remotely before anyone travels.',
    ),
    IssueOption(
      code: 'cctv_recorder_dead',
      label: 'DVR or NVR not working',
      deviceType: DeviceType.network,
      suggestedRoute: ServiceRoute.needsDiagnosis,
      hintText:
          'Could be the power supply, the hard drive or the board. '
          'Which one decides whether your footage survives.',
    ),
    IssueOption(
      code: 'cctv_night_vision',
      label: 'Night vision not working',
      deviceType: DeviceType.network,
      suggestedRoute: ServiceRoute.homeService,
      hintText:
          'Often the infrared cut filter or a setting, and it can only '
          'be judged where the camera is pointing.',
    ),
    IssueOption(
      code: 'cctv_cable_damage',
      label: 'CCTV cable or wiring damage',
      deviceType: DeviceType.network,
      suggestedRoute: ServiceRoute.homeService,
      hintText:
          'Cable runs are fixed in place, so the repair happens where '
          'the damage is.',
      impliesPhysicalDamage: true,
    ),
    IssueOption(
      code: 'cctv_expand_system',
      label: 'Add more cameras to an existing system',
      deviceType: DeviceType.network,
      suggestedRoute: ServiceRoute.homeService,
      hintText:
          'The technician checks the recorder has free channels and '
          'the power supply has headroom before quoting.',
    ),

    IssueOption(
      code: 'network_device_wont_connect',
      label: 'Device will not connect',
      deviceType: DeviceType.network,
      suggestedRoute: ServiceRoute.remoteAssist,
      hintText:
          'Usually a password, a band or a setting. Talked through '
          'without a visit.',
    ),
  ];

  static IssueOption? byCode(String? code) {
    for (final IssueOption option in all) {
      if (option.code == code) return option;
    }
    return null;
  }
}
