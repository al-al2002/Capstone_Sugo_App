import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../models/device_category.dart';
import 'device_glyph.dart';
import '../../../core/constants/app_colors.dart';

/// The five device cards.
///
/// Laid out by hand rather than with `GridView.count`, because five items in
/// a two-column grid leave a hole: the grid parks the last card in the left
/// column and the empty cell beside it reads as a card that failed to load.
/// Measuring the column width here lets the odd card sit centred on its own
/// row, which reads as the deliberate end of a list.
class DeviceTypeGrid extends StatelessWidget {
  const DeviceTypeGrid({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final DeviceCategory? selected;
  final ValueChanged<DeviceCategory> onSelect;

  static const double _gap = AppSizes.md;

  /// Tall enough for the glyph, a two-line label, and air around both.
  static const double _cardHeight = 104;

  @override
  Widget build(BuildContext context) {
    const List<DeviceCategory> cards = DeviceCategory.values;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double cell = (constraints.maxWidth - _gap) / 2;
        final List<Widget> rows = <Widget>[];

        for (int i = 0; i < cards.length; i += 2) {
          if (i > 0) rows.add(const SizedBox(height: _gap));
          final bool alone = i + 1 >= cards.length;

          rows.add(
            Row(
              mainAxisAlignment: alone
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: cell,
                  height: _cardHeight,
                  child: _DeviceCard(
                    category: cards[i],
                    selected: cards[i] == selected,
                    onTap: () => onSelect(cards[i]),
                  ),
                ),
                if (!alone) ...<Widget>[
                  const SizedBox(width: _gap),
                  SizedBox(
                    width: cell,
                    height: _cardHeight,
                    child: _DeviceCard(
                      category: cards[i + 1],
                      selected: cards[i + 1] == selected,
                      onTap: () => onSelect(cards[i + 1]),
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        return Column(children: rows);
      },
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final DeviceCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: category.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSizes.tileRadius),
          splashColor: AppColors.primary.withValues(alpha: 0.06),
          highlightColor: Colors.transparent,
          child: AnimatedContainer(
            duration: AppMotion.base,
            curve: AppMotion.standard,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.sm,
              vertical: AppSizes.md,
            ),
            decoration: BoxDecoration(
              color: selected ? AppColors.primarySofter : AppColors.surface,
              borderRadius: BorderRadius.circular(AppSizes.tileRadius),
              // Selection is SUGO blue - the colour that points - at 2px,
              // on a tint. Since the Dispatch redesign no card lifts on a
              // shadow; a doubled border in a different colour is read as
              // quickly as depth was, and does not blur on a cheap screen.
              border: Border.all(
                color: selected ? AppColors.secondary : AppColors.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Stack(
              children: <Widget>[
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    DeviceGlyph(category: category, selected: selected),
                    const SizedBox(height: AppSizes.sm),
                    Text(
                      category.label,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.25,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: selected
                            ? AppColors.primaryDark
                            : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                // The tick. Scales in on [AppMotion.playful] - a small,
                // once-per-step reward, which is exactly the budget that curve
                // is reserved for.
                Positioned(
                  top: 0,
                  right: 0,
                  child: AnimatedScale(
                    scale: selected ? 1 : 0,
                    duration: AppMotion.base,
                    curve: AppMotion.playful,
                    child: const Icon(
                      Icons.check_circle_rounded,
                      size: 17,
                      color: AppColors.primary,
                    ),
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
