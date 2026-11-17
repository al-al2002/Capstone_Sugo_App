import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../models/delivery_fee.dart';
import '../models/job_enums.dart';
import '../theme/posting_text.dart';

/// "I'll bring it myself" or "Shop pickup/delivery", with the fee beside each
/// and a breakdown that updates the moment the choice changes (2026-11-16).
///
/// Used in two places:
///
/// * the booking dialog, given [distanceKm] to the chosen technician's shop -
///   the exact fee, worked out before the client sends the request;
/// * without a distance, the rule ("₱50 up to 3 km, then ₱15 per km - per
///   trip, 2 trips").
///
/// Pickup and delivery is two trips - collecting the unit and bringing it
/// back - so its fee is twice the trip fee (2026-11-17), and the breakdown
/// says so.
///
/// The fee is always [DeliveryFee.calculate], the one place the app knows
/// the rates. The amount saved on the job is worked out again on the server
/// from the same rule.
class DeliveryOptionSelector extends StatelessWidget {
  const DeliveryOptionSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.distanceKm,
  });

  final DeliveryOption value;
  final ValueChanged<DeliveryOption> onChanged;

  /// Km to the chosen technician's shop, when known.
  final double? distanceKm;

  @override
  Widget build(BuildContext context) {
    final DeliveryFee? fee = distanceKm == null
        ? null
        : DeliveryFee.calculate(distanceKm!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final DeliveryOption option in DeliveryOption.values)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSizes.sm),
            child: _OptionTile(
              option: option,
              selected: option == value,
              price: option == DeliveryOption.self
                  ? '₱0'
                  : fee == null
                  ? 'from ₱${DeliveryFee.minimumTotal}'
                  : '₱${fee.total}',
              onTap: () => onChanged(option),
            ),
          ),
        // The breakdown, swapped with a short cross-fade rather than a jump,
        // so the client sees the number change as they switch.
        AnimatedSwitcher(
          duration: AppMotion.base,
          switchInCurve: AppMotion.standard,
          switchOutCurve: AppMotion.standard,
          child: _FeeBreakdown(
            key: ValueKey<DeliveryOption>(value),
            option: value,
            fee: fee,
          ),
        ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.option,
    required this.selected,
    required this.price,
    required this.onTap,
  });

  final DeliveryOption option;
  final bool selected;
  final String price;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${option.label}, $price',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSizes.tileRadius),
          child: AnimatedContainer(
            duration: AppMotion.base,
            curve: AppMotion.standard,
            constraints: const BoxConstraints(minHeight: AppSizes.touchTarget),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.md,
              vertical: AppSizes.sm + 2,
            ),
            decoration: BoxDecoration(
              color: selected ? AppColors.secondarySoft : AppColors.surface,
              borderRadius: BorderRadius.circular(AppSizes.tileRadius),
              border: Border.all(
                color: selected ? AppColors.secondary : AppColors.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  option.icon,
                  size: 20,
                  color: selected ? AppColors.secondaryDark : AppColors.hint,
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        option.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: selected
                              ? AppColors.primaryDark
                              : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(option.blurb, style: PostingText.caption),
                    ],
                  ),
                ),
                const SizedBox(width: AppSizes.sm),
                Text(
                  price,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: option == DeliveryOption.self
                        ? AppColors.success
                        : AppColors.primaryDark,
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

/// The fee and how it was reached, for the option that is selected.
class _FeeBreakdown extends StatelessWidget {
  const _FeeBreakdown({super.key, required this.option, required this.fee});

  final DeliveryOption option;
  final DeliveryFee? fee;

  @override
  Widget build(BuildContext context) {
    final List<(String, String)> rows = switch (option) {
      DeliveryOption.self => const <(String, String)>[('Delivery fee', '₱0')],
      DeliveryOption.delivery when fee != null => <(String, String)>[
        (
          'Distance to shop',
          '${fee!.distanceKm.toStringAsFixed(1)} km → ${fee!.billedKm} km',
        ),
        ('Rate per trip', fee!.breakdownLabel),
        // The two trips, each its own line (2026-11-17).
        ('Pickup trip', '₱${fee!.oneWay}'),
        ('Delivery trip', '₱${fee!.oneWay}'),
        ('Pickup and delivery fee', '₱${fee!.total}'),
      ],
      DeliveryOption.delivery => const <(String, String)>[
        ('Pickup and delivery fee', DeliveryFee.ruleLabel),
      ],
    };

    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final (String label, String value) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              // Both sides flexible, so a narrow card at large text wraps the
              // words rather than overflowing.
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Flexible(
                    flex: 2,
                    child: Text(label, style: PostingText.caption),
                  ),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    flex: 3,
                    child: Text(
                      value,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: label == 'Delivery fee'
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (option == DeliveryOption.delivery && fee == null)
            const Text(
              'The exact fee is shown when you choose a technician - it '
              'depends on how far their shop is - before you send the '
              'request.',
              style: PostingText.caption,
            ),
          if (option == DeliveryOption.self)
            const Text(
              "You'll see the shop's location once the technician accepts.",
              style: PostingText.caption,
            ),
        ],
      ),
    );
  }
}
