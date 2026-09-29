import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../theme/app_motion.dart';
import '../theme/app_text_styles.dart';
import 'sugo_card.dart';

/// A single headline figure with a label and a tinted glyph.
///
/// Both dashboards and both profiles lead with a row of these, which is the
/// point: before the renovation each screen built its own summary strip, so a
/// technician's "Jobs done" and a client's "Bookings" were the same idea drawn
/// two different ways. One widget means one answer to what a number looks like.
///
/// ## Why the number counts up
///
/// The value animates from zero on first build over [AppMotion.slow]. This is
/// not decoration. A dashboard's figures are the reason the screen exists, and
/// a number that resolves draws the eye to itself at the moment the screen
/// settles - which is exactly where the eye should go. It also covers the gap
/// between the screen painting and the data arriving, so the tile never snaps
/// from a placeholder to a real value.
///
/// Counting is suppressed for values that are not counts - a rating like 4.8
/// or a peso total - where rolling digits read as a slot machine rather than
/// as data. Pass `animate: false` for those.
class SugoStatTile extends StatelessWidget {
  const SugoStatTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.tint = AppColors.primarySoft,
    this.foreground = AppColors.primary,
    this.onTap,
    this.animate = true,
    this.numericValue,
    this.trailing,
  });

  final IconData icon;

  /// What to print. When [animate] is on, supply [numericValue] too so the
  /// tile knows what it is counting towards.
  final String value;

  final String label;
  final Color tint;
  final Color foreground;
  final VoidCallback? onTap;

  /// Count the figure up on first build.
  final bool animate;

  /// The number behind [value], for the count-up. When null the tile prints
  /// [value] unchanged.
  final num? numericValue;

  /// Optional trend chip or hint under the label.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SugoCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSizes.md + 2),
      radius: AppSizes.tileRadius,
      elevation: SugoElevation.sm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(AppSizes.radius),
            ),
            child: Icon(icon, size: 18, color: foreground),
          ),
          const SizedBox(height: AppSizes.md),
          _Figure(
            value: value,
            numericValue: numericValue,
            animate: animate,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.statLabel,
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(height: AppSizes.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.value,
    required this.numericValue,
    required this.animate,
  });

  final String value;
  final num? numericValue;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final num? target = numericValue;

    if (!animate || target == null) {
      return Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.stat,
      );
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target.toDouble()),
      duration: AppMotion.slow,
      // Decelerating, so the count is quick at the start and eases onto the
      // final figure. A linear count arrives with a jolt.
      curve: AppMotion.standard,
      builder: (BuildContext context, double current, Widget? _) {
        return Text(
          current.round().toString(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.stat,
        );
      },
    );
  }
}

/// A row of [SugoStatTile]s that share their width evenly.
///
/// Exists so callers stop writing `Expanded(child: ...)` three times with a
/// hand-picked gap between them, which is how the two dashboards drifted apart
/// in the first place.
class SugoStatRow extends StatelessWidget {
  const SugoStatRow({super.key, required this.tiles, this.gap = AppSizes.md});

  final List<Widget> tiles;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < tiles.length; i++) ...<Widget>[
            if (i > 0) SizedBox(width: gap),
            Expanded(child: tiles[i]),
          ],
        ],
      ),
    );
  }
}
