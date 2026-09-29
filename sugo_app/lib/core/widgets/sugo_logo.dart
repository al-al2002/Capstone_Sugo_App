import 'package:flutter/material.dart';

import '../constants/app_assets.dart';
import '../constants/app_colors.dart';
import '../constants/app_strings.dart';
import '../theme/app_text_styles.dart';

/// The SUGO wordmark: heavy lettering with the orange stroke across the "O",
/// optionally over the tagline.
///
/// ## The 2026-09-29 brand
///
/// The wordmark used to carry a small paper plane beside it. The client
/// retired the plane - it read as Telegram's logo - for the house, wrench and
/// van emblem ([SugoLogoMark]). What stayed from the old lockup is the orange
/// stroke on the "O", which the new artwork keeps too; it is painted here
/// rather than borrowed from an icon font, so it sits where the artwork puts
/// it. [onDark] flips the lettering to white for navy surfaces.
class SugoLogo extends StatelessWidget {
  const SugoLogo({
    super.key,
    this.fontSize = 34,
    this.showTagline = true,
    this.onDark = false,
  });

  final double fontSize;
  final bool showTagline;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final Color ink = onDark ? Colors.white : AppColors.primary;

    return Semantics(
      label: showTagline
          ? '${AppStrings.appName}. ${AppStrings.tagline}'
          : AppStrings.appName,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Text(
                AppStrings.appName,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w800,
                  color: ink,
                  letterSpacing: fontSize * 0.02,
                  height: 1,
                ),
              ),
              // The stroke cuts into the "O" from its top right, as on the
              // icon. Sized and placed in fractions of the font size so it
              // lands on the letter at any size.
              Positioned(
                right: -fontSize * 0.04,
                top: -fontSize * 0.06,
                child: CustomPaint(
                  size: Size(fontSize * 0.34, fontSize * 0.5),
                  painter: const _Stroke(),
                ),
              ),
            ],
          ),
          if (showTagline) ...<Widget>[
            SizedBox(height: fontSize * 0.22),
            Text(
              AppStrings.tagline,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: (fontSize * 0.36).clamp(12, 18),
                fontWeight: FontWeight.w600,
                color: onDark
                    ? Colors.white.withValues(alpha: 0.82)
                    : AppColors.textSecondary,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The orange stroke: a wedge, broad at the top right, narrowing to a point
/// towards the centre of the "O".
class _Stroke extends CustomPainter {
  const _Stroke();

  @override
  void paint(Canvas canvas, Size size) {
    final Path wedge = Path()
      ..moveTo(size.width * 0.52, 0)
      ..lineTo(size.width, size.height * 0.16)
      ..lineTo(size.width * 0.12, size.height)
      ..close();
    canvas.drawPath(wedge, Paint()..color = AppColors.accent);
  }

  @override
  bool shouldRepaint(covariant _Stroke oldDelegate) => false;
}

/// The compact brand mark: the emblem - a house with a wrench, a swoosh and a
/// service van - on its navy tile.
///
/// For places the full wordmark does not fit: the top of the home screen, the
/// auth header's fallback. The artwork is the app icon's own emblem
/// ([AppAssets.brandEmblem]), so the mark in the app is the icon on the
/// phone's home screen.
///
/// If the file is missing the tile still draws, with a house-and-wrench glyph
/// in place of the artwork - a missing export never breaks a screen.
class SugoLogoMark extends StatelessWidget {
  const SugoLogoMark({super.key, this.size = 40, this.onDark = false});

  final double size;

  /// On a navy background the tile gets a faint light edge, so the navy mark
  /// does not disappear into the navy ground.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final BorderRadius corners = BorderRadius.circular(size * 0.28);

    return Semantics(
      label: AppStrings.appName,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.navy,
          borderRadius: corners,
          border: onDark
              ? Border.all(color: Colors.white.withValues(alpha: 0.28))
              : null,
        ),
        child: ClipRRect(
          borderRadius: corners,
          // Zoomed a little past the tile's edge: the export leaves air round
          // the swoosh, which makes the emblem read thin at 32px.
          child: Transform.scale(
            scale: 1.15,
            child: Image.asset(
              AppAssets.brandEmblem,
              fit: BoxFit.cover,
              width: size,
              height: size,
              errorBuilder: (BuildContext _, Object _, StackTrace? _) => Icon(
                Icons.home_repair_service_rounded,
                size: size * 0.56,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
