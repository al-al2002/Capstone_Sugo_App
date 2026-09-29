import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_avatar.dart';
import '../../profile/profile_navigation.dart';
import '../models/community_models.dart';

/// The byline on a post or an answer: picture, name, standing, timestamp.
///
/// ## Why reputation is rendered here and not in the card
///
/// A technician's tier and points are the reason the feed is worth reading -
/// they are what separates an answer from an opinion. Putting that presentation
/// in one widget means an answer cannot accidentally show a name without the
/// credentials attached, which would make it indistinguishable from a comment
/// by anyone at all.
///
/// The points chip is shown only for technicians, and only when they have
/// earned some. A "0 pts" chip beside a new technician's first answer
/// advertises inexperience at exactly the moment they are trying to build a
/// reputation, and it tells the reader nothing they can use.
class CommunityAuthorRow extends StatelessWidget {
  const CommunityAuthorRow({
    super.key,
    required this.author,
    required this.timestamp,
    this.trailing,
    this.dense = false,
  });

  final CommunityAuthor author;
  final DateTime timestamp;
  final Widget? trailing;

  /// Smaller avatar and type, for a nested answer.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        // The picture and the name open that person's profile - the full
        // technician profile, or the public client profile - so an answer
        // can be traced to a real, rated person and a question to whoever
        // asked it. Works from both sides of the app.
        //
        // Nested inside the tappable post card on purpose: a tap on the
        // byline opens the person, a tap anywhere else opens the thread.
        Expanded(
          child: InkWell(
            onTap: author.id.isEmpty
                ? null
                : () => openPersonProfile(
                    context,
                    userId: author.id,
                    role: author.role,
                    name: author.displayName,
                    avatarUrl: author.avatarUrl,
                  ),
            borderRadius: BorderRadius.circular(AppSizes.tileRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: <Widget>[
                  SugoAvatar(
                    name: author.displayName,
                    imageUrl: author.avatarUrl,
                    size: dense ? 34 : AppSizes.avatarSm,
                    verified: author.isTechnician && author.isVerified,
                  ),
                  const SizedBox(width: AppSizes.sm + 2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                author.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.titleSmall.copyWith(
                                  fontSize: dense ? 13 : 13.5,
                                ),
                              ),
                            ),
                            if (author.isTechnician) ...<Widget>[
                              const SizedBox(width: 6),
                              _TierPill(author: author),
                            ],
                          ],
                        ),
                        const SizedBox(height: 1),
                        Row(
                          children: <Widget>[
                            Text(
                              communityTimeAgo(timestamp),
                              style: AppTextStyles.micro,
                            ),
                            if (author.isTechnician &&
                                author.points > 0) ...<Widget>[
                              const _Dot(),
                              Icon(
                                Icons.auto_awesome_rounded,
                                size: 13,
                                color: AppColors.accentDark,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '${author.points} pts',
                                style: AppTextStyles.micro.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.accentDark,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (trailing != null) ...<Widget>[
          const SizedBox(width: AppSizes.sm),
          trailing!,
        ],
      ],
    );
  }
}

/// The tier badge beside a technician's name.
class _TierPill extends StatelessWidget {
  const _TierPill({required this.author});

  final CommunityAuthor author;

  @override
  Widget build(BuildContext context) {
    final (Color tint, Color ink) = author.tierColors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.workspace_premium_rounded, size: 10, color: ink),
          const SizedBox(width: 3),
          Text(
            author.badgeLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: ink,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// The separator between metadata items.
class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 5),
      child: Text(
        '·',
        style: TextStyle(
          fontSize: 12,
          color: AppColors.hint,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
