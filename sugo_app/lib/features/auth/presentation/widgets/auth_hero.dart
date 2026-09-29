import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/widgets/skyline_backdrop.dart';
import '../../../../core/widgets/sugo_logo.dart';
import 'hero_figures.dart';

/// Which illustration the header shows.
enum AuthHeroVariant {
  /// A map pin on the left, the courier with a parcel on the right.
  login,

  /// A home tile, the courier and customer together, then a parcel tile.
  register,
}

/// **Superseded by `AuthHeader` in the 2026-09 redesign, and no longer used.**
///
/// The auth screen now draws a navy gradient header in code. This painted
/// scene - and `hero_figures.dart`, `service_chips.dart` and
/// `skyline_backdrop.dart`, which nothing else references either - is kept
/// only because it is a lot of hand-built artwork and the project has no
/// version control to recover it from. It still compiles and can be dropped
/// back in by rendering `AuthHero` in place of `AuthHeader`.
///
/// Safe to delete outright once nobody wants the old look back.
///
/// Illustrated header above the auth card: the SUGO wordmark and tagline over
/// a city skyline, with the scene for [variant] below it.
///
/// The logo is identical on every screen that uses this widget. To swap the
/// painted scene for real artwork, pass [illustrationAsset].
class AuthHero extends StatelessWidget {
  const AuthHero({
    super.key,
    required this.variant,
    this.illustrationAsset,
    this.assetIncludesLogo = false,
    this.bannerHeight = defaultBannerHeight,
    this.bannerAlignment = defaultBannerAlignment,
    this.leading,
    this.height = AppSizes.authHeroHeight,
  });

  /// How tall the banner is drawn. The supplied artwork is a 2062x763 strip
  /// (2.7:1), so at phone widths showing it whole leaves it only ~144px tall
  /// and its lettering too small to read. Drawing it taller scales the artwork
  /// up - text included - and crops the sides to compensate.
  static const double defaultBannerHeight = 190;

  /// Which part survives the crop. Centred: the artwork carries empty margin
  /// on both sides, so an even trim reaches neither the wordmark on the left
  /// nor the figures on the right. At 190px the crop is ~12% per side, which
  /// stops just short of both. Going taller starts clipping "SUGO".
  static const Alignment defaultBannerAlignment = Alignment.center;

  final AuthHeroVariant variant;
  final String? illustrationAsset;

  /// True when [illustrationAsset] is a full banner that already carries the
  /// wordmark and tagline. The painted logo is then suppressed - otherwise
  /// "SUGO" would appear twice - and the banner sizes itself to its own aspect
  /// ratio so nothing is letterboxed or cropped.
  final bool assetIncludesLogo;

  /// Height of the drawn banner. Fixing it also reserves the space before the
  /// image decodes, so the form does not jump on first paint.
  final double bannerHeight;

  /// Alignment used when the scaled banner is wider than the screen.
  final Alignment bannerAlignment;

  /// Optional control (typically a back button) placed in its own row above
  /// the artwork. The supplied banner is left-aligned, so floating a button
  /// over its top-left corner would land on the wordmark.
  final Widget? leading;

  final double height;

  @override
  Widget build(BuildContext context) {
    final String? asset = illustrationAsset;
    if (asset != null && assetIncludesLogo) return _banner(asset);

    return SizedBox(
      height: height,
      width: double.infinity,
      child: SkylineBackdrop(
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.only(top: AppSizes.sm),
            child: Column(
              children: <Widget>[
                const SugoLogo(fontSize: 34),
                const SizedBox(height: AppSizes.md),
                Expanded(child: _scene()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A banner export is the whole header: full width, its own aspect ratio,
  /// with the backdrop showing only behind the status bar.
  Widget _banner(String asset) {
    return SkylineBackdrop(
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (leading != null)
              Padding(
                padding: const EdgeInsets.only(
                  left: AppSizes.sm,
                  top: AppSizes.xs,
                ),
                child: leading,
              ),
            SizedBox(
              height: bannerHeight,
              width: double.infinity,
              child: Image.asset(
                asset,
                // Cover scales the artwork until it fills the box by height,
                // then clips the extra width per bannerAlignment.
                fit: BoxFit.cover,
                alignment: bannerAlignment,
                errorBuilder:
                    (BuildContext context, Object error, StackTrace? trace) {
                      // Missing or unreadable file: use the painted header.
                      return Column(
                        children: <Widget>[
                          const SugoLogo(fontSize: 34),
                          const SizedBox(height: AppSizes.md),
                          Expanded(child: _PaintedScene(variant: variant)),
                        ],
                      );
                    },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scene() {
    final String? asset = illustrationAsset;
    if (asset != null) {
      return Image.asset(
        asset,
        fit: BoxFit.contain,
        // The artwork is optional, so fall back rather than throwing.
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
          return _PaintedScene(variant: variant);
        },
      );
    }
    return _PaintedScene(variant: variant);
  }
}

class _PaintedScene extends StatelessWidget {
  const _PaintedScene({required this.variant});

  final AuthHeroVariant variant;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Scale the figures to whatever vertical room the header has left, so
        // the scene never overflows on a short device.
        final double figure = constraints.maxHeight.clamp(60.0, 126.0);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.xl),
          child: switch (variant) {
            AuthHeroVariant.login => Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Padding(
                  // Lifts the pin off the baseline, as in the design.
                  padding: EdgeInsets.only(bottom: figure * 0.22),
                  child: MapPinMark(height: figure * 0.52),
                ),
                CourierFigure(height: figure),
              ],
            ),
            AuthHeroVariant.register => Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.only(bottom: figure * 0.34),
                  child: IconTile(
                    icon: Icons.home_rounded,
                    size: figure * 0.38,
                  ),
                ),
                CourierFigure(height: figure * 0.94, carriesParcel: false),
                CustomerFigure(height: figure * 0.94),
                Padding(
                  padding: EdgeInsets.only(bottom: figure * 0.34),
                  child: IconTile(
                    icon: Icons.inventory_2_rounded,
                    size: figure * 0.38,
                  ),
                ),
              ],
            ),
          },
        );
      },
    );
  }
}
