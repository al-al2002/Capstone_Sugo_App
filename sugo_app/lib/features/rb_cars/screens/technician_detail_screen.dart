import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/services/local_prefs.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/contact_launcher.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/widgets/sugo_pill.dart';
import '../../../core/theme/app_elevation.dart';
import '../../../core/widgets/sugo_app_bar.dart';
import '../../../core/widgets/sugo_skeleton.dart';
import '../models/job_enums.dart';
import '../models/match_result.dart';
import '../models/technician.dart';
import '../models/technician_preferences.dart';
import '../models/technician_profile_details.dart';
import '../services/rb_cars_service.dart';
import '../services/technician_directory_service.dart';
import '../widgets/explainability_chip.dart';
import '../widgets/review_card.dart';
import '../widgets/score_breakdown_sheet.dart';
import '../widgets/stat_chip.dart';
import '../widgets/trust_badge_pill.dart';
import 'job_posting_screen.dart';
import '../../../core/widgets/sugo_brand_cover.dart';
import '../../profile/widgets/profile_cover_header.dart';

/// Technician profile: hero photo, stat chips, tabs, sticky booking bar.
///
/// Two ways in. From the home screen it fetches the profile through the
/// `technician-directory` function. From a match card it already has a
/// snapshot in `score_breakdown`, so it renders instantly and refreshes in the
/// background - the match view also gets the "why this match" line, which the
/// browsing view has no score to show.
class TechnicianDetailScreen extends StatefulWidget {
  const TechnicianDetailScreen({
    super.key,
    required this.technicianId,
    this.match,
    this.initialTechnician,
  });

  final String technicianId;

  /// Present when opened from the Top 3.
  final MatchResult? match;

  /// Optional seed so the screen paints before the network call returns.
  final Technician? initialTechnician;

  @override
  State<TechnicianDetailScreen> createState() => _TechnicianDetailScreenState();
}

