import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_elevation.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_avatar.dart';
import '../../../core/widgets/sugo_brand_cover.dart';
import '../../../core/widgets/sugo_card.dart';

/// A profile's identity panel: an illustrated cover, the avatar cut into its
/// lower edge, the name, an optional line, badges and - when given - a strip
/// of figures.
///
/// Used for your own profile and for other people's (a client's public
/// profile, a technician's), so every profile in the app reads the same way.
///
/// ## The 2026-11-16 renovation
///
/// At the user's request ("that image profile look awful"). What changed:
///
/// * **The cover is a scene**, not a gradient with a stray van: Davao's
///   skyline, Mount Apo and the dashed booking route, in the style of SUGO's
///   other artwork ([SugoBrandCover]). Daylight for a client, dusk with lit
///   windows for a technician ([style]).
/// * **The avatar sits to the left**, cut into the cover's edge. Centred, it
///   covered the middle of the picture and left the name floating under it;
///   on the left the scene stays visible and the name, badges and figures
///   line up on one edge, which is how a list of facts is read.
/// * **The role is a chip on the cover** ([roleLabel]), so the badges under
///   the name are the ones that were earned - tier, ID verified, member
///   since - and not "Client", which every client has.
/// * **Figures live in the card** ([stats]), as one divided strip, instead of
///   three loose tiles under it. Counts roll up once as the panel appears.
/// * **Your own profile has an Edit button** ([onEdit]) beside the avatar,
///   where people look for it, as well as in the Account list.
///
/// The avatar and name ease in once; everything is instant under the
/// system's reduce-motion setting.
class ProfileCoverHeader extends StatelessWidget {
  const ProfileCoverHeader({
    super.key,
    required this.name,
    this.avatarUrl,
    this.verified = false,
    this.subtitle,
    this.badges = const <Widget>[],
    this.style = SugoCoverStyle.client,
    this.roleLabel,
    this.stats = const <ProfileStat>[],
    this.onEdit,
  });

  final String name;
  final String? avatarUrl;

  /// Shows the verified tick on the avatar.
  final bool verified;

  /// One line under the name - a specialism and a distance, say.
  final String? subtitle;

  /// Small chips under the name - tier, ID status, member since.
  final List<Widget> badges;

  /// Which light the cover is drawn in.
  final SugoCoverStyle style;

  /// "Client" or "Technician", as a chip on the cover. Null shows none.
  final String? roleLabel;

  /// Figures in a strip at the foot of the card. Empty shows none.
  final List<ProfileStat> stats;

  /// Your own profile: an "Edit profile" button beside the avatar.
  final VoidCallback? onEdit;

  /// Height of the cover.
  static const double coverHeight = 140;

  /// The white ring around the avatar, so it reads as cut into the cover.
  static const double _ringWidth = 4;

  static const double _avatarSize = 88;

  static const double _avatarOuter = _avatarSize + _ringWidth * 2;

