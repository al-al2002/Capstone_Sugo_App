import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/specialization_catalog.dart';

/// Device -> brand multi-select, across both categories at once.
///
/// ## Why both categories are on one page
///
/// They used to sit behind tabs. The selections persisted across a tab switch,
/// but nothing on screen said so - pick an aircon, switch to IT devices, and
/// your appliance work simply vanished from view. The control read as "choose
/// a category", when a technician who repairs both laptops and refrigerators
/// is completely ordinary.
///
/// Now both sections are on one scrolling page with a running count in each
/// header, so picking from both is the obvious thing to do rather than a
/// hidden capability.
///
/// ## Why brands are a drill-down
///
/// The full cross product is ten devices times seven brands - seventy chips at
/// once, most irrelevant to any given technician. Expanding a device to reveal
/// its brands keeps the page to ten rows until the user shows interest, and it
/// makes the result self-explanatory: brands sit visibly *under* the device
/// they belong to, which is exactly what a `(device_type, brand)` row means.
///
/// Each selected brand becomes one [TechnicianSpecialization], and the parent
/// owns the list - this widget only reports changes.
class SpecializationPicker extends StatefulWidget {
  const SpecializationPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  /// Currently chosen device + brand pairs, saved or not.
  final List<TechnicianSpecialization> selected;

  final ValueChanged<List<TechnicianSpecialization>> onChanged;

  @override
  State<SpecializationPicker> createState() => _SpecializationPickerState();
}

class _SpecializationPickerState extends State<SpecializationPicker> {
  /// Which device rows are open. Several may be open at once - a technician
  /// who does laptops and desktops wants to compare the two brand lists
  /// without one collapsing the other.
  final Set<String> _expanded = <String>{};

  bool _isSelected(DeviceType device, String brand) {
    return widget.selected.any(
      (TechnicianSpecialization s) =>
          s.deviceType == device.wire && s.brand == brand,
    );
  }

  /// Brands chosen for a device, whether or not the row is expanded.
  List<TechnicianSpecialization> _forDevice(DeviceType device) {
    return widget.selected
        .where((TechnicianSpecialization s) => s.deviceType == device.wire)
        .toList(growable: false);
  }

  void _toggle(DeviceType device, String brand) {
    final List<TechnicianSpecialization> next =
        List<TechnicianSpecialization>.from(widget.selected);

    final int index = next.indexWhere(
      (TechnicianSpecialization s) =>
          s.deviceType == device.wire && s.brand == brand,
    );

    if (index >= 0) {
      // Verified rows are removable too, since 20260907000009. Passing a track
      // verifies every brand in it at once, so locking them would mean a single
      // quiz could permanently freeze a brand added by mistake. The attempt
      // history is keyed on the track and survives the deletion.
      next.removeAt(index);
    } else {
      next.add(
        TechnicianSpecialization(
          category: device.category,
          deviceType: device.wire,
          brand: brand,
        ),
      );
    }

    widget.onChanged(next);
  }

