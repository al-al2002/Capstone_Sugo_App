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
  const AuthHeader({
    super.key,
    required this.height,
    this.register,
    this.onBack,
  });

  final double height;
  final bool? register;
  final VoidCallback? onBack;

  /// How far the white sheet rides up over the header's bottom edge.
  static const double sheetOverlap = 28;

  /// Header height for a given content width: square, within limits.
  static double heightFor(double width, {required bool register}) =>
      register ? width * 0.72 : width * 643 / 887;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: '${AppStrings.appName}. ${AppStrings.tagline}',
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const ColoredBox(color: AppColors.navy),
            Image.asset(
              register == null
                  ? AppAssets.brandHeader
                  : register!
                  ? AppAssets.registerHeader
                  : AppAssets.loginHeader,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
              errorBuilder:
                  (BuildContext context, Object error, StackTrace? stackTrace) {
                    if (kDebugMode) {
                      debugPrint(
                        'AuthHeader: failed to load the header image ($error)',
                      );
                    }
                    return const _DrawnLockup();
                  },
            ),
            if (register == true)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 8,
                left: 12,
                child: IconButton(
                  onPressed: onBack,
                  color: Colors.white,
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: 'Back to login',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DrawnLockup extends StatelessWidget {
  const _DrawnLockup();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
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
    );
  }
}
