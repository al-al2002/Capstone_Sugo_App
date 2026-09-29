import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_app_bar.dart';
import '../../../core/widgets/sugo_skeleton.dart';
import '../models/technician.dart';
import '../models/technician_profile_details.dart';
import '../models/technician_specialization.dart';
import '../services/rb_cars_service.dart';
import '../services/technician_directory_service.dart';
import '../widgets/review_card.dart';
import '../widgets/technician_avatar.dart';

/// The profile behind a card tap, from either listing.
///
/// Opened with the [Technician] the card already had, so the header - name,
/// avatar, specialisation, rating - paints on the first frame instead of after
/// a spinner. `technician_profile()` then fills in the four things the card
/// does not carry: specialisation badges, portfolio photos, the star breakdown
/// and the reviews.
///
/// That is why [seed] exists and why a failed load is not necessarily fatal:
/// with a seed, the screen degrades to the header it already had and offers a
/// retry. Without one it has nothing to show and the error takes the screen.
class TechnicianProfileScreen extends StatefulWidget {
  const TechnicianProfileScreen({
    super.key,
    required this.technicianId,
    this.seed,
    this.originLatitude,
    this.originLongitude,
    this.onBook,
  });

  /// Convenience constructor for a card tap, where the row is already in hand.
  TechnicianProfileScreen.fromCard({
    Key? key,
    required Technician technician,
    double? originLatitude,
    double? originLongitude,
    VoidCallback? onBook,
  }) : this(
         key: key,
         technicianId: technician.id,
         seed: technician,
         originLatitude: originLatitude,
         originLongitude: originLongitude,
         onBook: onBook,
       );

  final String technicianId;

  /// The card's own copy, shown while the full profile loads.
  final Technician? seed;

  /// The client's position, so the header can carry a distance. Display only -
  /// it never affects what is shown, only whether the distance line appears.
  final double? originLatitude;
  final double? originLongitude;

  /// Null hides the booking bar, which is correct when the profile is opened
  /// from somewhere with no job to book.
  final VoidCallback? onBook;

  @override
  State<TechnicianProfileScreen> createState() =>
      _TechnicianProfileScreenState();
}

class _TechnicianProfileScreenState extends State<TechnicianProfileScreen> {
  final TechnicianDirectoryService _service = TechnicianDirectoryService();
  final ScrollController _scroll = ScrollController();

  TechnicianProfileDetails? _details;
  String? _error;
  bool _loading = true;

  /// Paging state for the review list.
  bool _loadingMore = false;
  bool _reachedEnd = false;