  /// Prompts for a brand the catalogue does not list.
  ///
  /// This is why `brand` is free text with no foreign key - a technician who
  /// services a brand SUGO has never heard of is still a technician SUGO wants.
  Future<void> _addOtherBrand(DeviceType device) async {
    final TextEditingController controller = TextEditingController();

    final String? brand = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('Add a brand for ${device.label}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Brand name'),
          onSubmitted: (String v) => Navigator.of(dialogContext).pop(v.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (brand == null || brand.isEmpty) return;
    if (_isSelected(device, brand)) return; // Already chosen; nothing to do.

    _toggle(device, brand);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('What do you repair?', style: AppTextStyles.headline),
        const SizedBox(height: AppSizes.sm),
        const Text(
          'Pick every device you work on, then the brands you know best. '
          'You can choose from both groups — most technicians do.',
          style: AppTextStyles.subtitle,
        ),
        const SizedBox(height: AppSizes.xl),

        // Both categories, one after the other. No tabs: a technician who
        // repairs laptops and refrigerators should not have to discover that
        // picking from both was allowed all along.
        for (final ServiceCategory category
            in ServiceCategory.values) ...<Widget>[
          _sectionHeader(category),
          const SizedBox(height: AppSizes.md),
          ...category.deviceTypes.map(_deviceRow),
          const SizedBox(height: AppSizes.lg),
        ],

        if (widget.selected.isNotEmpty) _summary(),
      ],
    );
  }

  /// Section heading with a live count, so selections in the section you are
  /// not looking at stay visible.
  Widget _sectionHeader(ServiceCategory category) {
    final int count = widget.selected
        .where((TechnicianSpecialization s) => s.category == category)
        .length;

    return Row(
      children: <Widget>[
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: count > 0 ? AppColors.primary : AppColors.primarySoft,
            borderRadius: BorderRadius.circular(AppSizes.sm),
          ),
          child: Icon(
            category.icon,
            size: 16,
            color: count > 0 ? Colors.white : AppColors.primary,
          ),
        ),
        const SizedBox(width: AppSizes.md),
        Text(
          category.label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const Spacer(),
        if (count > 0)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.md,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(AppSizes.pillRadius),
            ),
            child: Text(
              '$count selected',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
      ],
    );
  }

  Widget _deviceRow(DeviceType device) {
    final List<TechnicianSpecialization> chosen = _forDevice(device);
    final bool isOpen = _expanded.contains(device.wire);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(
          color: chosen.isEmpty ? AppColors.border : AppColors.primary,
          width: chosen.isEmpty ? 1 : 1.4,
        ),
      ),
      child: Column(
        children: <Widget>[
          InkWell(
            onTap: () => setState(() {
              if (isOpen) {
                _expanded.remove(device.wire);
              } else {
                _expanded.add(device.wire);
              }
            }),
            borderRadius: BorderRadius.circular(AppSizes.tileRadius),
            child: Padding(
              padding: const EdgeInsets.all(AppSizes.md),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: chosen.isEmpty
                          ? AppColors.primarySofter
                          : AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(AppSizes.sm),
                    ),
                    child: Icon(
                      device.icon,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          device.label,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          chosen.isEmpty
                              ? 'No brands selected'
                              : '${chosen.length} brand'
                                    '${chosen.length == 1 ? '' : 's'} selected',
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isOpen
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),

          if (isOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSizes.md,
                0,
                AppSizes.md,
                AppSizes.md,
              ),
              child: Wrap(
                spacing: AppSizes.sm,
                runSpacing: AppSizes.sm,
                children: <Widget>[
                  ...device.brands.map(
                    (String brand) => _brandChip(device, brand),
                  ),

                  // Brands the technician added themselves, which are not in
                  // the catalogue and would otherwise vanish from the list
                  // while staying selected.
                  ...chosen
                      .map((TechnicianSpecialization s) => s.brand)
                      .where((String b) => !device.brands.contains(b))
                      .map((String brand) => _brandChip(device, brand)),

                  _otherChip(device),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _brandChip(DeviceType device, String brand) {
    final bool selected = _isSelected(device, brand);

    // A verified brand keeps its tick, but stays tappable: it can be removed
    // like any other. See the note in `_toggle`.
    final bool isVerified = widget.selected.any(
      (TechnicianSpecialization s) =>
          s.deviceType == device.wire && s.brand == brand && s.verified,
    );

    return InkWell(
      onTap: () => _toggle(device, brand),
      borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.md,
          vertical: AppSizes.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSizes.pillRadius),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (isVerified)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.verified_rounded,
                  size: 13,
                  color: AppColors.success,
                ),
              )
            else if (selected)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.check_rounded,
                  size: 13,
                  color: AppColors.primary,
                ),
              ),
            Text(
              brand,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _otherChip(DeviceType device) {
    return InkWell(
      onTap: () => _addOtherBrand(device),
      borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.md,
          vertical: AppSizes.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.accentSofter,
          borderRadius: BorderRadius.circular(AppSizes.pillRadius),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.add_rounded, size: 16, color: AppColors.accentDark),
            SizedBox(width: 4),
            Text(
              SpecializationCatalog.othersBrand,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                // The text orange: the bright one is 2.1:1 on its wash.
                color: AppColors.accentDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Running total, so the count is visible without scrolling back up.
  ///
  /// It doubles as an expectation-setter for the next step: each of these is
  /// one assessment to sit, and seeing "12 selected" before the assessment
  /// list appears is much better than discovering it there.
  Widget _summary() {
    final int count = widget.selected.length;

    // What they will actually sit. Devices that share a track share one quiz,
    // so this is usually far smaller than the specialisation count - and
    // saying so here sets the expectation before the assessment step.
    final int trackCount = widget.selected
        .map((TechnicianSpecialization s) => s.track)
        .whereType<AssessmentTrack>()
        .toSet()
        .length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.primarySofter,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.quiz_outlined, size: 17, color: AppColors.primary),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              '$count specialisation${count == 1 ? '' : 's'} selected, '
              'covered by $trackCount '
              '${trackCount == 1 ? 'assessment' : 'assessments'}. '
              'Tap a selected brand again to remove it.',
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
