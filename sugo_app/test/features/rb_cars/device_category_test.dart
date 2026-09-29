import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/features/onboarding/models/specialization_catalog.dart'
    as catalog;
import 'package:sugo_app/features/rb_cars/models/device_category.dart';
import 'package:sugo_app/features/rb_cars/models/issue_catalog.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';
import 'package:sugo_app/features/rb_cars/widgets/device_brand_picker.dart';

/// Pins the five-card picker to the four-value column underneath it.
///
/// `DeviceCategory` splits the `network` category into a Wi-Fi card and a CCTV
/// card so the client can find the word they came looking for. That split lives
/// only in the UI - `jobs.device_type` is still checked against
/// `('laptop','phone','appliance','network')` and the migration is frozen. The
/// tests below are the three ways that arrangement could quietly break:
///
/// 1. A card starts writing a value the check constraint rejects.
/// 2. A symptom falls between the two network cards and becomes unreachable.
/// 3. A card pre-selects a `device_detail` the matcher does not map.
void main() {
  group('every card writes a storable device_type', () {
    test('each category maps onto a DeviceType the migration allows', () {
      // The four values in the `jobs.device_type` check constraint.
      const Set<String> storable = <String>{
        'laptop',
        'phone',
        'appliance',
        'network',
      };

      for (final DeviceCategory category in DeviceCategory.values) {
        expect(
          storable,
          contains(category.deviceType.wire),
          reason:
              '${category.name} would write "${category.deviceType.wire}" to '
              'jobs.device_type, which the check constraint rejects.',
        );
      }
    });

    test('Wi-Fi and CCTV are two cards over one column', () {
      expect(DeviceCategory.network.deviceType, DeviceType.network);
      expect(DeviceCategory.cctv.deviceType, DeviceType.network);
    });
  });

  group('the split loses no symptoms', () {
    test('every catalogue issue belongs to exactly one card', () {
      for (final IssueOption issue in IssueCatalog.all) {
        final List<DeviceCategory> owners = DeviceCategory.values
            .where((DeviceCategory c) => c.owns(issue))
            .toList();

        expect(
          owners,
          hasLength(1),
          reason:
              '"${issue.code}" is claimed by ${owners.length} cards. A symptom '
              'on no card cannot be chosen; one on two cards is offered twice.',
        );
      }
    });

    test('the two network cards partition the network issues', () {
      final List<IssueOption> networkIssues = IssueCatalog.all
          .where((IssueOption i) => i.deviceType == DeviceType.network)
          .toList();

      expect(
        DeviceCategory.network.issues.length +
            DeviceCategory.cctv.issues.length,
        networkIssues.length,
      );
      expect(DeviceCategory.cctv.issues, isNotEmpty);
      expect(DeviceCategory.network.issues, isNotEmpty);
    });

    test('the CCTV card holds the camera symptoms and nothing else', () {
      expect(
        DeviceCategory.cctv.issues.every(
          (IssueOption i) => i.code.startsWith('cctv_'),
        ),
        isTrue,
      );
      expect(
        DeviceCategory.network.issues.any(
          (IssueOption i) => i.code.startsWith('cctv_'),
        ),
        isFalse,
        reason:
            'A camera symptom listed under Wi-Fi is the confusion the split '
            'was made to remove.',
      );
    });

    test('every card offers something to pick', () {
      for (final DeviceCategory category in DeviceCategory.values) {
        expect(
          category.issues,
          isNotEmpty,
          reason:
              '${category.name} is a dead end: tapping it opens an empty '
              'symptom dropdown.',
        );
      }
    });
  });

  group('pre-selected device_detail stays matchable', () {
    test('each implied device is one the matcher maps to that category', () {
      for (final DeviceCategory category in DeviceCategory.values) {
        final String? wire = category.deviceDetailWire;
        if (wire == null) continue;

        final List<String> mapped = DeviceBrandPicker.devicesFor(
          category.deviceType,
        ).map((catalog.DeviceType d) => d.wire).toList();

        expect(
          mapped,
          contains(wire),
          reason:
              '${category.name} pre-selects "$wire", which '
              'job_device_candidates() does not map to '
              '${category.deviceType.wire}. Stage 1 would score every '
              'technician on the device-only rung and nothing would say why.',
        );
      }
    });
  });
}