  /// Matches `p_review_limit` below and the page size used by [_loadMore], so
  /// "a short page means the end" holds for both.
  static const int _reviewPageSize = 20;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final TechnicianProfileDetails details = await _service.profile(
        widget.technicianId,
        latitude: widget.originLatitude,
        longitude: widget.originLongitude,
        reviewLimit: _reviewPageSize,
      );
      if (!mounted) return;
      setState(() {
        _details = details;
        _reachedEnd = details.reviews.length < _reviewPageSize;
        _loading = false;
      });
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load this profile.';
        _loading = false;
      });
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final double remaining =
        _scroll.position.maxScrollExtent - _scroll.position.pixels;
    // Fetch a screen early so the list does not visibly stall at the bottom.
    if (remaining < 400) _loadMore();
  }

  Future<void> _loadMore() async {
    final TechnicianProfileDetails? details = _details;
    if (details == null || _loadingMore || _reachedEnd) return;
    if (details.reviews.isEmpty) return;

    setState(() => _loadingMore = true);

    try {
      final List<TechnicianReview> more = await _service.reviews(
        widget.technicianId,
        // Keyset paging: continue from the oldest review already on screen.
        before: details.reviews.last.createdAt,
        limit: _reviewPageSize,
      );
      if (!mounted) return;
      setState(() {
        _details = details.withMoreReviews(more);
        _reachedEnd = more.length < _reviewPageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      // A failed page is not a failed screen: stop paging quietly and leave
      // what is already loaded readable.
      setState(() {
        _loadingMore = false;
        _reachedEnd = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final TechnicianProfileDetails? details = _details;
    final Technician? header = details?.technician ?? widget.seed;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const SugoAppBar(title: 'Technician', surface: true),
      body: header == null
          ? _FullScreenState(
              loading: _loading,
              error: _error,
              onRetry: _load,
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                controller: _scroll,
                slivers: <Widget>[
                  SliverToBoxAdapter(
                    child: _Header(
                      technician: header,
                      details: details,
                    ),
                  ),

                  // The banner appears only when the extra data failed but the
                  // seed carried the screen - see the class doc.
                  if (_error != null)
                    SliverToBoxAdapter(
                      child: _InlineError(message: _error!, onRetry: _load),
                    ),

                  if (details == null && _loading)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(AppSizes.xxl),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                      ),
                    ),

                  if (details != null) ...<Widget>[
                    SliverToBoxAdapter(
                      child: _Specializations(items: details.specializations),
                    ),
                    SliverToBoxAdapter(
                      child: _Portfolio(items: details.portfolio),
                    ),
                    SliverToBoxAdapter(child: _RatingSummary(details: details)),

                    // Every completed job by device, reviewed or not - the
                    // whole record, where the reviews below are a sample.
                    if (details.workHistory.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSizes.screenPadding,
                            AppSizes.lg,
                            AppSizes.screenPadding,
                            0,
                          ),
                          child: PastWorkSummary(
                            entries: details.workHistory,
                          ),
                        ),
                      ),

                    SliverToBoxAdapter(
                      child: _SectionTitle(
                        'Reviews',
                        trailing: details.reviewCount == 0
                            ? null
                            : '${details.reviewCount}',
                      ),
                    ),
                    if (details.reviews.isEmpty)
                      const SliverToBoxAdapter(
                        child: _EmptyNote(
                          icon: Icons.reviews_outlined,
                          message:
                              'No written reviews yet. Clients can leave one '
                              'after a job is completed.',
                        ),
                      )
                    else
                      // The shared card, so a review reads the same here as
                      // on the detail screen reached from the match list -
                      // each one headed by the repair it was about.
                      SliverList.builder(
                        itemCount: details.reviews.length,
                        itemBuilder: (BuildContext context, int index) =>
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSizes.screenPadding,
                              ),
                              child: ReviewCard(
                                key: ValueKey<String>(
                                  details.reviews[index].id,
                                ),
                                review: details.reviews[index],
                              ),
                            ),
                      ),
                    if (_loadingMore)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(AppSizes.lg),
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],

                  const SliverToBoxAdapter(child: SizedBox(height: AppSizes.xxl)),
                ],
              ),
            ),
      bottomNavigationBar: widget.onBook == null
          ? null
          : _BookingBar(onBook: widget.onBook!, awayLabel: header?.awayLabel),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.technician, this.details});

  final Technician technician;
  final TechnicianProfileDetails? details;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPadding,
        AppSizes.lg,
        AppSizes.screenPadding,
        AppSizes.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TechnicianAvatar(technician: technician, size: 68),
              const SizedBox(width: AppSizes.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            technician.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (technician.isVerified) ...<Widget>[
                          const SizedBox(width: 5),
                          const Icon(
                            Icons.verified_rounded,
                            size: 16,
                            color: AppColors.primary,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      technician.specializationLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    if (technician.distanceAwayLabel != null) ...<Widget>[
                      const SizedBox(height: 5),
                      Row(
                        children: <Widget>[
                          const Icon(
                            Icons.place_rounded,
                            size: 12,
                            color: AppColors.hint,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            technician.distanceAwayLabel!,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          Row(
            children: <Widget>[
              _Stat(
                value: technician.rating > 0
                    ? technician.rating.toStringAsFixed(1)
                    : '—',
                label: 'Rating',
              ),
              _Stat(
                value: '${technician.totalJobs}',
                label: 'Jobs done',
              ),
              _Stat(
                value: '${details?.reviewCount ?? technician.reviewCount}',
                label: 'Reviews',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One figure in the header's three-up stat row.
class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: AppSizes.sm),
        padding: const EdgeInsets.symmetric(vertical: AppSizes.md),
        decoration: BoxDecoration(
          color: AppColors.primarySofter,
          borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        ),
        child: Column(
          children: <Widget>[
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Specialisation badges
// ---------------------------------------------------------------------------

class _Specializations extends StatelessWidget {
  const _Specializations({required this.items});

  final List<TechnicianSpecialization> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SectionTitle('Specialisations'),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.screenPadding,
          ),
          child: Wrap(
            spacing: AppSizes.sm,
            runSpacing: AppSizes.sm,
            children: items
                .map((TechnicianSpecialization s) => _SpecializationBadge(spec: s))
                .toList(growable: false),
          ),
        ),
      ],
    );
  }
}

/// One badge. A verified specialisation is filled and carries a tick; an
/// unverified one is outlined.
///
/// The distinction is the point of the badge: `verified` is set only by a
/// passed assessment, so rendering both states identically would present a
/// self-declared skill as a proven one.
class _SpecializationBadge extends StatelessWidget {
  const _SpecializationBadge({required this.spec});

  final TechnicianSpecialization spec;

  @override
  Widget build(BuildContext context) {
    final bool verified = spec.verified;
    final String? level = spec.skillLabel;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: verified ? AppColors.primarySoft : AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        border: Border.all(
          color: verified ? AppColors.primarySoft : AppColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            verified ? Icons.verified_rounded : Icons.build_circle_outlined,
            size: 13,
            color: verified ? AppColors.primary : AppColors.hint,
          ),
          const SizedBox(width: 5),
          Text(
            spec.badgeLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: verified ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
          if (level != null) ...<Widget>[
            const SizedBox(width: 5),
            Text(
              level,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.success,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Portfolio
// ---------------------------------------------------------------------------

class _Portfolio extends StatelessWidget {
  const _Portfolio({required this.items});

  final List<PortfolioItem> items;

  static const double _height = 128;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SectionTitle('Past work'),
        SizedBox(
          height: _height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.screenPadding,
            ),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSizes.sm),
            itemBuilder: (BuildContext context, int index) =>
                _PortfolioTile(item: items[index]),
          ),
        ),
      ],
    );
  }
}

class _PortfolioTile extends StatelessWidget {
  const _PortfolioTile({required this.item});

  final PortfolioItem item;

  @override
  Widget build(BuildContext context) {
    final String? caption = item.description?.trim();

    return SizedBox(
      width: 148,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Image.network(
              item.photoUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: AppColors.primarySofter,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.image_not_supported_outlined,
                  color: AppColors.hint,
                  size: 20,
                ),
              ),
            ),
            if (caption != null && caption.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.sm,
                    vertical: 5,
                  ),
                  // A solid scrim, not opacity on the text: a caption over a
                  // bright photo is otherwise unreadable.
                  color: AppColors.navy.withValues(alpha: 0.72),
                  child: Text(
                    caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      height: 1.25,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rating summary
// ---------------------------------------------------------------------------

class _RatingSummary extends StatelessWidget {
  const _RatingSummary({required this.details});

  final TechnicianProfileDetails details;

  @override
  Widget build(BuildContext context) {
    if (details.reviewCount == 0) return const SizedBox.shrink();

    final int largest = details.largestStarBucket;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SectionTitle('Rating'),
        Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppSizes.screenPadding,
          ),
          padding: const EdgeInsets.all(AppSizes.lg),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSizes.tileRadius),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Column(
                children: <Widget>[
                  Text(
                    details.averageRating.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      height: 1.05,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  _Stars(rating: details.averageRating, size: 13),
                  const SizedBox(height: 4),
                  Text(
                    '${details.reviewCount} review'
                    '${details.reviewCount == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: AppSizes.xl),
              Expanded(
                child: Column(
                  // 5 down to 1, the order every store uses.
                  children: <Widget>[
                    for (int star = 5; star >= 1; star--)
                      _BreakdownBar(
                        star: star,
                        count: details.starBreakdown[star] ?? 0,
                        largest: largest,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BreakdownBar extends StatelessWidget {
  const _BreakdownBar({
    required this.star,
    required this.count,
    required this.largest,
  });

  final int star;
  final int count;
  final int largest;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 10,
            child: Text(
              '$star',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSizes.pillRadius),
              child: LinearProgressIndicator(
                // Scaled to the largest bucket, not to the total: with 40 of
                // 45 reviews at five stars, scaling to the total leaves the
                // other four bars invisible.
                value: largest == 0 ? 0 : count / largest,
                minHeight: 6,
                backgroundColor: AppColors.divider,
                // The text orange: the bright one is under 3:1 against the
                // track, and the bar is the count.
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.accentDark,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 26,
            child: Text(
              '$count',
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Five stars, filled to [rating]. Half stars are rendered because the average
/// is a real number even though each individual review is a whole star.
class _Stars extends StatelessWidget {
  const _Stars({required this.rating, this.size = 14});

  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 1; i <= 5; i++)
          Icon(
            rating >= i
                ? Icons.star_rounded
                : (rating >= i - 0.5
                      ? Icons.star_half_rounded
                      : Icons.star_border_rounded),
            size: size,
            color: AppColors.accent,
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Reviews
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Shared small pieces
// ---------------------------------------------------------------------------

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPadding,
        AppSizes.xl,
        AppSizes.screenPadding,
        AppSizes.md,
      ),
      child: Row(
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: AppSizes.sm),
            Text(
              trailing!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.hint,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSizes.screenPadding),
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 22, color: AppColors.hint),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.caption.copyWith(fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSizes.screenPadding,
        AppSizes.lg,
        AppSizes.screenPadding,
        0,
      ),
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.cloud_off_rounded, size: 20, color: AppColors.hint),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.caption.copyWith(fontSize: 12),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _FullScreenState extends StatelessWidget {
  const _FullScreenState({
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      // The profile's shape while it loads, not a centred spinner.
      return const Padding(
        padding: EdgeInsets.all(AppSizes.screenPadding),
        child: SugoSkeletonList(count: 3),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.person_off_outlined, size: 34, color: AppColors.hint),
            const SizedBox(height: AppSizes.md),
            Text(
              error ?? 'This technician is no longer listed.',
              textAlign: TextAlign.center,
              style: AppTextStyles.caption.copyWith(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: AppSizes.md),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class _BookingBar extends StatelessWidget {
  const _BookingBar({required this.onBook, this.awayLabel});

  final VoidCallback onBook;

  /// "On vacation until Sep 27" while they are away, which disables the
  /// button and becomes its label. Booking is refused on the server too.
  final String? awayLabel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(
        AppSizes.screenPadding,
        0,
        AppSizes.screenPadding,
        AppSizes.md,
      ),
      child: SizedBox(
        height: AppSizes.buttonHeight,
        child: FilledButton(
          onPressed: awayLabel == null ? onBook : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
            ),
          ),
          child: Text(awayLabel ?? 'Book this technician'),
        ),
      ),
    );
  }
}