class _TechnicianDetailScreenState extends State<TechnicianDetailScreen>
    with SingleTickerProviderStateMixin {
  /// Assigned in [initState], never lazily.
  ///
  /// `build` returns early with a loading scaffold while the technician is
  /// still being fetched, so it does not reach `tabs: _tabs` on that path.
  /// Opening this screen and going back before the fetch lands therefore made
  /// [dispose] the first access - and constructing a `TabController` there
  /// calls `createTicker`, which looks up `TickerMode` on a deactivated
  /// element and throws mid-unmount. Same failure as `_GlyphState` in
  /// `sugo_empty_state.dart`.
  late final TabController _tabs;
  final TechnicianDirectoryService _directory = TechnicianDirectoryService();

  Technician? _technician;
  bool _contactUnlocked = false;

  /// Reviews, past work and the star breakdown. Null until
  /// `technician_profile` answers, and stays null if only the fallback path
  /// worked - the Reviews tab then falls back to the summary it used to show.
  TechnicianProfileDetails? _details;

  /// Matches `reviewLimit` below, so a full first page means there may be more.
  static const int _reviewPageSize = 20;
  bool _loadingMoreReviews = false;
  bool _reachedReviewEnd = false;

  bool _isLoading = true;
  bool _isFavourite = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _technician = widget.initialTechnician ?? widget.match?.technician;
    _load();
    _loadFavourite();
  }

  Future<void> _loadFavourite() async {
    final String? uid = SupabaseService.auth.currentUser?.id;
    if (uid == null) return;
    final bool saved = await LocalPrefs.instance.isFavorite(
      uid,
      widget.technicianId,
    );
    if (mounted && saved) setState(() => _isFavourite = true);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// Loads the full profile, reviews and past work included.
  ///
  /// This screen used to call `byId`, which goes through the
  /// `technician-directory` edge function and returns the technician and the
  /// contact flag - and nothing else. So the screen a client reaches from the
  /// match list, which is exactly when they are deciding whether to book, was
  /// the one screen that never fetched a single review. The Reviews tab could
  /// only show an average and a sentence apologising for the lack of detail.
  ///
  /// `technician_profile` returns everything `byId` did plus the reviews, the
  /// star breakdown and the work history, in one round trip. `byId` is kept as
  /// a fallback so a failure here can never leave the screen worse off than
  /// it was before this change.
  Future<void> _load() async {
    try {
      final TechnicianProfileDetails details = await _directory.profile(
        widget.technicianId,
        reviewLimit: _reviewPageSize,
      );
      if (!mounted) return;
      setState(() {
        _details = details;
        _technician = details.technician;
        _contactUnlocked = details.contactUnlocked;
        _reachedReviewEnd = details.reviews.length < _reviewPageSize;
        _isLoading = false;
        _error = null;
      });
      return;
    } catch (_) {
      // Fall through to the lighter call below.
    }

    try {
      final TechnicianProfile profile = await _directory.byId(
        widget.technicianId,
      );
      if (!mounted) return;
      setState(() {
        _technician = profile.technician;
        _contactUnlocked = profile.contactUnlocked;
        _isLoading = false;
        _error = null;
      });
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        // A snapshot from the match is enough to render, so a failed refresh
        // is only fatal when there was nothing to start with.
        _error = _technician == null ? failure.message : null;
      });
    }
  }

  /// The next page of reviews, keyset-paged on the oldest one on screen.
  Future<void> _loadMoreReviews() async {
    final TechnicianProfileDetails? details = _details;
    if (details == null || _loadingMoreReviews || _reachedReviewEnd) return;
    if (details.reviews.isEmpty) return;

    setState(() => _loadingMoreReviews = true);
    try {
      final List<TechnicianReview> more = await _directory.reviews(
        widget.technicianId,
        before: details.reviews.last.createdAt,
        limit: _reviewPageSize,
      );
      if (!mounted) return;
      setState(() {
        _details = details.withMoreReviews(more);
        _reachedReviewEnd = more.length < _reviewPageSize;
        _loadingMoreReviews = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMoreReviews = false);
      UiFeedback.showError(context, 'Could not load more reviews.');
    }
  }

  Future<void> _confirmBooking() async {
    final MatchResult? match = widget.match;
    final String weather =
        match?.breakdown.context.weatherLabel ?? 'Not available';
    final String traffic =
        match?.breakdown.context.trafficLabel ?? 'Not available';

    final bool? proceed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          titlePadding: const EdgeInsets.fromLTRB(
            AppSizes.xl,
            AppSizes.xl,
            AppSizes.xl,
            AppSizes.sm,
          ),
          contentPadding: const EdgeInsets.fromLTRB(
            AppSizes.xl,
            0,
            AppSizes.xl,
            0,
          ),
          actionsPadding: const EdgeInsets.fromLTRB(
            AppSizes.lg,
            0,
            AppSizes.lg,
            AppSizes.lg,
          ),
          title: Text(
            'Before you book',
            style: AppTextStyles.title.copyWith(color: AppColors.textPrimary),
          ),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Here is the live context for this service request.',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSizes.lg),
                _ContextStatusRow(
                  icon: Icons.wb_sunny_outlined,
                  label: 'Weather',
                  value: weather,
                ),
                const SizedBox(height: AppSizes.sm),
                _ContextStatusRow(
                  icon: Icons.traffic_rounded,
                  label: 'Traffic',
                  value: traffic,
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
              ),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.lg,
                  vertical: AppSizes.sm,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Proceed to book technician'),
            ),
          ],
        );
      },
    );

    if (proceed != true || !mounted) return;
    _startBooking();
  }

  void _startBooking() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            JobPostingScreen(preselectedTechnicianId: widget.technicianId),
      ),
    );
  }

  /// Call or message this technician.
  ///
  /// Both used to end in `UiFeedback.showInfo('Opening call...')` - a button
  /// that announced an action and performed none. Now:
  ///
  /// * **Call** opens the platform dialler with the number the server
  ///   released. `technician-directory` withholds `phone` until the caller has
  ///   a confirmed booking, so an unlocked button always has a number behind
  ///   it, and a locked one explains what unlocks it.
  /// * **Message** needs a job to attach the thread to - chat is scoped to a
  ///   booking, not to a pair of people - so before there is one it says so
  ///   and points at booking.
  Future<void> _contact(String channel) async {
    if (!_contactUnlocked) {
      UiFeedback.showInfo(
        context,
        'Calls and messages open once you have a confirmed booking with this '
        'technician.',
      );
      return;
    }

    if (channel == 'call') {
      await ContactLauncher.call(context, _technician?.phone);
      return;
    }

    // A thread belongs to a job. From here the client may have several with
    // this technician, so the honest move is to send them to the booking
    // rather than guess which conversation they meant.
    if (!mounted) return;
    UiFeedback.showInfo(
      context,
      'Open the booking to message them - each chat belongs to one job.',
    );
  }

  /// Saves or unsaves this technician on this device.
  ///
  /// Favourites are `LocalPrefs`, by the user's decision on 2026-09-22: no
  /// table, no sync. The toggle used to be a `setState` on a field that was
  /// thrown away the moment the screen closed, so the heart forgot every time.
  Future<void> _toggleFavourite() async {
    final String? uid = SupabaseService.auth.currentUser?.id;
    if (uid == null) return;

    final bool nowFavourite = await LocalPrefs.instance.toggleFavorite(
      uid,
      widget.technicianId,
    );
    if (!mounted) return;
    setState(() => _isFavourite = nowFavourite);
    UiFeedback.showSuccess(
      context,
      nowFavourite
          ? 'Saved to your favourites on this phone.'
          : 'Removed from your favourites.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final Technician? technician = _technician;

    if (technician == null) {
      return Scaffold(
        appBar: const SugoAppBar(),
        body: Center(
          child: _isLoading
              // The profile's shape while it loads, not a spinner.
              ? const Padding(
                  padding: EdgeInsets.all(AppSizes.screenPadding),
                  child: SugoSkeletonList(count: 3),
                )
              : Padding(
                  padding: const EdgeInsets.all(AppSizes.xxl),
                  child: Text(
                    _error ?? 'Technician not found.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.subtitle,
                  ),
                ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (BuildContext context, bool _) => <Widget>[
          _HeroHeader(
            technician: technician,
            isFavourite: _isFavourite,
            onFavourite: _toggleFavourite,
          ),
        ],
        body: _Content(
          technician: technician,
          details: _details,
          match: widget.match,
          tabs: _tabs,
          onContact: _contact,
          contactUnlocked: _contactUnlocked,
          onLoadMoreReviews: _loadMoreReviews,
          loadingMoreReviews: _loadingMoreReviews,
          reachedReviewEnd: _reachedReviewEnd,
        ),
      ),
      bottomNavigationBar: _BookingBar(
        technician: technician,
        onBook: _confirmBooking,
      ),
    );
  }
}

/// The profile's header: the drawn brand cover with the technician's photo in
/// a ring at its centre, their name and standing beneath it, and the back and
/// bookmark buttons floating over the top.
///
/// ## Why not their photo, full width (2026-09-29)
///
/// It used to be exactly that. An avatar is a small square, so stretched
/// across a phone it came out soft and cropped - and most accounts have no
/// photo at all, which left faint giant initials on blue. Now the cover is
/// [SugoBrandCover], the same one on every profile in the app, and the photo
/// is shown at the size it was taken for.
///
/// It still collapses: scrolled up, the header folds into a navy bar with the
/// name in it, so the back button never scrolls away with the cover.
class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.technician,
    required this.isFavourite,
    required this.onFavourite,
  });

  final Technician technician;
  final bool isFavourite;
  final VoidCallback onFavourite;

  /// Room for the avatar, the name, one line under it and the badge, below
  /// the status bar and the toolbar. Grows with the text size, so large text
  /// does not push the name into the toolbar.
  static double _expandedHeight(BuildContext context) {
    final double text = MediaQuery.textScalerOf(context).scale(14) / 14;
    return MediaQuery.paddingOf(context).top +
        kToolbarHeight +
        AppSizes.avatarLg +
        8 +
        112 * text;
  }

  @override
  Widget build(BuildContext context) {
    final double expanded = _expandedHeight(context);
    final double top = MediaQuery.paddingOf(context).top;

    return SliverAppBar(
      expandedHeight: expanded,
      pinned: true,
      backgroundColor: AppColors.navy,
      foregroundColor: Colors.white,
      leading: Padding(
        padding: const EdgeInsets.all(AppSizes.sm),
        child: _CircleButton(
          icon: Icons.arrow_back_rounded,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ),
      actions: <Widget>[
        Padding(
          padding: const EdgeInsets.all(AppSizes.sm),
          child: _CircleButton(
            icon: isFavourite
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            onTap: onFavourite,
            tint: isFavourite ? AppColors.accentDark : null,
          ),
        ),
      ],
      flexibleSpace: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final double collapsed = top + kToolbarHeight;
          // 1 fully open, 0 folded into the bar.
          final double open =
              ((box.maxHeight - collapsed) / (expanded - collapsed)).clamp(
                0.0,
                1.0,
              );

          return ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                SugoBrandCover(topInset: collapsed - 20, bottomScrim: true),
                Positioned(
                  left: AppSizes.screenPadding,
                  right: AppSizes.screenPadding,
                  bottom: AppSizes.lg,
                  child: Opacity(
                    opacity: Curves.easeIn.transform(open),
                    child: _Identity(technician: technician),
                  ),
                ),
                // The name in the bar, once the header has folded.
                Positioned(
                  left: 64,
                  right: 64,
                  top: top,
                  height: kToolbarHeight,
                  child: Opacity(
                    opacity: (1 - open * 3).clamp(0.0, 1.0),
                    child: Center(
                      child: Text(
                        technician.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleSmall.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The photo in its ring, the name, one line of standing, and the badge.
class _Identity extends StatelessWidget {
  const _Identity({required this.technician});

  final Technician technician;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ProfileAvatar(
          name: technician.displayName,
          avatarUrl: technician.avatarUrl,
          verified: technician.isVerified,
        ),
        const SizedBox(height: AppSizes.md),
        Text(
          technician.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTextStyles.title.copyWith(color: Colors.white),
        ),
        const SizedBox(height: 2),
        Text(
          <String>[
            technician.headline,
            if (technician.distanceLabel != null)
              '${technician.distanceLabel} away',
            if (technician.memberSinceLabel != null)
              'On SUGO since ${technician.memberSinceLabel}',
          ].join('  ·  '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTextStyles.caption.copyWith(color: Colors.white70),
        ),
        const SizedBox(height: AppSizes.sm),
        SugoPill.badge(
          label: technician.badgeLabel,
          icon:
              technician.trustBadge?.icon ??
              (technician.isVerified
                  ? Icons.verified_rounded
                  : Icons.person_outline_rounded),
          // White words need the text orange: 5.0:1, where the bright orange
          // gave 2.1:1.
          tint: AppColors.accentDark,
          foreground: Colors.white,
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap, this.tint});

  final IconData icon;
  final VoidCallback onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, size: 19, color: tint ?? AppColors.textPrimary),
        ),
      ),
    );
  }
}

class _ContextStatusRow extends StatelessWidget {
  const _ContextStatusRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.fieldFill,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: AppTextStyles.micro.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({
    required this.technician,
    required this.details,
    required this.match,
    required this.tabs,
    required this.onContact,
    required this.contactUnlocked,
    required this.onLoadMoreReviews,
    required this.loadingMoreReviews,
    required this.reachedReviewEnd,
  });

  final Technician technician;
  final TechnicianProfileDetails? details;
  final VoidCallback onLoadMoreReviews;
  final bool loadingMoreReviews;
  final bool reachedReviewEnd;
  final MatchResult? match;
  final TabController tabs;
  final void Function(String channel) onContact;
  final bool contactUnlocked;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSizes.screenPadding,
            AppSizes.lg,
            AppSizes.screenPadding,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _ContactRow(
                technician: technician,
                unlocked: contactUnlocked,
                onContact: onContact,
              ),
              const SizedBox(height: AppSizes.lg),

              Row(
                children: <Widget>[
                  Expanded(
                    child: StatChip.experience(
                      value: technician.tenureLabel ?? 'New',
                    ),
                  ),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: StatChip.rating(
                      value: technician.rating > 0
                          ? technician.rating.toStringAsFixed(1)
                          : 'New',
                    ),
                  ),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: StatChip.jobs(value: '${technician.totalJobs}'),
                  ),
                ],
              ),

              if (match != null) ...<Widget>[
                const SizedBox(height: AppSizes.lg),
                ExplainabilityLine(
                  breakdown: match!.breakdown,
                  maxParts: 4,
                  onTap: () => ScoreBreakdownSheet.show(context, match!),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: AppSizes.lg),
        _Tabs(controller: tabs),
        const SizedBox(height: AppSizes.lg),

        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.screenPadding,
          ),
          child: AnimatedBuilder(
            animation: tabs,
            builder: (BuildContext context, Widget? _) => switch (tabs.index) {
              1 => _AvailabilityTab(technician: technician),
              2 => _ExperienceTab(technician: technician),
              3 => _ReviewsTab(
                technician: technician,
                details: details,
                onLoadMore: onLoadMoreReviews,
                loadingMore: loadingMoreReviews,
                reachedEnd: reachedReviewEnd,
              ),
              _ => _AboutTab(technician: technician),
            },
          ),
        ),
        const SizedBox(height: AppSizes.xxl),
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.technician,
    required this.unlocked,
    required this.onContact,
  });

  final Technician technician;
  final bool unlocked;
  final void Function(String channel) onContact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            // The name is already in the header above; repeating it here
            // read as a second, smaller profile. This row is about reaching
            // them.
            children: <Widget>[
              Text('Get in touch', style: AppTextStyles.titleSmall),
              Text(
                unlocked
                    ? 'Message or call ${technician.displayName.split(' ').first}.'
                    : 'Calling opens once they accept your booking.',
                style: AppTextStyles.caption,
              ),
            ],
          ),
        ),
        _ContactButton(
          icon: Icons.chat_bubble_outline_rounded,
          unlocked: unlocked,
          onTap: () => onContact('chat'),
        ),
        const SizedBox(width: AppSizes.sm),
        _ContactButton(
          icon: Icons.call_rounded,
          unlocked: unlocked,
          onTap: () => onContact('call'),
        ),
      ],
    );
  }
}

