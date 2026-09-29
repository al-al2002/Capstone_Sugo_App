import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_card.dart';
import '../models/community_models.dart';
import 'community_author_row.dart';

/// One answer, with the control that rates it.
class CommunityAnswerCard extends StatelessWidget {
  const CommunityAnswerCard({
    super.key,
    required this.answer,
    required this.onToggleHelpful,
    this.onDelete,
  });

  final CommunityAnswer answer;
  final ValueChanged<bool> onToggleHelpful;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    // A technician's answer is what the thread exists for, so it gets the
    // white card. A client chiming in on their own question is context, so it
    // sits on the page tint with no elevation - present, but visibly not the
    // thing being rated.
    final bool isAnswer = answer.isFromTechnician;

    return SugoCard(
      margin: const EdgeInsets.only(bottom: AppSizes.md),
      padding: const EdgeInsets.all(AppSizes.md + 2),
      elevation: isAnswer ? SugoElevation.sm : SugoElevation.flat,
      background: isAnswer ? AppColors.surface : AppColors.primarySofter,
      borderColor: isAnswer ? null : AppColors.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CommunityAuthorRow(
            author: answer.author,
            timestamp: answer.createdAt,
            dense: true,
            trailing: onDelete == null
                ? null
                : IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 17),
                    color: AppColors.hint,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    tooltip: 'Delete this answer',
                  ),
          ),
          const SizedBox(height: AppSizes.md),
          Text(answer.body, style: AppTextStyles.body),

          if (isAnswer) ...<Widget>[
            const SizedBox(height: AppSizes.md),
            Row(
              children: <Widget>[
                _HelpfulButton(answer: answer, onToggle: onToggleHelpful),
                const Spacer(),
                if (answer.helpfulCount > 0) _PointsEarned(answer: answer),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The thumbs-up control.
///
/// ## What happens on tap
///
/// Three things at once, all on [AppMotion.fast]: the icon swaps to its filled
/// form, the pill fills with the success tint, and the whole control springs
/// briefly to 1.18 before settling. The spring is the one place in the app
/// licensed to overshoot - rating an answer is a once-per-answer act of
/// generosity, not a control anyone presses repeatedly, and the small reward
/// is the point.
///
/// A haptic tick fires with it. Voting is otherwise a silent, consequence-free
/// tap, and without the tick it is genuinely unclear whether it registered.
///
/// ## Three states, not two
///
/// * **Can vote** - the live control.
/// * **Already voted** - filled, still tappable, because a rating you cannot
///   withdraw is one people hesitate to give in the first place.
/// * **Cannot vote** - a technician reading a peer's answer, or the author of
///   the answer. The tally is shown as a plain read-only count rather than a
///   disabled button, because a greyed-out control invites a tap that will
///   never work and reads as a bug.
class _HelpfulButton extends StatefulWidget {
  const _HelpfulButton({required this.answer, required this.onToggle});

  final CommunityAnswer answer;
  final ValueChanged<bool> onToggle;

  @override
  State<_HelpfulButton> createState() => _HelpfulButtonState();
}

class _HelpfulButtonState extends State<_HelpfulButton>
    with SingleTickerProviderStateMixin {
  /// Created in [initState], never lazily.
  ///
  /// [build] returns early with a read-only tally when the reader cannot vote -
  /// a technician looking at a peer's answer, or the author of it - so on that
  /// path nothing ever touched this field. [dispose] was then the first
  /// access, and building an `AnimationController` there calls `createTicker`,
  /// which looks up `TickerMode` on an already-deactivated element and throws
  /// mid-unmount. See the same note on `_GlyphState` in `sugo_empty_state.dart`.
  late final AnimationController _spring;

  @override
  void initState() {
    super.initState();
    _spring = AnimationController(
      vsync: this,
      duration: AppMotion.base,
      lowerBound: 0,
      upperBound: 1,
    );
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  void _tap() {
    final bool next = !widget.answer.hasVoted;

    // Only on the way up. Springing as a vote is withdrawn would celebrate
    // the wrong thing.
    if (next) {
      _spring.forward(from: 0);
      HapticFeedback.lightImpact();
    }

    widget.onToggle(next);
  }

  @override
  Widget build(BuildContext context) {
    final CommunityAnswer answer = widget.answer;

    if (!answer.canVote) {
      return _ReadOnlyTally(count: answer.helpfulCount);
    }

    final bool voted = answer.hasVoted;

    return AnimatedBuilder(
      animation: _spring,
      builder: (BuildContext context, Widget? child) {
        // A single hump: 0 -> 1 -> 0 over the controller's run, so the control
        // returns to its own size rather than staying enlarged.
        final double t = _spring.value;
        final double scale = 1 + (0.18 * (t < 0.5 ? t * 2 : (1 - t) * 2));
        return Transform.scale(scale: scale, child: child);
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _tap,
          borderRadius: BorderRadius.circular(AppSizes.pillRadius),
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.standard,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.md,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: voted ? AppColors.successSoft : AppColors.background,
              borderRadius: BorderRadius.circular(AppSizes.pillRadius),
              border: Border.all(
                color: voted ? AppColors.success : AppColors.border,
                width: voted ? 1.4 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  voted
                      ? Icons.thumb_up_rounded
                      : Icons.thumb_up_outlined,
                  size: 14,
                  color: voted ? AppColors.success : AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  answer.helpfulCount == 0
                      ? 'Helpful'
                      : 'Helpful · ${answer.helpfulCount}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: voted
                        ? AppColors.success
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The tally as seen by someone who cannot vote on it.
class _ReadOnlyTally extends StatelessWidget {
  const _ReadOnlyTally({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count == 0) {
      return Text(
        'No ratings yet',
        style: AppTextStyles.micro,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(
          Icons.thumb_up_rounded,
          size: 13,
          color: AppColors.success,
        ),
        const SizedBox(width: 5),
        Text(
          count == 1 ? '1 client found this helpful' : '$count found helpful',
          style: AppTextStyles.micro.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.success,
          ),
        ),
      ],
    );
  }
}

/// What the answer earned its author.
///
/// Shown because the points economy is only motivating if it is visible at the
/// moment it pays out. A technician who sees "+10 pts" on their own answer
/// learns the rule without ever reading a help page.
class _PointsEarned extends StatelessWidget {
  const _PointsEarned({required this.answer});

  final CommunityAnswer answer;

  /// Mirrors `community_points_per_vote()` in migration 20260921000001.
  static const int pointsPerVote = 5;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.accentSofter,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.auto_awesome_rounded,
            size: 13,
            color: AppColors.accentDark,
          ),
          const SizedBox(width: 4),
          Text(
            '+${answer.helpfulCount * pointsPerVote} pts',
            // The text orange: the bright one is 2.1:1 on white.
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.accentDark,
            ),
          ),
        ],
      ),
    );
  }
}
