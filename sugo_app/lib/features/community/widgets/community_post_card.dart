import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_card.dart';
import '../models/community_models.dart';
import '../services/community_service.dart';
import 'community_author_row.dart';

/// One question on the feed.
///
/// ## What the card leads with
///
/// The title, at [AppTextStyles.title]. Everything else on the row - who asked,
/// the topic, how many answers - is metadata that only matters once the title
/// has caught someone. Cards that lead with an avatar and a name make every
/// row look the same and force the reader to scan to the second line before
/// they learn anything.
///
/// ## The answered state
///
/// An unanswered question carries an accent-tinted left edge and an "Unanswered"
/// chip; an answered one shows its answer count in the brand tone. This is the
/// feed's single most useful signal in both directions - a technician looking
/// for something to answer wants the accented ones, and a client browsing for
/// advice wants the others - so it is given colour rather than just a number.
class CommunityPostCard extends StatelessWidget {
  const CommunityPostCard({
    super.key,
    required this.post,
    required this.onTap,
    this.onDelete,
  });

  final CommunityPost post;
  final VoidCallback onTap;

  /// Offered only on the caller's own question.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final bool answered = post.isAnswered;
    final String? photoUrl = CommunityService.publicPhotoUrl(post.imagePath);

    return SugoCard(
      margin: const EdgeInsets.only(bottom: AppSizes.md),
      padding: EdgeInsets.zero,
      onTap: onTap,
      // A Stack, not a stretched Row.
      //
      // The status edge has to be as tall as the card, and the obvious way to
      // say that is `Row(crossAxisAlignment: stretch)`. That is a trap here:
      // the feed is a ListView, so this card is laid out with UNBOUNDED
      // height, and a stretched Row passes its own cross-axis extent down as a
      // tight constraint - `h=Infinity`. The edge then cannot be laid out at
      // all, and from that point every touch on the screen reports
      // "Cannot hit test a render box with no size".
      //
      // A `Positioned` with `top: 0, bottom: 0` gets the same full height
      // without the Stack needing to know that height in advance: the Stack
      // sizes itself to the content child first, then stretches the edge to
      // match. No intrinsic pass, no unbounded constraint.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSizes.panelRadius),
        child: Stack(
          children: <Widget>[
            Padding(
              // Left padding clears the 4px edge drawn behind it.
              padding: const EdgeInsets.fromLTRB(
                AppSizes.md + 6,
                AppSizes.md + 2,
                AppSizes.md + 2,
                AppSizes.md + 2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      _TopicChip(topic: post.topic),
                      const Spacer(),
                      if (onDelete != null)
                        IconButton(
                          onPressed: onDelete,
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 17,
                          ),
                          color: AppColors.hint,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          tooltip: 'Delete this question',
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSizes.sm),

                  // The photo rides beside the text, not above it.
                  //
                  // A full-width image would push the author row and the
                  // answer count off a phone screen and make a question with
                  // a picture twice the height of one without - so the feed
                  // would scroll in two different rhythms. A fixed square
                  // keeps every card the same shape and still says "there is
                  // a picture here".
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              post.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.title.copyWith(fontSize: 16),
                            ),
                            const SizedBox(height: AppSizes.xs + 2),
                            Text(
                              post.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.subtitle,
                            ),
                          ],
                        ),
                      ),
                      if (photoUrl != null) ...<Widget>[
                        const SizedBox(width: AppSizes.md),
                        _Thumbnail(url: photoUrl),
                      ],
                    ],
                  ),

                  const SizedBox(height: AppSizes.md),
                  const Divider(height: 1),
                  const SizedBox(height: AppSizes.md - 2),

                  CommunityAuthorRow(
                    author: post.author,
                    timestamp: post.lastActivityAt,
                    dense: true,
                    trailing: _AnswerCount(post: post),
                  ),
                ],
              ),
            ),

            // The status edge. A 4px bar rather than a full tinted background:
            // it reads at a glance while scrolling, and it does not fight the
            // title for contrast the way a washed card does.
            //
            // Green once answered, accent while nobody has replied - the
            // feed's most useful signal, in both directions.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 4,
              child: ColoredBox(
                color: answered ? AppColors.success : AppColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The square preview on a card.
///
/// Fails quietly in both directions: a slow network shows a tinted square, a
/// dead link shows a broken-image glyph in the same square. Neither changes
/// the card's height, so a feed that is halfway through loading does not jump
/// under the reader's thumb.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.url});

  final String url;

  static const double _side = 66;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSizes.sm + 2),
      child: Image.network(
        url,
        width: _side,
        height: _side,
        fit: BoxFit.cover,
        loadingBuilder:
            (BuildContext context, Widget child, ImageChunkEvent? progress) {
              if (progress == null) return child;
              return const _ThumbnailBox(
                icon: Icons.image_outlined,
                tint: AppColors.fieldFill,
              );
            },
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
          return const _ThumbnailBox(
            icon: Icons.broken_image_outlined,
            tint: AppColors.fieldFill,
          );
        },
      ),
    );
  }
}

class _ThumbnailBox extends StatelessWidget {
  const _ThumbnailBox({required this.icon, required this.tint});

  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _Thumbnail._side,
      height: _Thumbnail._side,
      color: tint,
      alignment: Alignment.center,
      child: Icon(icon, size: 20, color: AppColors.hint),
    );
  }
}

class _TopicChip extends StatelessWidget {
  const _TopicChip({required this.topic});

  final CommunityTopic topic;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primarySofter,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        border: Border.all(color: AppColors.primarySoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(topic.icon, size: 11, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            topic.label,
            style: AppTextStyles.overline.copyWith(
              color: AppColors.primaryDark,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// The answer tally, or the "needs an answer" prompt.
class _AnswerCount extends StatelessWidget {
  const _AnswerCount({required this.post});

  final CommunityPost post;

  @override
  Widget build(BuildContext context) {
    final bool answered = post.isAnswered;

    final Color tint = answered ? AppColors.successSoft : AppColors.accentSoft;
    final Color ink = answered ? AppColors.success : AppColors.accent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            answered
                ? Icons.check_circle_rounded
                : Icons.help_outline_rounded,
            size: 12,
            color: ink,
          ),
          const SizedBox(width: 4),
          Text(
            answered ? '${post.commentCount}' : 'Unanswered',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}