class _ContactButton extends StatelessWidget {
  const _ContactButton({
    required this.icon,
    required this.unlocked,
    required this.onTap,
  });

  final IconData icon;
  final bool unlocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: unlocked ? AppColors.primarySoft : AppColors.divider,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(
            icon,
            size: 19,
            color: unlocked ? AppColors.primary : AppColors.hint,
          ),
        ),
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.controller});

  final TabController controller;

  @override
  Widget build(BuildContext context) {
    return TabBar(
      controller: controller,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.screenPadding),
      labelColor: AppColors.primary,
      unselectedLabelColor: AppColors.textSecondary,
      indicatorColor: AppColors.primary,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: AppColors.divider,
      // From AppTextStyles, which names the family: a bare TextStyle here
      // replaced the theme's and the tabs fell back to the phone's font.
      labelStyle: AppTextStyles.label.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelStyle: AppTextStyles.label.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      tabs: const <Widget>[
        Tab(text: 'About'),
        Tab(text: 'Availability'),
        Tab(text: 'Experience'),
        Tab(text: 'Reviews'),
      ],
    );
  }
}

class _AboutTab extends StatelessWidget {
  const _AboutTab({required this.technician});

  final Technician technician;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('About ${technician.displayName}', style: AppTextStyles.label),
        const SizedBox(height: AppSizes.sm),
        Text(
          technician.bio,
          style: AppTextStyles.subtitle.copyWith(height: 1.55),
        ),
        if (technician.skillTags.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSizes.lg),
          const Text('Skills', style: AppTextStyles.label),
          const SizedBox(height: AppSizes.sm),
          Wrap(
            spacing: AppSizes.sm,
            runSpacing: AppSizes.sm,
            children: technician.skillTags
                .map(
                  (String tag) =>
                      SugoPill.soft(label: tag.replaceAll('_', ' ')),
                )
                .toList(growable: false),
          ),
        ],
      ],
    );
  }
}

