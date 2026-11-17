import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';

/// A round icon button in frosted glass, for the navy headers (2026-11-16).
///
/// The home headers moved onto the illustrated navy cover, where the hairline
/// white [SugoIconButton] read as a sticker. This is the same 40px disc with a
/// 48dp touch target, in translucent white, carrying the same unread count.
class SugoGlassIconButton extends StatelessWidget {
  const SugoGlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  /// Unread items. Zero shows no badge; above nine shows "9+".
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: badgeCount > 0 ? '$tooltip, $badgeCount unread' : tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: SizedBox(
          width: AppSizes.touchTarget,
          height: AppSizes.touchTarget,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onPressed,
              customBorder: const CircleBorder(),
              child: Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Icon(icon, size: 19, color: Colors.white),
                    ),
                    if (badgeCount > 0)
                      Positioned(
                        top: -3,
                        right: -3,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 18),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(
                              AppSizes.pillRadius,
                            ),
                            border: Border.all(
                              color: AppColors.navy,
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            badgeCount > 9 ? '9+' : '$badgeCount',
                            textAlign: TextAlign.center,
                            // Ink on the orange: white on it is 2.1:1.
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppColors.onAccent,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
