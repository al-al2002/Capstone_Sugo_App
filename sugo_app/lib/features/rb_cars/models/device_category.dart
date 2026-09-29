import 'issue_catalog.dart';
import 'job_enums.dart';

/// The five cards on "What needs fixing?".
///
/// ## Why this is not [DeviceType]
///
/// `jobs.device_type` is checked against
/// `('laptop','phone','appliance','network')` by the RB-CARS migration, and
/// that constraint is frozen. Clients, though, do not think of a camera system
/// as "a network" - they look for the word CCTV and stop reading when they do
/// not find it. Folding both behind one "Network / CCTV" card made the picker
/// honest about the column and dishonest about the product.
///
/// So this enum is a **presentation vocabulary**, the same trick
/// [ServiceRoute] plays on `jobs.service_path`: five cards, four storable
/// values, and [deviceType] is how a card gets written down. Nothing about the
/// schema or the matcher moves - `job_device_candidates()` already maps the
/// `network` category onto the `router` and `cctv` specialisations, so a CCTV
/// job reaches exactly the technicians it reached before.
///
/// The split pays for itself twice more:
///
/// * The symptom dropdown is halved. Picking CCTV shows seven camera symptoms
///   instead of twelve mixed ones, so nobody scrolls past "Router will not
///   turn on" to find "No video".
/// * [deviceDetailWire] pre-answers the device question on step 2. A client who
///   tapped the CCTV card has already said it is a camera; the brand picker
///   opens with `cctv` chosen rather than asking again.
enum DeviceCategory {
  laptop('Laptop / PC', DeviceType.laptop, 'laptop'),
  phone('Phone / Tablet', DeviceType.phone, 'smartphone'),
  appliance('Appliance', DeviceType.appliance, null),
  network('Network / Wi-Fi', DeviceType.network, 'router'),
  cctv('CCTV', DeviceType.network, 'cctv');

  const DeviceCategory(this.label, this.deviceType, this.deviceDetailWire);

  final String label;

  /// The value actually written to `jobs.device_type`.
  final DeviceType deviceType;

  /// The `technician_specializations.device_type` this card implies, used to
  /// pre-select the chip on the detail step. Null where the card is too coarse
  /// to imply one - "Appliance" could be any of five machines.
  final String? deviceDetailWire;

  /// The card a saved job was posted from, for "Edit post".
  ///
  /// `network` and `cctv` write the same `jobs.device_type`, so the job alone
  /// cannot say which was tapped. The symptom can: every camera issue code is
  /// namespaced `cctv_` (see [owns]), and a camera device settles the rest.
  static DeviceCategory forJob({
    required DeviceType deviceType,
    String? deviceDetail,
    String? symptomCode,
  }) {
    if (deviceType == DeviceType.network) {
      final bool camera =
          (symptomCode?.startsWith('cctv_') ?? false) || deviceDetail == 'cctv';
      return camera ? DeviceCategory.cctv : DeviceCategory.network;
    }
    return DeviceCategory.values.firstWhere(
      (DeviceCategory c) => c.deviceType == deviceType,
      orElse: () => DeviceCategory.laptop,
    );
  }

  /// True when [issue] belongs on this card.
  ///
  /// Only the network pair needs splitting, and the issue codes already carry
  /// the answer: every camera symptom is namespaced `cctv_`, every router one
  /// `network_`. Adding a camera symptom is still one row in [IssueCatalog] -
  /// it lands on the right card by virtue of its code.
  bool owns(IssueOption issue) {
    if (issue.deviceType != deviceType) return false;
    if (deviceType != DeviceType.network) return true;
    final bool isCamera = issue.code.startsWith('cctv_');
    return this == DeviceCategory.cctv ? isCamera : !isCamera;
  }

  /// The selectable symptoms for this card, in catalogue order.
  List<IssueOption> get issues =>
      IssueCatalog.all.where(owns).toList(growable: false);
}