  @override
  Widget build(BuildContext context) {
    final bool reduced = AppMotion.reduced(context);

    return SugoCard(
      padding: EdgeInsets.zero,
      pressable: false,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: reduced ? 1 : 0, end: 1),
        duration: reduced ? Duration.zero : AppMotion.page,
        curve: AppMotion.emphasized,
        builder: (BuildContext context, double t, Widget? _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(AppSizes.radius - 1),
                      ),
                      child: SizedBox(
                        height: coverHeight,
                        child: SugoBrandCover(
                          style: style,
                          motifHeight: coverHeight,
                        ),
                      ),
                    ),
                    // Room for the lower half of the avatar.
                    const SizedBox(height: _avatarOuter / 2),
                  ],
                ),
                if (roleLabel != null)
                  Positioned(
                    top: AppSizes.md,
                    left: AppSizes.md,
                    child: _RoleChip(
                      label: roleLabel!,
                      icon: style == SugoCoverStyle.technician
                          ? Icons.engineering_rounded
                          : Icons.person_rounded,
                    ),
                  ),
                Positioned(
                  left: AppSizes.lg,
                  top: coverHeight - _avatarOuter / 2,
                  child: Opacity(
                    opacity: t.clamp(0, 1),
                    child: Transform.scale(
                      scale: 0.82 + 0.18 * Curves.easeOutBack.transform(t),
                      child: ProfileAvatar(
                        name: name,
                        avatarUrl: avatarUrl,
                        verified: verified,
                        size: _avatarSize,
                      ),
                    ),
                  ),
                ),
                if (onEdit != null)
                  Positioned(
                    right: AppSizes.lg,
                    top: coverHeight + AppSizes.sm + 2,
                    child: _EditButton(onPressed: onEdit!),
                  ),
              ],
            ),
            Opacity(
              opacity: t.clamp(0, 1),
              child: Transform.translate(
                offset: Offset(0, 8 * (1 - t)),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSizes.lg,
                    AppSizes.md,
                    AppSizes.lg,
                    stats.isEmpty ? AppSizes.lg : AppSizes.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Semantics(
                        header: true,
                        child: Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.title,
                        ),
                      ),
                      if (subtitle != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption,
                        ),
                      ],
                      if (badges.isNotEmpty) ...<Widget>[
                        const SizedBox(height: AppSizes.sm + 2),
                        Wrap(
                          spacing: AppSizes.sm,
                          runSpacing: AppSizes.xs + 2,
                          children: badges,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (stats.isNotEmpty) ...<Widget>[
              const Divider(height: 1, thickness: 1, color: AppColors.divider),
              ProfileStatStrip(stats: stats),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Client" or "Technician", in frosted glass on the cover.
class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _EditButton extends StatelessWidget {
  const _EditButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.edit_outlined, size: 16),
      // "Edit", not "Edit profile": beside an avatar the pencil already says
      // what is edited, and the long label ran into the avatar at 320dp.
      label: const Text('Edit'),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
        shape: const StadiumBorder(),
        // The app font named explicitly: a button's textStyle replaces the
        // theme's rather than merging with it.
        textStyle: const TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// One figure in a profile's strip.
class ProfileStat {
  const ProfileStat({
    required this.label,
    required this.value,
    this.count,
    this.icon,
    this.color = AppColors.primary,
  });

  final String label;

  /// What is shown: "4.8", "12", "Sep 2026", "—".
  final String value;

  /// When set, the figure rolls up from zero to this once. Only for tallies
  /// - a rating or a date rolling from zero reads as a slot machine.
  final int? count;

  final IconData? icon;
  final Color color;
}

/// Figures side by side, divided by hairlines.
class ProfileStatStrip extends StatelessWidget {
  const ProfileStatStrip({super.key, required this.stats});

  final List<ProfileStat> stats;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < stats.length; i++) ...<Widget>[
            if (i > 0)
              const VerticalDivider(
                width: 1,
                thickness: 1,
                indent: AppSizes.md,
                endIndent: AppSizes.md,
                color: AppColors.divider,
              ),
            Expanded(child: _StatCell(stat: stats[i])),
          ],
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.stat});

  final ProfileStat stat;

  @override
  Widget build(BuildContext context) {
    final bool reduced = AppMotion.reduced(context);
    final int? count = stat.count;

    Widget value(String text) => Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
        letterSpacing: -0.2,
      ),
    );

    return Semantics(
      label: '${stat.label}: ${stat.value}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.xs,
          vertical: AppSizes.md,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (stat.icon != null) ...<Widget>[
                  Icon(stat.icon, size: 15, color: stat.color),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: count == null || reduced
                      ? value(stat.value)
                      : TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: count.toDouble()),
                          duration: const Duration(milliseconds: 900),
                          curve: AppMotion.emphasized,
                          builder: (BuildContext _, double v, Widget? _) =>
                              value('${v.round()}'),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              stat.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTextStyles.micro,
            ),
          ],
        ),
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
        boxShadow: AppElevation.md,
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