class _AvailabilityTab extends StatelessWidget {
  const _AvailabilityTab({required this.technician});

  final Technician technician;

  @override
  Widget build(BuildContext context) {
    // `current_workload` is withheld by the directory function - it is a
    // scoring input, not a public field - so availability is expressed
    // qualitatively here rather than as a live queue depth.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('Booking window', style: AppTextStyles.label),
        const SizedBox(height: AppSizes.sm),
        Text(
          'SUGO technicians work on a request basis rather than a fixed '
          'roster. Post a job with your preferred schedule and '
          '${technician.displayName.split(' ').first} will confirm or suggest '
          'another slot.',
          style: AppTextStyles.subtitle.copyWith(height: 1.55),
        ),
        const SizedBox(height: AppSizes.lg),
        const Text('Service paths', style: AppTextStyles.label),
        const SizedBox(height: AppSizes.sm),
        Wrap(
          spacing: AppSizes.sm,
          runSpacing: AppSizes.sm,
          children: ServicePath.values
              .where((ServicePath path) => path != ServicePath.itCommunity)
              .map(
                (ServicePath path) =>
                    SugoPill.soft(label: path.label, icon: path.icon),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _ExperienceTab extends StatelessWidget {
  const _ExperienceTab({required this.technician});

  final Technician technician;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('Specialisations', style: AppTextStyles.label),
        const SizedBox(height: AppSizes.sm),
        if (technician.specialization.isEmpty)
          Text(
            'General repair work across devices.',
            style: AppTextStyles.subtitle,
          )
        else
          Wrap(
            spacing: AppSizes.sm,
            runSpacing: AppSizes.sm,
            children: technician.specialization
                .map(
                  (String area) => SugoPill.soft(
                    label: DeviceType.fromWire(area)?.label ?? area,
                    icon: DeviceType.fromWire(area)?.icon,
                  ),
                )
                .toList(growable: false),
          ),
        if (technician.trustBadge case final TrustBadge badge) ...<Widget>[
          const SizedBox(height: AppSizes.lg),
          const Text('Trust badge', style: AppTextStyles.label),
          const SizedBox(height: AppSizes.sm),
          TrustBadgePill(badge: badge),
          const SizedBox(height: AppSizes.xs),
          Text(badge.blurb, style: AppTextStyles.caption),
          if (technician.skillVerifiedSpecializations.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSizes.sm),
            Text(
              'Skill verified for '
              '${technician.skillVerifiedSpecializations.map((PreferredSpecialization s) => s.label).join(', ')}',
              style: AppTextStyles.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ],
        const SizedBox(height: AppSizes.lg),
        const Text('Track record', style: AppTextStyles.label),
        const SizedBox(height: AppSizes.sm),
        _Fact(label: 'Tier', value: technician.tier.label),
        _Fact(
          label: 'Verified',
          value: technician.isVerified ? 'Yes, ID checked' : 'Pending',
        ),
        _Fact(label: 'Jobs completed', value: '${technician.totalJobs}'),
        _Fact(
          label: 'On SUGO since',
          value: technician.memberSinceLabel ?? 'Not recorded',
        ),
      ],
    );
  }
}

/// What the technician has fixed, and what clients said about it.
///
/// ## What this used to be
///
/// An average, five stars, and a sentence explaining that "individual review
/// text is not in the RB-CARS schema". That was true when it was written -
/// `job_outcomes` stores a bare number - and stopped being true when
/// `job_reviews` arrived, but this tab was never updated. So the screen a
/// client reaches from their match list, at the exact moment they are deciding
/// whether to book, could not show a single thing any previous client wrote.
///
/// ## What it is now, in reading order
///
///   1. **The verdict** - average, stars, how many reviews and jobs.
///   2. **Past work** - every completed job counted by device, including
///      unreviewed ones. Reviews are a sample; this is the whole record.
///   3. **The reviews** - each headed by the repair it was about, so a review
///      of an aircon job is not mistaken for evidence about a phone.
class _ReviewsTab extends StatelessWidget {
  const _ReviewsTab({
    required this.technician,
    required this.details,
    required this.onLoadMore,
    required this.loadingMore,
    required this.reachedEnd,
  });

  final Technician technician;

  /// Null while loading, or if only the lighter fallback call succeeded.
  final TechnicianProfileDetails? details;

  final VoidCallback onLoadMore;
  final bool loadingMore;
  final bool reachedEnd;

  @override
  Widget build(BuildContext context) {
    final TechnicianProfileDetails? full = details;

    if (technician.totalJobs == 0 && (full?.reviews.isEmpty ?? true)) {
      return Text(
        'No completed jobs yet, so there is no work or reviews to show. New '
        'technicians are still ranked: SUGO scores them at a neutral '
        'accuracy prior rather than at zero.',
        style: AppTextStyles.subtitle.copyWith(height: 1.55),
      );
    }

    // Still loading the full profile - show the summary we already have from
    // the card rather than an empty tab.
    if (full == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _RatingHeadline(
            rating: technician.rating,
            reviews: technician.reviewCount,
            jobs: technician.totalJobs,
          ),
          const SizedBox(height: AppSizes.lg),
          const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSizes.lg),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _RatingHeadline(
          rating: full.averageRating,
          reviews: full.reviewCount,
          jobs: technician.totalJobs,
        ),

        if (full.workHistory.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSizes.lg),
          PastWorkSummary(entries: full.workHistory),
        ],

        const SizedBox(height: AppSizes.xl),
        Row(
          children: <Widget>[
            const Icon(
              Icons.rate_review_outlined,
              size: 16,
              color: AppColors.primary,
            ),
            const SizedBox(width: 6),
            Text('What clients said', style: AppTextStyles.sectionTitle),
          ],
        ),
        const SizedBox(height: AppSizes.md),

        if (full.reviews.isEmpty)
          Text(
            'No written reviews yet. Clients can leave one once a job is '
            'completed.',
            style: AppTextStyles.subtitle.copyWith(height: 1.55),
          )
        else ...<Widget>[
          for (final TechnicianReview review in full.reviews)
            ReviewCard(key: ValueKey<String>(review.id), review: review),

          // Explicit rather than infinite scroll. This tab lives inside a
          // NestedScrollView whose inner list is shared with three other tabs,
          // so "load more when near the bottom" would fire from whichever tab
          // happened to be scrolled - a button is the honest control here.
          if (!reachedEnd)
            Center(
              child: loadingMore
                  ? const Padding(
                      padding: EdgeInsets.all(AppSizes.md),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                    )
                  : TextButton.icon(
                      onPressed: onLoadMore,
                      icon: const Icon(Icons.expand_more_rounded, size: 18),
                      label: const Text('Show more reviews'),
                    ),
            ),
        ],
      ],
    );
  }
}

