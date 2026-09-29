import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../theme/app_text_styles.dart';
import 'sugo_card.dart';
import 'sugo_skeleton.dart';

/// A small inline spinner with an optional line of text.
///
/// For the few places a skeleton cannot stand in - an action in progress, a
/// sheet that is submitting. Screen-level loading should use a skeleton
/// (below), never a full-screen spinner: a spinner says nothing about what is
/// coming and makes the layout jump when it arrives.
class SugoLoading extends StatelessWidget {
  const SugoLoading({super.key, this.label, this.size = 24});

  final String? label;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label ?? 'Loading',
      liveRegion: true,
      excludeSemantics: true,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: size,
              height: size,
              child: const CircularProgressIndicator(strokeWidth: 2.6),
            ),
            if (label != null) ...<Widget>[
              const SizedBox(height: AppSizes.md),
              Text(label!, style: AppTextStyles.caption),
            ],
          ],
        ),
      ),
    );
  }
}

/// A spinner and a word for the inside of a button whose action is running:
/// "Accepting…", "Completing…".
///
/// The word stays because a bare spinner where "Accept" used to be leaves the
/// technician guessing which button they pressed. The colour comes from the
/// button itself (the icon colour it sets), so the same widget reads on a
/// filled button and an outlined one.
class SugoButtonProgress extends StatelessWidget {
  const SugoButtonProgress({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final Color? color = IconTheme.of(context).color;

    return Semantics(
      label: label,
      liveRegion: true,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          ),
          const SizedBox(width: AppSizes.sm),
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// Skeleton of a technician card in a vertical list: avatar, name, meta line,
/// and the two buttons.
class SugoTechnicianSkeleton extends StatelessWidget {
  const SugoTechnicianSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const SugoCard(
      margin: EdgeInsets.only(bottom: AppSizes.md),
      elevation: SugoElevation.sm,
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              SugoSkeleton.circle(size: 56),
              SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SugoSkeleton(width: 140, height: 14),
                    SizedBox(height: AppSizes.sm),
                    SugoSkeleton(width: 100, height: 11),
                    SizedBox(height: AppSizes.sm),
                    SugoSkeleton(width: 170, height: 11),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: AppSizes.lg),
          Row(
            children: <Widget>[
              Expanded(child: SugoSkeleton(height: 40, radius: 12)),
              SizedBox(width: AppSizes.md),
              Expanded(child: SugoSkeleton(height: 40, radius: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Skeleton of a booking card: icon tile, two lines, a status pill, and a
/// footer row.
class SugoBookingSkeleton extends StatelessWidget {
  const SugoBookingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const SugoCard(
      margin: EdgeInsets.only(bottom: AppSizes.md),
      elevation: SugoElevation.sm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              SugoSkeleton(width: 44, height: 44, radius: 13),
              SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SugoSkeleton(width: 170, height: 14),
                    SizedBox(height: AppSizes.sm),
                    SugoSkeleton(width: 110, height: 11),
                  ],
                ),
              ),
              SugoSkeleton(width: 74, height: 24, radius: 999),
            ],
          ),
          SizedBox(height: AppSizes.lg),
          SugoSkeleton(height: 11, width: 200),
          SizedBox(height: AppSizes.sm),
          SugoSkeleton(height: 11, width: 150),
        ],
      ),
    );
  }
}

/// Several skeleton cards of one kind, for a list that is still loading.
class SugoSkeletonCards extends StatelessWidget {
  const SugoSkeletonCards.bookings({super.key, this.count = 3})
    : _technicians = false;

  const SugoSkeletonCards.technicians({super.key, this.count = 3})
    : _technicians = true;

  final int count;
  final bool _technicians;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List<Widget>.generate(
        count,
        (_) => _technicians
            ? const SugoTechnicianSkeleton()
            : const SugoBookingSkeleton(),
      ),
    );
  }
}

/// A star, a figure and an optional count - "★ 4.9 (128)".
///
/// Deliberately prints "New" rather than "0.0" for someone with no reviews: a
/// zero rating reads as a *bad* rating, and a technician with no history has
/// not earned one.
class SugoRatingLabel extends StatelessWidget {
  const SugoRatingLabel({
    super.key,
    required this.rating,
    this.reviewCount,
    this.size = 13,
    this.onDark = false,
  });

  final double rating;
  final int? reviewCount;
  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final bool unrated = rating <= 0;
    final Color ink = onDark ? Colors.white : AppColors.textPrimary;
    final Color muted = onDark
        ? Colors.white.withValues(alpha: 0.75)
        : AppColors.textSecondary;

    return Semantics(
      label: unrated
          ? 'New, no ratings yet'
          : 'Rated ${rating.toStringAsFixed(1)} out of 5'
                '${reviewCount == null ? '' : ' from $reviewCount reviews'}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            unrated ? Icons.auto_awesome_rounded : Icons.star_rounded,
            size: size + 3,
            color: unrated ? AppColors.secondary : AppColors.accent,
          ),
          const SizedBox(width: 3),
          Text(
            unrated ? 'New' : rating.toStringAsFixed(1),
            style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
          if (!unrated && reviewCount != null && reviewCount! > 0) ...<Widget>[
            const SizedBox(width: 3),
            Text(
              '($reviewCount)',
              style: TextStyle(
                fontSize: size - 1,
                fontWeight: FontWeight.w500,
                color: muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
