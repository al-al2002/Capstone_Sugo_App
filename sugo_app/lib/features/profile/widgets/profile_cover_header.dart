import 'package:flutter/material.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_avatar.dart';
import '../../../core/widgets/sugo_card.dart';

/// A profile's identity panel: a cover photo, the avatar straddling its lower
/// edge, then the name and a row of badges.
///
/// ## Why the avatar overlaps the cover
///
/// An image above a card is a banner. An image with the portrait cut into its
/// bottom edge is a *cover* - the arrangement every social profile uses, so
/// people read it without being told. The overlap is half the avatar.
///
/// ## The cover image
///
/// The emblem from the app icon ([AppAssets.profileCover]), the same for
/// every account; there is no per-user cover upload. Below the cover the
/// panel keeps the brand gradient the old header had, so the name and badges
/// are still white on navy - and if the image is ever missing, that gradient
/// is simply what shows.
class ProfileCoverHeader extends StatelessWidget {
  const ProfileCoverHeader({
    super.key,
    required this.name,
    this.avatarUrl,
    this.verified = false,
    this.badges = const <Widget>[],
  });

  final String name;
  final String? avatarUrl;

  /// Shows the verified tick on the avatar.
  final bool verified;

  /// Small chips under the name - role, tier, ID status.
  final List<Widget> badges;

  /// Width to height of the cover. Near the asset's own 2.13, so on a phone
  /// almost none of the emblem is cropped away.
  static const double coverAspectRatio = 2.2;

  /// The navy ring around the avatar. The same colour as the panel, so the
  /// portrait looks cut into the cover rather than stuck on top of it.
  static const double _ringWidth = 4;

  static const double _avatarOuter = AppSizes.avatarLg + _ringWidth * 2;

  @override
  Widget build(BuildContext context) {
    return SugoCard(
      padding: EdgeInsets.zero,
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[AppColors.primary, AppColors.navy],
      ),
      elevation: SugoElevation.lg,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSizes.panelRadius),
        child: Column(
          children: <Widget>[
            Stack(
              alignment: Alignment.bottomCenter,
              children: <Widget>[
                // The cover reserves room below itself for the lower half of
                // the avatar, so the Stack is exactly as tall as what it
                // paints and nothing overflows into the name.
                const Padding(
                  padding: EdgeInsets.only(bottom: _avatarOuter / 2),
                  child: AspectRatio(
                    aspectRatio: coverAspectRatio,
                    child: _Cover(),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(_ringWidth),
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: SugoAvatar(
                    name: name,
                    imageUrl: avatarUrl,
                    size: AppSizes.avatarLg,
                    verified: verified,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSizes.xl,
                AppSizes.md,
                AppSizes.xl,
                AppSizes.xl,
              ),
              child: Column(
                children: <Widget>[
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.display.copyWith(
                      color: Colors.white,
                      fontSize: 20,
                    ),
                  ),
                  if (badges.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSizes.sm),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: AppSizes.sm,
                      runSpacing: AppSizes.xs,
                      children: badges,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      AppAssets.profileCover,
      fit: BoxFit.cover,
      // Decoration: a screen reader has nothing to gain from "image".
      excludeFromSemantics: true,
      // A missing file leaves the panel's gradient showing - the header as
      // it looked before it had a cover - rather than an error box.
      errorBuilder: (BuildContext _, Object _, StackTrace? _) =>
          const SizedBox.shrink(),
    );
  }
}