/// The big number, the stars, and what they are based on.
class _RatingHeadline extends StatelessWidget {
  const _RatingHeadline({
    required this.rating,
    required this.reviews,
    required this.jobs,
  });

  final double rating;
  final int reviews;
  final int jobs;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(
          rating > 0 ? rating.toStringAsFixed(1) : '—',
          style: AppTextStyles.display,
        ),
        const SizedBox(width: AppSizes.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              StarRow(rating: rating, size: 17),
              const SizedBox(height: 2),
              Text(
                // Both numbers, because they are different things: every
                // completed job counts toward the work, only some were
                // reviewed. Showing one as if it were the other overstates or
                // understates the record.
                '$reviews ${reviews == 1 ? 'review' : 'reviews'} · '
                '$jobs completed ${jobs == 1 ? 'job' : 'jobs'}',
                style: AppTextStyles.caption,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label, style: AppTextStyles.caption),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sticky bar: the book button, full width.
///
/// The "Hourly fee" and "Typical job" tiles above it were removed on
/// 2026-11-17 at the user's request. They were estimates derived from the
/// tier, not prices the technician set; the real labor and travel fees are
/// shown in the send-request sheet.
class _BookingBar extends StatelessWidget {
  const _BookingBar({required this.technician, required this.onBook});

  final Technician technician;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final String firstName = technician.displayName.split(' ').first;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPadding,
        AppSizes.md,
        AppSizes.screenPadding,
        AppSizes.md,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
        // It floats over the scrolling profile: the bar shadow every floating
        // footer uses, rather than a hand-typed one.
        boxShadow: AppElevation.navBar,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Disabled, not hidden, while they are on vacation: the date on the
            // button tells the client when to come back, which a missing
            // button would not. Booking is refused on the server regardless.
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: technician.isAway ? null : onBook,
                icon: Icon(
                  technician.isAway
                      ? Icons.beach_access_rounded
                      : Icons.event_available_rounded,
                  size: 18,
                ),
                label: Text(technician.awayLabel ?? 'Schedule $firstName'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
