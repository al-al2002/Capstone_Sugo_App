import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_sheet.dart';
import '../../rb_cars/models/job_enums.dart';
import '../../rb_cars/widgets/service_path_card.dart';

/// "Still not fixed? Find a technician" (2026-11-16).
///
/// On the client's own community post. The tips did not work, so the same
/// request becomes a Home Service or Shop Repair booking - device, problem,
/// location and photos carried over, nothing retyped. A Shop Repair asks
/// "bring it myself or pickup/delivery" when they choose a technician, with
/// the fee, so this sheet only asks which service.
class FindTechnicianButton extends StatelessWidget {
  const FindTechnicianButton({
    super.key,
    required this.onChooseService,
    this.converting = false,
  });

  final Future<void> Function(ServicePath path) onChooseService;
  final bool converting;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSizes.buttonHeight,
      child: ElevatedButton.icon(
        onPressed: converting ? null : () => _choose(context),
        icon: converting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.handyman_rounded, size: 18),
        label: Text(
          converting
              ? 'Finding technicians…'
              : 'Still not fixed? Find a technician',
        ),
      ),
    );
  }

  Future<void> _choose(BuildContext context) async {
    final ServicePath? path = await showSugoBottomSheet<ServicePath>(
      context: context,
      title: 'Find a technician',
      subtitle: 'Your post becomes a booking. Nothing to retype.',
      builder: (BuildContext sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final ServicePath option in const <ServicePath>[
            ServicePath.homeService,
            ServicePath.pickup,
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.sm),
              child: _ServiceTile(
                path: option,
                onTap: () => Navigator.of(sheetContext).pop(option),
              ),
            ),
        ],
      ),
    );
    if (path != null) await onChooseService(path);
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.path, required this.onTap});

  final ServicePath path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSizes.tileRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSizes.touchTarget),
          padding: const EdgeInsets.all(AppSizes.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSizes.tileRadius),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: <Widget>[
              Icon(path.icon, color: AppColors.secondaryDark),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      ServicePathSuggestion.titleFor(path),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ServicePathSuggestion.blurbFor(path),
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.hint),
            ],
          ),
        ),
      ),
    );
  }
}
