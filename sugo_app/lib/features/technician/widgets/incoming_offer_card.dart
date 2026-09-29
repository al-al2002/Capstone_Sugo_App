import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_pill.dart';
import '../../rb_cars/models/job.dart';
import '../../rb_cars/models/match_result.dart';
import '../../rb_cars/widgets/explainability_chip.dart';

/// One job offered to this technician: Accept or Decline.
///
/// ## Why there is no "Needs shop" here any more
///
/// There used to be a third button, so a technician had to predict from a photo
/// and a symptom whether the unit would have to travel to the workshop. That is
/// a guess made at the worst possible moment - before they have seen the
/// device. The honest answer usually only exists after they arrive, open it up,
/// and find it needs a bench.
///
/// So the decision moved to where the knowledge is: the offer is a straight
/// yes/no, and `ActiveJobCard` carries the escape hatch once they are on site.
///
/// The job details come from `score_breakdown.job`, not the `jobs` table:
/// `jobs_technician_select_assigned` hides an unassigned job, so until they
/// accept, the snapshot is the only view they have. The client's identity and
/// exact address are deliberately not in it - distance is what they need to
/// judge the offer, and the address unlocks on acceptance.
class IncomingOfferCard extends StatelessWidget {
  const IncomingOfferCard({
    super.key,
    required this.match,
    required this.onAccept,
    required this.onDecline,
    required this.onViewDetails,
    required this.onMessage,
    this.unreadMessages = 0,
    this.isBusy = false,
  });

  final MatchResult match;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  /// Opens the full task: the exact machine, the make, the symptom in the
  /// client's words, their photos and their budget range.
  final VoidCallback onViewDetails;

  /// Opens the negotiation thread. Available *before* accepting, because the
  /// most common reason to decline is a budget that will not cover the part -
  /// and that is a question, not a verdict.
  final VoidCallback onMessage;

  /// Unread messages already waiting on this request.
  final int unreadMessages;

  final bool isBusy;

  /// How long this offer has been sitting.
  ///
  /// The schema has no expiry column, so this is elapsed time rather than a
  /// countdown to a deadline. It answers the question that matters to a
  /// technician - "how stale is this?" - without inventing a timer the backend
  /// would not enforce.
  String get _waitingLabel {
    final DateTime? created = match.createdAt;
    if (created == null) return 'Just now';

    final Duration elapsed = DateTime.now().difference(created);
    if (elapsed.inMinutes < 1) return 'Just now';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min ago';
    if (elapsed.inHours < 24) return '${elapsed.inHours} h ago';
    return '${elapsed.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    final JobSnapshot? job = match.job;

    return SugoCard(
      margin: const EdgeInsets.only(bottom: AppSizes.md),
      borderColor: job?.isUrgent ?? false
          ? AppColors.accent.withValues(alpha: 0.45)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (job?.isUrgent ?? false)
                const SugoPill.badge(
                  label: 'Needed today',
                  icon: Icons.bolt_rounded,
                  tint: AppColors.accentSoft,
                  foreground: AppColors.accentDark,
                )
              else
                const SugoPill.badge(
                  label: 'Can wait',
                  icon: Icons.schedule_rounded,
                  tint: AppColors.primarySoft,
                  foreground: AppColors.primaryDark,
                ),
              const Spacer(),
              Icon(
                Icons.hourglass_bottom_rounded,
                size: 13,
                color: AppColors.hint,
              ),
              const SizedBox(width: 3),
              Text(
                _waitingLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primarySofter,
                  borderRadius: BorderRadius.circular(AppSizes.radius),
                ),
                child: Icon(
                  job?.deviceType.icon ?? Icons.devices_other_rounded,
                  size: 21,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      job?.title ?? 'Repair job',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: AppSizes.md,
                      runSpacing: 3,
                      children: <Widget>[
                        if (job?.servicePath != null)
                          _Meta(
                            icon: job!.servicePath!.icon,
                            label: job.servicePath!.label,
                          ),
                        if (match.breakdown.context.distanceLabel != null)
                          _Meta(
                            icon: Icons.place_rounded,
                            label: match.breakdown.context.distanceLabel!,
                          ),
                        if (job != null)
                          _Meta(
                            icon: Icons.payments_outlined,
                            label: job.budgetLabel,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              _RankChip(rank: match.rank),
            ],
          ),

          if (job?.hasPhysicalDamage ?? false) ...<Widget>[
            const SizedBox(height: AppSizes.sm),
            const Row(
              children: <Widget>[
                Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: AppColors.warning,
                ),
                SizedBox(width: 5),
                Text(
                  'Client reported visible physical damage',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.warning,
                  ),
                ),
              ],
            ),
          ],

          if (job?.description != null) ...<Widget>[
            const SizedBox(height: AppSizes.sm),
            Text(
              job!.description!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ],

          const SizedBox(height: AppSizes.md),
          ExplainabilityLine(breakdown: match.breakdown, maxParts: 3),

          const SizedBox(height: AppSizes.md),

          // Two rows, because these are two different kinds of action.
          //
          // The top row is how you find out more - read the task, or ask
          // about it. The bottom row is the answer. Mixing them would put
          // "Decline" next to "View task" at the same weight, and an
          // irreversible action should never sit in a row of safe ones.
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isBusy ? null : onViewDetails,
                  icon: const Icon(Icons.article_outlined, size: 16),
                  label: const Text('View task'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(40),
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isBusy ? null : onMessage,
                  icon: _MessageIcon(unread: unreadMessages),
                  label: const Text('Message'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(40),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          Row(
            children: <Widget>[
              Expanded(
                child: ElevatedButton(
                  onPressed: isBusy ? null : onAccept,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(42),
                  ),
                  child: const Text('Accept'),
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: OutlinedButton(
                  onPressed: isBusy ? null : onDecline,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    minimumSize: const Size.fromHeight(42),
                  ),
                  child: const Text('Decline'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The chat icon, with a dot when the client is already waiting on a reply.
///
/// A count is not drawn here. On a button this size the number would be
/// smaller than the caption text, and "there is something unread" is the
/// entire decision anyway - the thread is one tap away.
class _MessageIcon extends StatelessWidget {
  const _MessageIcon({required this.unread});

  final int unread;

  @override
  Widget build(BuildContext context) {
    const Icon icon = Icon(Icons.chat_bubble_outline_rounded, size: 16);
    if (unread <= 0) return icon;

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        icon,
        Positioned(
          top: -2,
          right: -3,
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }
}

class _RankChip extends StatelessWidget {
  const _RankChip({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final bool top = rank == 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: top ? AppColors.primary : AppColors.primarySofter,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      ),
      child: Text(
        top ? 'Top pick' : 'Rank $rank',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: top ? Colors.white : AppColors.primaryDark,
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 13, color: AppColors.textSecondary),
        const SizedBox(width: 3),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
