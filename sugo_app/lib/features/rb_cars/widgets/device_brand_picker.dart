import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../onboarding/models/specialization_catalog.dart';
import '../models/job_enums.dart' as job_enums;
import '../theme/posting_text.dart';
import 'posting_field.dart';
import '../../../core/constants/app_colors.dart';

/// Lets the client name the exact device and brand they need repaired.
///
/// ## Why this exists
///
/// Stage 1 of RB-CARS ranks a technician who passed an assessment on *this
/// brand and device* above one who merely repairs the category. That ladder
/// can only fire if the job actually carries a brand - without this control
/// `jobs.brand` is always null, every candidate falls to the device-only rung,
/// and the brand matching is dead code.
///
/// ## Why it reads from SpecializationCatalog
///
/// The technician picks their brands from that same catalogue. Sharing it is
/// what guarantees the two sides use identical strings - a separate list here
/// would drift, and "Samsung" against "samsung " would silently never match.
///
/// ## Why both are optional
///
/// A client with a broken aircon may genuinely not know the brand, and
/// certainly should not be blocked from posting over it. Leaving this blank
/// degrades Stage 1 to device-category matching, which is the behaviour the
/// engine already handles for an unspecified brand.
///
/// ## Why dropdowns rather than chip rows
///
/// Brand lists run to a dozen entries. As chips they wrapped to four or five
/// rows and pushed the rest of the step off screen; as a dropdown the field is
/// one line tall whether it holds two options or twenty.
class DeviceBrandPicker extends StatelessWidget {
  const DeviceBrandPicker({
    super.key,
    required this.category,
    required this.deviceDetail,
    required this.brand,
    required this.onChanged,
  });

  /// The coarse RB-CARS category already chosen on the classification step.
  final job_enums.DeviceType category;

  final String? deviceDetail;
  final String? brand;

  final void Function({String? deviceDetail, String? brand}) onChanged;

  /// The catalogue devices that belong to this coarse category.
  ///
  /// Mirrors `job_device_candidates()` in SQL. Kept in step by
  /// `test/features/rb_cars/device_brand_picker_test.dart`, which fails if the
  /// two ever diverge.
  static List<DeviceType> devicesFor(job_enums.DeviceType category) {
    const Map<String, List<String>> byCategory = <String, List<String>>{
      'laptop': <String>['laptop', 'desktop'],
      'phone': <String>['smartphone', 'tablet'],
      'appliance': <String>[
        'aircon',
        'refrigerator',
        'washing_machine',
        'television',
        'microwave',
      ],
      // A router and a camera system are the two things people call about
      // under "network". Before the catalogue carried them this list was
      // empty, so a network job could not name a device or a brand at all and
      // every candidate fell to the device-only rung of the ladder.
      'network': <String>['router', 'cctv'],
    };

    final List<String> wires = byCategory[category.wire] ?? const <String>[];

    return wires
        .map(SpecializationCatalog.deviceByWire)
        .whereType<DeviceType>()
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final List<DeviceType> devices = devicesFor(category);

    // Nothing to narrow. A network job is matched on the category alone.
    if (devices.isEmpty) return const SizedBox.shrink();

    final DeviceType? selected = devices
        .where((DeviceType d) => d.wire == deviceDetail)
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // One candidate means the card on step 1 already settled it - showing a
        // dropdown with a single entry is a question with one answer, so the
        // whole labelled block is skipped rather than rendered read-only twice.
        if (devices.length > 1) ...<Widget>[
          PostingLabel(
            'Which one is it?',
            state: selected == null ? FieldState.isNew : FieldState.saved,
          ),
          const SizedBox(height: AppSizes.sm),
          DropdownButtonFormField<String>(
            key: ValueKey<String>('device-${category.wire}'),
            initialValue: selected?.wire,
            isExpanded: true,
            decoration: const InputDecoration(hintText: 'Which one is it?'),
            items: devices
                .map(
                  (DeviceType device) => DropdownMenuItem<String>(
                    value: device.wire,
                    child: Text(
                      device.label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                )
                .toList(growable: false),
            // Changing the device invalidates the brand: "Lenovo" is not an
            // answer to "which aircon".
            onChanged: (String? wire) => onChanged(deviceDetail: wire),
          ),
          const SizedBox(height: AppSizes.xl),
        ],

        // Brands only make sense once a device is chosen: the list differs per
        // device, and showing every brand on the platform would be noise.
        if (selected != null) ...<Widget>[
          PostingLabel(
            'Brand',
            state: brand == null ? FieldState.isNew : FieldState.saved,
          ),
          const SizedBox(height: AppSizes.sm),
          DropdownButtonFormField<String>(
            key: ValueKey<String>('brand-${selected.wire}'),
            initialValue: brand,
            isExpanded: true,
            decoration: InputDecoration(
              hintText: 'Select brand - e.g. ${selected.brands.first}',
            ),
            items: <DropdownMenuItem<String>>[
              ...selected.brands.map(
                (String option) => DropdownMenuItem<String>(
                  value: option,
                  child: Text(
                    option,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ),
              // "Not sure" is an explicit answer, not an absence. It stores
              // null, which the engine reads as "match on device alone".
              const DropdownMenuItem<String>(
                value: _notSure,
                child: Text(
                  'I am not sure',
                  style: TextStyle(
                    fontSize: 15,
                    fontStyle: FontStyle.italic,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
            onChanged: (String? value) => onChanged(
              deviceDetail: selected.wire,
              brand: value == _notSure ? null : value,
            ),
          ),
          const SizedBox(height: AppSizes.sm),
          const Text(
            'Naming the brand puts technicians assessed on your machine at the '
            'top. Leaving it blank rules nobody out.',
            style: PostingText.caption,
          ),
        ],
      ],
    );
  }

  /// Sentinel for the explicit "I am not sure" row. A `DropdownMenuItem` with a
  /// null value cannot be distinguished from "nothing picked yet".
  static const String _notSure = '__not_sure__';
}
