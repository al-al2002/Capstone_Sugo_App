import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../rb_cars/config/service_offers.dart';
import '../../rb_cars/models/device_category.dart';
import '../../rb_cars/models/issue_catalog.dart';
import '../../rb_cars/widgets/press_scale.dart';
import '../../rb_cars/widgets/service_offer_sheet.dart';

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
///   - and then do the same, landing on a real catalogue problem: since
///   2026-11-16 the catalogue carries the work itself (aircon cleaning, a
///   laptop tune-up, TV mounting) with Davao prices - see [ServiceOffers].
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
  mobile('Mobile device', Icons.smartphone_rounded, DeviceCategory.phone),
  appliance(
    'Appliance repair',
    Icons.kitchen_rounded,
    DeviceCategory.appliance,
  ),
  network('Network & Wi-Fi', Icons.router_rounded, DeviceCategory.network),
  cctv('CCTV & security', Icons.videocam_rounded, DeviceCategory.cctv),
  installation('Installation', Icons.construction_rounded, null),
  maintenance('Maintenance', Icons.cleaning_services_rounded, null),
  other('Other services', Icons.grid_view_rounded, null);

  const HomeServiceCategory(this.label, this.icon, this.device);

  final String label;
  final IconData icon;

  /// The device this tile resolves to directly, or null when it needs a
  /// follow-up question (or none, for [other]).
  final DeviceCategory? device;

  /// The tile's wash and icon colour (2026-11-16). Each category its own, so
  /// the grid is scanned by colour as well as by word; Maintenance and
  /// Installation match their cards in the posting flow.
  (Color, Color) get tone => switch (this) {
    computer => (AppColors.primarySoft, AppColors.primary),
    mobile => (AppColors.secondarySoft, AppColors.secondaryDark),
    appliance => (AppColors.successSoft, AppColors.success),
    network => (AppColors.violetSoft, AppColors.violet),
    cctv => (AppColors.errorSoft, AppColors.error),
    installation => (AppColors.accentSoft, AppColors.accentDark),
    maintenance => (AppColors.cyanSoft, AppColors.cyanDark),
    other => (AppColors.fieldFill, AppColors.textSecondary),
  };

  /// Search keywords beyond the label, so "aircon" finds Appliance Repair and
  /// "wifi" finds Network.
  List<String> get keywords => switch (this) {
    computer => <String>[
      'laptop',
      'pc',
      'desktop',
      'computer',
      'mac',
      'windows',
    ],
    mobile => <String>[
      'phone',
      'tablet',
      'iphone',
      'android',
      'cellphone',
      'screen',
    ],
    appliance => <String>[
      'aircon',
      'ac',
      'fridge',
      'refrigerator',
      'washing machine',
      'tv',
      'oven',
      'microwave',
      'electric fan',
    ],
    network => <String>['wifi', 'wi-fi', 'router', 'internet', 'modem', 'lan'],
    cctv => <String>['cctv', 'camera', 'security', 'dvr', 'nvr'],
    installation => <String>['install', 'setup', 'set up', 'mount'],
    maintenance => <String>['maintenance', 'cleaning', 'tune-up', 'check-up'],
    other => <String>['other', 'help'],
  };
}

/// Resolves a tile tap to a device category - and, for Installation and
/// Maintenance, the exact problem - asking the follow-up question first.
///
/// Since 2026-11-16 the follow-up sheet is the shared [showServiceOfferSheet],
/// the same one step 1 of posting opens, so an answer such as "Laptop or PC
/// tune-up" lands on the tune-up itself with its Davao price, not just on
/// "Laptop". [onResolved] gets a null symptom when the answer covers several
/// problems (an appliance install could be an aircon or a TV), and is only
/// called with an answer: "Other" resolves to no device, a dismissed sheet to
/// nothing at all.
Future<void> resolveHomeCategory(
  BuildContext context,
  HomeServiceCategory category, {
  required void Function(DeviceCategory? device, String? symptomCode)
  onResolved,
}) async {
  final IssueKind? kind = switch (category) {
    HomeServiceCategory.installation => IssueKind.installation,
    HomeServiceCategory.maintenance => IssueKind.maintenance,
    _ => null,
  };
  if (kind == null) {
    onResolved(category.device, null);
    return;
  }

  final ServiceOffer? picked = await showServiceOfferSheet(context, kind);
  if (picked != null) onResolved(picked.category, picked.issueCode);
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
    final (Color wash, Color ink) = category.tone;

    return Semantics(
      button: true,
      label: category.label,
      excludeSemantics: true,
      child: PressScale(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSizes.radius),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
            child: Column(
              children: <Widget>[
                // One tile in the category's own wash and ink (2026-11-16).
                // Eight identical white squares made the grid a list to read;
                // in colour it is a set to pick from.
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: wash,
                    borderRadius: BorderRadius.circular(AppSizes.radius + 4),
                  ),
                  alignment: Alignment.center,
                  child: Icon(category.icon, size: 26, color: ink),
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
      ),
    );
  }
}
