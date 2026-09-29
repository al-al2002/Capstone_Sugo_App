import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_sheet.dart';
import '../../rb_cars/models/device_category.dart';

/// The home screen's service categories.
///
/// ## How eight tiles map onto what the matching engine understands
///
/// RB-CARS classifies a job by device - laptop, phone, appliance, network,
/// CCTV (`DeviceCategory`) - because that is what decides which technicians are
/// qualified. The brief's categories are how *clients* think: "Installation",
/// "Maintenance". Those are kinds of work, not kinds of device, and inventing
/// a device type for them would send jobs to the matcher that no technician's
/// specialisation can satisfy.
///
/// So each tile resolves to a real category, one way or another:
///
/// * The five device tiles open the posting flow with that category chosen.
/// * **Installation** and **Maintenance** ask one quick question - "for what?"
///   - and then do the same. The issue catalog already carries installation
///   jobs (`network_new_install`, `cctv_new_install`) and on-site cleaning and
///   tune-ups, so these land on real symptoms.
/// * **Other** opens the device picker with nothing chosen.
///
/// Labels are sentence case since the Dispatch redesign, like every other
/// label in the app ("Computer & laptop", not "Computer & Laptop").
enum HomeServiceCategory {
  computer(
    'Computer & laptop',
    Icons.laptop_mac_rounded,
    DeviceCategory.laptop,
  ),
  mobile(
    'Mobile device',
    Icons.smartphone_rounded,
    DeviceCategory.phone,
  ),
  appliance(
    'Appliance repair',
    Icons.kitchen_rounded,
    DeviceCategory.appliance,
  ),
  network(
    'Network & Wi-Fi',
    Icons.router_rounded,
    DeviceCategory.network,
  ),
  cctv(
    'CCTV & security',
    Icons.videocam_rounded,
    DeviceCategory.cctv,
  ),
  installation(
    'Installation',
    Icons.construction_rounded,
    null,
  ),
  maintenance(
    'Maintenance',
    Icons.cleaning_services_rounded,
    null,
  ),
  other(
    'Other services',
    Icons.grid_view_rounded,
    null,
  );

  const HomeServiceCategory(this.label, this.icon, this.device);

  final String label;
  final IconData icon;

  /// The device this tile resolves to directly, or null when it needs a
  /// follow-up question (or none, for [other]).
  final DeviceCategory? device;

  /// Search keywords beyond the label, so "aircon" finds Appliance Repair and
  /// "wifi" finds Network.
  List<String> get keywords => switch (this) {
    computer => <String>['laptop', 'pc', 'desktop', 'computer', 'mac', 'windows'],
    mobile => <String>['phone', 'tablet', 'iphone', 'android', 'cellphone', 'screen'],
    appliance => <String>[
      'aircon', 'ac', 'fridge', 'refrigerator', 'washing machine', 'tv', 'oven',
      'microwave', 'electric fan',
    ],
    network => <String>['wifi', 'wi-fi', 'router', 'internet', 'modem', 'lan'],
    cctv => <String>['cctv', 'camera', 'security', 'dvr', 'nvr'],
    installation => <String>['install', 'setup', 'set up', 'mount'],
    maintenance => <String>['maintenance', 'cleaning', 'tune-up', 'check-up'],
    other => <String>['other', 'help'],
  };
}

/// What Installation and Maintenance ask before starting.
const Map<HomeServiceCategory, List<(String, String, IconData, DeviceCategory)>>
_followUps = <HomeServiceCategory, List<(String, String, IconData, DeviceCategory)>>{
  HomeServiceCategory.installation: <(String, String, IconData, DeviceCategory)>[
    ('Wi-Fi or router', 'New router, mesh, access point', Icons.router_rounded,
        DeviceCategory.network),
    ('CCTV cameras', 'New cameras and recorder', Icons.videocam_rounded,
        DeviceCategory.cctv),
    ('Appliance', 'Aircon, TV, washing machine', Icons.kitchen_rounded,
        DeviceCategory.appliance),
  ],
  HomeServiceCategory.maintenance: <(String, String, IconData, DeviceCategory)>[
    ('Laptop or PC tune-up', 'Cleaning, thermal paste, speed', Icons.laptop_mac_rounded,
        DeviceCategory.laptop),
    ('Appliance cleaning', 'Aircon cleaning, check-ups', Icons.kitchen_rounded,
        DeviceCategory.appliance),
    ('Phone or tablet', 'Battery and port check', Icons.smartphone_rounded,
        DeviceCategory.phone),
    ('Network check-up', 'Slow Wi-Fi, dead spots', Icons.router_rounded,
        DeviceCategory.network),
  ],
};

/// Resolves a tile tap to a device category, asking the follow-up question
/// for Installation and Maintenance. Returns null for "Other", or when the
/// follow-up sheet was dismissed; [onResolved] is only called with an answer.
Future<void> resolveHomeCategory(
  BuildContext context,
  HomeServiceCategory category, {
  required void Function(DeviceCategory? device) onResolved,
}) async {
  if (category.device != null || category == HomeServiceCategory.other) {
    onResolved(category.device);
    return;
  }

  final List<(String, String, IconData, DeviceCategory)> options =
      _followUps[category]!;

  final DeviceCategory? picked = await showSugoBottomSheet<DeviceCategory>(
    context: context,
    title: category == HomeServiceCategory.installation
        ? 'What needs installing?'
        : 'What needs maintenance?',
    subtitle: 'We will match you with technicians who do exactly this.',
    builder: (BuildContext sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final (String label, String hint, IconData icon, DeviceCategory d)
            in options)
          SugoSheetOption(
            icon: icon,
            label: label,
            hint: hint,
            onTap: () => Navigator.of(sheetContext).pop(d),
          ),
      ],
    ),
  );
  if (picked != null) onResolved(picked);
}

/// A 4 x 2 grid of category tiles.
class ServiceCategoryGrid extends StatelessWidget {
  const ServiceCategoryGrid({super.key, required this.onSelect});

  final void Function(HomeServiceCategory category) onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Four across on a normal phone, three on a narrow one. At 320dp the
        // four-column tile is 68px wide, which breaks "Computer & Laptop" into
        // "Compu / ter & L…" - three columns keeps whole words.
        const double gap = AppSizes.md;
        final int columns = constraints.maxWidth < 330 ? 3 : 4;
        final double tile =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: AppSizes.lg,
          children: <Widget>[
            for (final HomeServiceCategory category
                in HomeServiceCategory.values)
              SizedBox(
                width: tile,
                child: _CategoryTile(
                  category: category,
                  onTap: () => onSelect(category),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onTap});

  final HomeServiceCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: category.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
          child: Column(
            children: <Widget>[
              // One tile, not a tile inside a tile: a white square with the
              // hairline edge every card has, and a navy icon. The old
              // blue-on-soft-blue disc inside a shadowed square was two
              // containers doing one job.
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSizes.radius),
                  border: Border.all(color: AppColors.border),
                ),
                alignment: Alignment.center,
                child: Icon(category.icon, size: 24, color: AppColors.primary),
              ),
              const SizedBox(height: AppSizes.sm),
              Text(
                category.label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.micro.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
