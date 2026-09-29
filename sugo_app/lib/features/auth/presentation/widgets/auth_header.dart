import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_assets.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/sugo_logo.dart';

/// The branded header above the login and register forms.
///
/// ## Why it is the icon artwork
///
/// The reference design (2026-09-28) opens on the SUGO lockup - the emblem
/// (since the 2026-09-29 rebrand, a house, wrench and van), the wordmark,
/// "Fix. Technology. Appliances." - large, on navy. That
/// is exactly the content of the app icon, so the header *is* the icon
/// artwork (`AppAssets.brandHeader`, cut by `tool/prepare_brand_images.py`)
/// rather than a second drawing of the same logo that could drift from it.
///
/// ## Why the height is the width
///
/// The artwork is square and fills the width, so [heightFor] makes the header
/// square too and nothing is cropped. That matters at both ends: the icon has
/// about 13% of navy above the roof, which is exactly the room the status bar
/// needs, and about 14% below the tagline, which the sheet's [sheetOverlap]
/// rides into without touching the words. An earlier 92% crop took both
/// margins and put the status bar across the top of the logo.
///
/// Clamped, so a tablet does not give the logo half the page; past 420 the
/// crop is shared top and bottom and both margins are still larger than what
/// they have to clear.
class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, required this.height});

  final double height;

  /// How far the white sheet rides up over the header's bottom edge.
  static const double sheetOverlap = 28;

  /// Header height for a given content width: square, within limits.
  static double heightFor(double width) => width.clamp(280.0, 420.0);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: '${AppStrings.appName}. ${AppStrings.tagline}',
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: AppColors.heroGradient),
          child: Image.asset(
            AppAssets.brandHeader,
            fit: BoxFit.cover,
            excludeFromSemantics: true,
            // Never an empty header. This returned nothing at first, and on
            // 2026-09-28 the running app's asset bundle simply did not have
            // the file - it was added while `flutter run` was up, and a hot
            // restart does not pick up new asset files - so the login screen
            // showed a bare navy block. The logo drawn in code stands in.
            errorBuilder:
                (BuildContext context, Object error, StackTrace? stackTrace) {
                  if (kDebugMode) {
                    debugPrint(
                      'AuthHeader: ${AppAssets.brandHeader} did not load '
                      '($error). If the file exists, stop the app and '
                      '`flutter run` again - new asset files are not '
                      'picked up by hot reload or hot restart.',
                    );
                  }
                  return const _DrawnLockup();
                },
          ),
        ),
      ),
    );
  }
}

/// The lockup drawn in code - mark, wordmark, tagline - for when the artwork
/// cannot be shown. Centred in the space below the status bar, so it sits
/// where the artwork's logo would have been.
class _DrawnLockup extends StatelessWidget {
  const _DrawnLockup();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        // Clear of the sheet that rides up over the bottom edge.
        padding: const EdgeInsets.only(bottom: AuthHeader.sheetOverlap),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const <Widget>[
                SugoLogoMark(size: 72, onDark: true),
                SizedBox(height: 18),
                SugoLogo(fontSize: 44, onDark: true),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
