import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/features/onboarding/models/specialization_catalog.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart' as job_enums;
import 'package:sugo_app/features/rb_cars/widgets/device_brand_picker.dart';

/// Pins the client-side device list to `job_device_candidates()` in SQL.
///
/// The two vocabularies are the trap this whole area sets. `jobs.device_type`
/// is coarse (laptop | phone | appliance | network); the technician's
/// `technician_specializations.device_type` is fine (laptop, desktop, aircon,
/// ...). If the picker offers a device the SQL bridge does not map — or maps
/// it to a different category — the job would carry a `device_detail` that
/// matches no technician, and Stage 1 would return nobody with no error
/// anywhere to explain why.
void main() {
  /// The mapping as `20260907000010_matching_inputs.sql` defines it.
  const Map<String, List<String>> sqlMapping = <String, List<String>>{
    'laptop': <String>['laptop', 'desktop'],
    'phone': <String>['smartphone', 'tablet'],
    'appliance': <String>[
      'aircon',
      'refrigerator',
      'washing_machine',
      'television',
      'microwave',
    ],
    'network': <String>['router', 'cctv'],
  };

  group('DeviceBrandPicker.devicesFor mirrors job_device_candidates()', () {
    for (final job_enums.DeviceType category in job_enums.DeviceType.values) {
      test('${category.wire} offers exactly what SQL maps', () {
        final List<String> offered = DeviceBrandPicker.devicesFor(
          category,
        ).map((DeviceType d) => d.wire).toList();

        expect(
          offered,
          sqlMapping[category.wire],
          reason:
              'The picker and job_device_candidates() disagree for '
              '${category.wire}. A job posted here would carry a device_detail '
              'the matcher cannot use.',
        );
      });
    }

    test('network offers the router and camera devices', () {
      expect(
        DeviceBrandPicker.devicesFor(
          job_enums.DeviceType.network,
        ).map((DeviceType d) => d.wire),
        containsAll(<String>['router', 'cctv']),
      );
    });
  });

  group('every offered device exists in the shared catalogue', () {
    test('so client and technician use identical device strings', () {
      for (final job_enums.DeviceType category in job_enums.DeviceType.values) {
        for (final DeviceType device in DeviceBrandPicker.devicesFor(
          category,
        )) {
          expect(
            SpecializationCatalog.deviceByWire(device.wire),
            isNotNull,
            reason: '${device.wire} is not in SpecializationCatalog',
          );
          // Every offered device must also belong to an assessment track,
          // otherwise no technician could ever be verified on it.
          expect(
            device.track,
            isNotNull,
            reason: '${device.wire} belongs to no assessment track',
          );
        }
      }
    });

    test(
      'offered brands come from the catalogue the technician picks from',
      () {
        // A separate brand list here would drift, and "Samsung" against
        // "samsung " would silently never match.
        final List<DeviceType> laptops = DeviceBrandPicker.devicesFor(
          job_enums.DeviceType.laptop,
        );

        expect(laptops, isNotEmpty);

        for (final DeviceType device in laptops) {
          final DeviceType? catalogue = SpecializationCatalog.deviceByWire(
            device.wire,
          );
          expect(device.brands, catalogue!.brands);
        }
      },
    );
  });
}
