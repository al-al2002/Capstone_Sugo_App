import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../models/trust_badge.dart';

/// One rung of the Progressive Trust Badge as a tinted pill.
///
/// The same component on the match card, the technician's profile and their
/// own progress card, so a client learns what "Skill verified" looks like
/// once. Colour is never the only signal: every rung has its own icon and
/// its name in words.
class TrustBadgePill extends StatelessWidget {
  const TrustBadgePill({super.key, required this.badge, this.compact = false});

  final TrustBadge badge;

  /// Smaller, for a dense row such as the match card.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (Color wash, Color ink) = badge.colors;

    return Semantics(
      label: 'Trust badge: ${badge.label}',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : AppSizes.sm,
          vertical: compact ? 2 : AppSizes.xs,
        ),
        decoration: BoxDecoration(
          color: wash,
          borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(badge.icon, size: compact ? 13 : 15, color: ink),
            SizedBox(width: compact ? 3 : AppSizes.xs),
            Flexible(
              child: Text(
                badge.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
