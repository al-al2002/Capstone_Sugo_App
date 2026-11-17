import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../models/device_category.dart';
import '../models/issue_catalog.dart';
import '../models/labor_price_catalog.dart';

/// One answer to "What needs maintenance?" or "What needs installing?".
///
/// ## Why this file exists (2026-11-16)
///
/// These lists used to live inside the home screen's category row, and an
/// answer only picked a device: "Laptop or PC tune-up" opened the posting flow
/// on Laptop and left the client to find a tune-up in a list of faults, where
/// there was none. At the user's request the posting flow offers the same two
/// sheets, so the lists moved here, where both screens read them - and each
/// answer now lands on a real catalogue problem with a Davao price.
class ServiceOffer {
  const ServiceOffer({
    required this.kind,
    required this.label,
    required this.hint,
    required this.icon,
    required this.category,
    this.issueCode,
  });

  /// Maintenance or installation.
  final IssueKind kind;

  final String label;
  final String hint;
  final IconData icon;

  /// The device card this lands on.
  final DeviceCategory category;

  /// The exact problem this means, or null when there are several to choose
  /// from on the problem step - "Appliance" installation can be an aircon, a
  /// TV or a washing machine, and guessing would set the wrong price.
  final String? issueCode;

  /// The catalogue problems this offer covers.
  List<IssueOption> get issues {
    final String? code = issueCode;
    if (code != null) {
      final IssueOption? issue = IssueCatalog.byCode(code);
      return issue == null ? const <IssueOption>[] : <IssueOption>[issue];
    }
    return category.issues
        .where((IssueOption issue) => issue.kind == kind)
        .toList(growable: false);
  }

  /// "₱1,000", "₱800/camera", "From ₱500", or null when nothing is priced.
  String? get priceLabel {
    final List<String> fees = issues.map(_feeOf).nonNulls.toList();
    if (fees.isEmpty) return null;
    // One price, or several that agree ("₱800/camera" twice): show it as is.
    if (fees.toSet().length == 1) return fees.first;
    return _fromCheapest(fees);
  }
}

/// The catalogue fee for [issue], e.g. "₱1,000" or "₱800/camera".
String? _feeOf(IssueOption issue) => LaborPriceCatalog.forJob(
  deviceType: issue.deviceType,
  symptomCode: issue.code,
)?.fee;

/// "From ₱500": the cheapest of [fees], or null when none has a number.
String? _fromCheapest(Iterable<String> fees) {
  final List<int> amounts = <int>[
    for (final String fee in fees)
      if (RegExp(r'[\d,]+').firstMatch(fee)?.group(0) case final String digits)
        int.parse(digits.replaceAll(',', '')),
  ];
  if (amounts.isEmpty) return null;
  amounts.sort();
  return 'From ${Fmt.peso(amounts.first)}';
}

/// The two lists, shared by the home screen and step 1 of posting.
class ServiceOffers {
  const ServiceOffers._();

  static const List<ServiceOffer> maintenance = <ServiceOffer>[
    ServiceOffer(
      kind: IssueKind.maintenance,
      label: 'Laptop or PC tune-up',
      hint: 'Cleaning, thermal paste, speed',
      icon: Icons.laptop_mac_rounded,
      category: DeviceCategory.laptop,
      issueCode: 'laptop_cleaning_tune_up',
    ),
    ServiceOffer(
      kind: IssueKind.maintenance,
      label: 'Appliance cleaning',
      hint: 'Aircon cleaning, check-ups',
      icon: Icons.ac_unit_rounded,
      category: DeviceCategory.appliance,
    ),
    ServiceOffer(
      kind: IssueKind.maintenance,
      label: 'Phone or tablet',
      hint: 'Battery and port check',
      icon: Icons.smartphone_rounded,
      category: DeviceCategory.phone,
      issueCode: 'phone_checkup',
    ),
    ServiceOffer(
      kind: IssueKind.maintenance,
      label: 'Network check-up',
      hint: 'Slow Wi-Fi, dead spots',
      icon: Icons.router_rounded,
      category: DeviceCategory.network,
      issueCode: 'network_checkup',
    ),
  ];

  static const List<ServiceOffer> installation = <ServiceOffer>[
    ServiceOffer(
      kind: IssueKind.installation,
      label: 'Wi-Fi or router',
      hint: 'New router, mesh, access point',
      icon: Icons.router_rounded,
      category: DeviceCategory.network,
      issueCode: 'network_new_install',
    ),
    ServiceOffer(
      kind: IssueKind.installation,
      label: 'CCTV cameras',
      hint: 'New cameras and recorder',
      icon: Icons.videocam_rounded,
      category: DeviceCategory.cctv,
    ),
    ServiceOffer(
      kind: IssueKind.installation,
      label: 'Appliance',
      hint: 'Aircon, TV, washing machine',
      icon: Icons.kitchen_rounded,
      category: DeviceCategory.appliance,
    ),
  ];

  static List<ServiceOffer> of(IssueKind kind) => switch (kind) {
    IssueKind.maintenance => maintenance,
    IssueKind.installation => installation,
    IssueKind.repair => const <ServiceOffer>[],
  };

  /// The cheapest offer in [kind], for the card on step 1: "From ₱300".
  static String? startingPrice(IssueKind kind) => _fromCheapest(<String>[
    for (final ServiceOffer offer in of(kind))
      ...offer.issues.map(_feeOf).nonNulls,
  ]);
}
