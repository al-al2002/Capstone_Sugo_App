import 'package:flutter/material.dart';

import '../../../../core/constants/app_assets.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_motion.dart';

/// The splash poster, edge to edge.
///
/// ## The 2026-09-29 poster
///
/// `splash 2.png` replaced the paper-plane illustration: the new lockup, "From
/// your home to our shop", the two service paths, and the technician between
/// a house and the SUGO shop and van. The app shows `AppAssets.splash`, the
/// copy of it that `tool/prepare_brand_images.py` makes with the drawn "Get
/// Started" button painted out - the splash screen draws a real one in that
/// space once loading has finished.
///
/// The previous splash animated its illustration region by region from
/// coordinates measured off that one file. None of those measurements fit the
/// new poster, and a poster that *is* the brand statement reads best whole,
/// so it now simply arrives: a short fade and a settle from 3% larger. The
/// motion on this screen is the loading animation, which carries information.
///
/// Scaled to cover and centred. On a tall phone the height decides the scale
/// and a little of each side is cropped - the content sits well inside the
/// middle 80% of the poster's width, so nothing written is lost.
class SplashArtwork extends StatelessWidget {
  const SplashArtwork({super.key});

  @override
  Widget build(BuildContext context) {
    final bool still = AppMotion.reduced(context);

    return DecoratedBox(
      // What shows for the instant before the image decodes, and for good if
      // the file is missing: the poster's own navy, so the screen is never a
      // white flash or a blank.
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[AppColors.primary, AppColors.navyLift],
        ),
      ),
      child: SizedBox.expand(
        child: Image.asset(
          AppAssets.splash,
          fit: BoxFit.cover,
          excludeFromSemantics: true,
          errorBuilder: (BuildContext _, Object _, StackTrace? _) =>
              const SizedBox.shrink(),
          frameBuilder:
              (
                BuildContext context,
                Widget child,
                int? frame,
                bool synchronous,
              ) {
                if (synchronous || still) return child;
                final bool shown = frame != null;
                return AnimatedOpacity(
                  opacity: shown ? 1 : 0,
                  duration: AppMotion.page,
                  curve: AppMotion.standard,
                  child: AnimatedScale(
                    scale: shown ? 1 : 1.03,
                    duration: AppMotion.page * 2,
                    curve: AppMotion.emphasized,
                    child: child,
                  ),
                );
              },
        ),
      ),
    );
  }
}
