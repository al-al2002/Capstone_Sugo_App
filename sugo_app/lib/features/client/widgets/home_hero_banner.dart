import 'package:flutter/material.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';

/// "Need a tech fix?" - the home screen's invitation when no booking is under
/// way: a heading, one line, a Book now button, and a technician on the right.
///
/// ## Where the technician comes from
///
/// He is the one from the splash illustration, cropped by
/// `tool/prepare_brand_images.py` (`AppAssets.bannerTechnician`), not a new
/// drawing - so the person a client sees on launch is the person on this card.
///
/// The crop is square and the card is wide, so he sits on the right and the
/// card's navy washes over his left side with a gradient. That fade is what
/// lets the heading sit on a flat colour, readable, while the picture still
/// runs to the card's edge.
///
/// ## In the Dispatch design (2026-09-29)
///
/// This is the one navy surface on the home screen, so it keeps its colour
/// and its illustration. It lost its shadow and its pill-shaped blue button:
/// flat, the page corner, and a white button with navy words - the brightest
/// thing on the card, which is the point. The button draws 40 tall and
/// answers taps across 48.
class HomeHeroBanner extends StatelessWidget {
  const HomeHeroBanner({super.key, required this.onBookNow});

  final VoidCallback onBookNow;

  /// The card's height at normal text size. A minimum, not a fixed height:
  /// at 1.3x text the heading and line need more, and the card grows rather
  /// than cutting the button off.
  static const double _height = 164;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: _height),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppSizes.radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: _height * 1.25,
            child: Image.asset(
              AppAssets.bannerTechnician,
              fit: BoxFit.cover,
              alignment: const Alignment(0.2, -0.3),
              excludeFromSemantics: true,
              errorBuilder: (BuildContext _, Object _, StackTrace? _) =>
                  const SizedBox.shrink(),
            ),
          ),
          // Navy over the left of the picture, fading out towards him.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    AppColors.primary,
                    AppColors.primary,
                    Color(0x00062B5C),
                  ],
                  stops: <double>[0, 0.42, 0.72],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSizes.lg + 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Need a tech fix?',
                  style: AppTextStyles.title.copyWith(color: Colors.white),
                ),
                const SizedBox(height: AppSizes.xs + 2),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 176),
                  child: Text(
                    'Trusted technicians near you are ready to help.',
                    style: AppTextStyles.caption.copyWith(
                      color: Colors.white.withValues(alpha: 0.88),
                    ),
                  ),
                ),
                const SizedBox(height: AppSizes.md),
                FilledButton(
                  onPressed: onBookNow,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primary,
                    minimumSize: const Size(0, AppSizes.compactButtonHeight),
                    // Pads the tap area to 48dp around the 40dp button.
                    tapTargetSize: MaterialTapTargetSize.padded,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSizes.lg + 2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSizes.radius),
                    ),
                    // Names the family: a button's textStyle replaces the
                    // inherited one, and this label used to fall back to
                    // the phone's own font.
                    textStyle: AppTextStyles.button.copyWith(fontSize: 13),
                  ),
                  child: const Text('Book now'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
