import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../config/service_offers.dart';
import '../models/issue_catalog.dart';
import 'press_scale.dart';

/// "Maintenance" or "Installation" on step 1 of posting (2026-11-16).
///
/// The same two doors as the home screen's category tiles, opening the same
/// sheet. Each card says what is behind it and what it starts at, so a client
/// looking for "aircon cleaning" sees the word "cleaning" and a price before
/// tapping anything.
class ServiceKindCard extends StatelessWidget {
  const ServiceKindCard({super.key, required this.kind, required this.onTap});

  /// Maintenance or installation.
  final IssueKind kind;
  final VoidCallback onTap;

  bool get _isInstall => kind == IssueKind.installation;

  @override
  Widget build(BuildContext context) {
    final String? price = ServiceOffers.startingPrice(kind);
    final Color tint = _isInstall ? AppColors.accentSoft : AppColors.cyanSoft;
    final Color ink = _isInstall ? AppColors.accentDark : AppColors.cyanDark;
    final String title = _isInstall ? 'Installation' : 'Maintenance';
    final String blurb = _isInstall
        ? 'Wi-Fi, CCTV, aircon, TV'
        : 'Tune-ups, aircon cleaning';

    return Semantics(
      button: true,
      label: <String>[title, blurb, ?price].join(', '),
      excludeSemantics: true,
      child: PressScale(
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSizes.tileRadius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppSizes.tileRadius),
                border: Border.all(color: AppColors.border),
              ),
              child: Stack(
                children: <Widget>[
                  // A soft wash of the card's colour in the corner, so the
                  // two read as a pair of distinct doors at a glance.
                  Positioned(
                    right: -26,
                    top: -26,
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppSizes.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: tint,
                            borderRadius: BorderRadius.circular(AppSizes.md),
                          ),
                          child: Icon(
                            _isInstall
                                ? Icons.construction_rounded
                                : Icons.cleaning_services_rounded,
                            size: 19,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: AppSizes.sm),
                        Text(title, style: AppTextStyles.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          blurb,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.micro.copyWith(height: 1.3),
                        ),
                        const SizedBox(height: AppSizes.sm),
                        Row(
                          children: <Widget>[
                            // Expanded, not Flexible + Spacer: those would
                            // split the row in half and clip "From ₱300".
                            Expanded(
                              child: Text(
                                price ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.success,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 18,
                              color: ink,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
