import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/sugo_button.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_loading.dart';
import '../../../core/widgets/sugo_status_badge.dart';
import '../models/technician.dart';
import 'technician_avatar.dart';

/// The full-width technician card used by the directory and favourites.
///
/// ## Why a third card shape
///
/// `TechnicianCard` already has two - the dashboard's narrow portrait tile and
/// the match row - and neither fits here. The directory is where someone
/// *chooses*, so it has to carry the facts a choice needs: verification,
/// rating with review count, jobs completed, distance, whether they can be
/// booked at all this week, and what they cost. The match row deliberately
/// omits price (the job has a budget instead) and the dashboard tile has room
/// for two facts.
///
/// ## About the price
///
/// `₱550/hr` is the tier's published rate from [Technician.indicativeHourlyFee],
/// labelled "from" and never presented as a quote. SUGO does not hold real
/// prices - a repair is priced by the technician after diagnosis - and a card
/// that looked like a quote would set an expectation the app cannot keep.
class TechnicianListCard extends StatelessWidget {
  const TechnicianListCard({
    super.key,
    required this.technician,
    required this.onOpen,
    this.onBook,
    this.isFavorite = false,
    this.onToggleFavorite,
  });

  final Technician technician;

  /// Opens the full profile.
  final VoidCallback onOpen;

  /// Starts a booking with this technician pre-selected. Null while they are
  /// on vacation - the server refuses the offer, so the button would fail.
  final VoidCallback? onBook;

  final bool isFavorite;
  final VoidCallback? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final bool away = technician.isAway;

    return SugoCard(
      margin: const EdgeInsets.only(bottom: AppSizes.md),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  TechnicianAvatar(technician: technician, size: 56),
                  if (technician.isVerified)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(1.5),
                        decoration: const BoxDecoration(
                          color: AppColors.surface,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.verified_rounded,
                          size: 17,
                          color: AppColors.secondary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            technician.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.titleSmall.copyWith(
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (technician.isNew) ...<Widget>[
                          const SizedBox(width: AppSizes.sm),
                          const SugoStatusBadge(
                            label: 'New',
                            icon: Icons.auto_awesome_rounded,
                            tone: SugoTone.info,
                            dense: true,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      technician.specializationLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.micro.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSizes.sm),
                    // The rating line is skipped for somebody with no rating
                    // at all: the "New" badge beside their name already says
                    // it, and `SugoRatingLabel` would print a second "New"
                    // two lines below the first.
                    if (technician.rating > 0)
                      SugoRatingLabel(
                        rating: technician.rating,
                        reviewCount: technician.reviewCount,
                        size: 12.5,
                      )
                    else
                      Text(
                        'No ratings yet — new to SUGO',
                        style: AppTextStyles.micro,
                      ),
                  ],
                ),
              ),
              if (onToggleFavorite != null)
                IconButton(
                  tooltip: isFavorite
                      ? 'Remove from favourites'
                      : 'Save to favourites',
                  onPressed: onToggleFavorite,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    isFavorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: 21,
                    color: isFavorite ? AppColors.error : AppColors.hint,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          Wrap(
            spacing: AppSizes.md,
            runSpacing: AppSizes.sm,
            children: <Widget>[
              _Fact(
                icon: Icons.build_rounded,
                label: technician.totalJobs == 0
                    ? 'No jobs yet'
                    : '${technician.totalJobs} jobs done',
              ),
              if (technician.distanceAwayLabel != null)
                _Fact(
                  icon: Icons.place_rounded,
                  label: technician.distanceAwayLabel!,
                ),
              _Fact(
                icon: Icons.payments_rounded,
                label: 'from ${Fmt.peso(technician.indicativeHourlyFee)}/hr',
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          if (away)
            SugoStatusBadge(
              label: technician.awayLabel ?? 'On vacation',
              icon: Icons.beach_access_rounded,
              tone: SugoTone.warning,
            )
          else
            const SugoStatusBadge(
              label: 'Available for booking',
              icon: Icons.event_available_rounded,
              tone: SugoTone.success,
            ),
          const SizedBox(height: AppSizes.md),
          Row(
            children: <Widget>[
              Expanded(
                child: SugoButton(
                  label: 'View profile',
                  variant: SugoButtonVariant.outlined,
                  size: SugoButtonSize.small,
                  onPressed: onOpen,
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: SugoButton(
                  label: away ? 'Unavailable' : 'Book now',
                  size: SugoButtonSize.small,
                  onPressed: away ? null : onBook,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 13, color: AppColors.hint),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppTextStyles.micro.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
