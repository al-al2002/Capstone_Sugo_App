import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_elevation.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_avatar.dart';
import '../../../core/widgets/sugo_brand_cover.dart';
import '../../../core/widgets/sugo_card.dart';

/// A profile's identity panel: a cover, the avatar straddling its lower edge,
/// then the name, an optional line under it, and a row of badges.
///
/// Used for your own profile and for other people's - a client's public
/// profile, and a technician's reached from "More technicians" - so every
/// profile in the app reads the same way.
///
/// ## The redesign (2026-09-29)
///
/// The cover used to be the app icon's emblem, stretched wide - house, wrench,
/// swoosh and van - with the avatar placed dead centre on top of it. The
/// portrait landed on the wrench and half the van, so the two pictures fought
/// and neither read; the panel under it was navy too, which made a light
/// avatar look pasted on. ("Mura mn lain tan-awon.")
///
/// Now the cover is drawn ([SugoBrandCover]): the brand gradient and the
/// dashed route to a van, quiet in the middle where the avatar sits. The panel
/// below is white like every other card, the avatar has a white ring, and the
/// badges are tinted pills ([ProfileBadge]).
///
/// ## Why the avatar overlaps the cover
///
/// An image above a card is a banner. An image with the portrait cut into its
/// bottom edge is a *cover* - the arrangement every social profile uses, so
/// people read it without being told. The overlap is half the avatar.
class ProfileCoverHeader extends StatelessWidget {
  const ProfileCoverHeader({
    super.key,
    required this.name,
    this.avatarUrl,
    this.verified = false,
    this.subtitle,
    this.badges = const <Widget>[],
  });

  final String name;
  final String? avatarUrl;

  /// Shows the verified tick on the avatar.
  final bool verified;

  /// One line under the name - a specialism and a distance, say.
  final String? subtitle;

  /// Small chips under the name - role, tier, ID status.
  final List<Widget> badges;

  /// Height of the cover.
  static const double coverHeight = 128;

  /// The white ring around the avatar, so it reads as cut into the cover.
  static const double _ringWidth = 4;

  static const double _avatarOuter = AppSizes.avatarLg + _ringWidth * 2;

  @override
  Widget build(BuildContext context) {
    return SugoCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          Stack(
            alignment: Alignment.bottomCenter,
            children: <Widget>[
              // The cover reserves room below itself for the lower half of
              // the avatar, so the Stack is exactly as tall as what it paints
              // and nothing overflows into the name.
              Padding(
                padding: const EdgeInsets.only(bottom: _avatarOuter / 2),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppSizes.radius - 1),
                  ),
                  child: const SizedBox(
                    height: coverHeight,
                    width: double.infinity,
                    child: SugoBrandCover(),
                  ),
                ),
              ),
              ProfileAvatar(
                name: name,
                avatarUrl: avatarUrl,
                verified: verified,
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
                  style: AppTextStyles.title,
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption,
                  ),
                ],
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
    );
  }
}

/// The avatar with its white ring, as it sits on a cover.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.name,
    this.avatarUrl,
    this.verified = false,
    this.size = AppSizes.avatarLg,
  });

  final String name;
  final String? avatarUrl;
  final bool verified;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        boxShadow: AppElevation.sm,
      ),
      child: SugoAvatar(
        name: name,
        imageUrl: avatarUrl,
        size: size,
        verified: verified,
      ),
    );
  }
}

/// How a profile badge is tinted.
enum ProfileBadgeTone { brand, accent, success }

/// A badge under a profile's name: a pale wash with the text shade on top,
/// each pair AA on its wash.
class ProfileBadge extends StatelessWidget {
  const ProfileBadge({
    super.key,
    required this.icon,
    required this.label,
    this.tone = ProfileBadgeTone.brand,
  });

  final IconData icon;
  final String label;
  final ProfileBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final (Color wash, Color ink) = switch (tone) {
      ProfileBadgeTone.brand => (AppColors.primarySofter, AppColors.primary),
      ProfileBadgeTone.accent => (AppColors.accentSoft, AppColors.accentDark),
      ProfileBadgeTone.success => (AppColors.successSoft, AppColors.success),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: 5),
      decoration: BoxDecoration(
        color: wash,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: ink),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.micro.copyWith(
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
