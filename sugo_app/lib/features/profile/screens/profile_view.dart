import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/session/session_state.dart';
import '../../../core/theme/app_elevation.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_dialog.dart';
import '../../../core/widgets/sugo_list_tile.dart';
import '../../../core/widgets/sugo_brand_cover.dart';
import '../../../core/widgets/sugo_skeleton.dart';
import '../../auth/presentation/controllers/auth_controller.dart';
import '../../community/services/community_service.dart';
import '../../onboarding/models/registration_status.dart';
import '../../rb_cars/models/job.dart';
import '../../rb_cars/models/job_enums.dart';
import '../../rb_cars/models/technician.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../../technician/services/technician_service.dart';
import '../../technician/widgets/vacation_card.dart';
import '../../community/screens/community_feed_view.dart';
import '../../help/help_screen.dart';
import '../../notifications/screens/notification_settings_screen.dart';
import '../../rb_cars/screens/technician_browse_screen.dart';
import '../models/client_booking_stats.dart';
import '../widgets/profile_cover_header.dart';
import 'profile_setup_screen.dart';
import 'saved_addresses_screen.dart';
import 'settings_screen.dart';

/// The Profile tab, for both roles.
///
/// Reads [SessionController], which already holds the account's role,
/// verification state and registration status - the single source the router
/// uses. Re-querying here would be a second answer to "what is this account?"
/// and the two would disagree the first time one of them was refreshed.
///
/// Read-only, and deliberately so. Everything shown - verification, tier,
/// trust level - is awarded by a review decision through a database function
/// that enforces the conditions. An editable field on this screen would be a
/// way around all of it. Editing a name or a photo is genuine profile work and
/// is handled by `ProfileSetupScreen.edit`, which changes only the photo and a
/// technician's workshop - never the name, which the ID review verified.
///
/// ## What the renovation changed
///
/// **A hero, not a row.** The identity block was an avatar beside two lines of
/// text. It is now a panel carrying the avatar, name, tier badge and
/// verification state - because this screen is the one place a technician sees
/// their own standing, and standing that is rendered as a caption does not
/// read as something worth earning. Since 2026-09-27 the panel opens with a
/// cover photo - the emblem from the app icon - with the avatar cut into
/// its lower edge; see [ProfileCoverHeader].
///
/// **Stats.** A technician now sees rating, jobs completed and community
/// points as figures. All three already existed; none of them were on this
/// screen, which is why it read as a settings page rather than a profile.
///
/// **The extra fetch.** [SessionProfile] holds identity and status but not
/// tier, rating or points, so a technician's card loads those separately.
/// Failure is non-fatal: the screen renders without the figures rather than
/// replacing a working profile with an error.
class ProfileView extends StatefulWidget {
  const ProfileView({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  final TechnicianService _technicians = TechnicianService();
  final CommunityService _community = CommunityService();
  final RbCarsService _jobs = RbCarsService();

  Technician? _technician;
  ({int points, int helpfulVotes, int answers})? _reputation;

  /// A client's bookings, for the figures in the header (2026-11-16). Since
  /// 2026-11-23 only Home Service and Shop Repair jobs count - see
  /// [ClientBookingStats].
  ClientBookingStats? _bookings;

  @override
  void initState() {
    super.initState();
    // Deferred so the first frame paints from the session alone; the figures
    // replace their dashes a moment later.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadExtras());
  }

  Future<void> _loadExtras() async {
    final SessionProfile? profile = context.read<SessionController>().profile;
    if (profile == null) return;

    // A client's figures are their bookings. Decoration, like the
    // technician's below: a failure shows dashes, never an error.
    if (profile.isClient) {
      final List<Job> jobs = await _jobs.myJobs().catchError(
        (_) => const <Job>[],
      );
      if (!mounted) return;
      setState(() => _bookings = ClientBookingStats.from(jobs));
      return;
    }
    if (!profile.isTechnician) return;

    // Both are decoration on top of a profile that already renders, so each
    // failure degrades to "no figure" rather than to an error screen.
    final Technician? technician = await _technicians.me().catchError(
      (_) => null,
    );
    final ({int points, int helpfulVotes, int answers}) reputation =
        await _community.reputation(profile.userId);

    if (!mounted) return;
    setState(() {
      _technician = technician;
      _reputation = reputation;
    });
  }

  @override
  Widget build(BuildContext context) {
    final SessionController session = context.watch<SessionController>();
    final SessionProfile? profile = session.profile;

    if (session.isLoading && profile == null) {
      return const Padding(
        padding: EdgeInsets.all(AppSizes.screenPadding),
        child: Column(
          children: <Widget>[
            // About the height of the cover header, so nothing jumps when the
            // real one replaces it.
            SugoSkeleton(height: 300, radius: AppSizes.panelRadius),
            SizedBox(height: AppSizes.lg),
            SugoSkeletonList(count: 2, showAvatar: false),
          ],
        ),
      );
    }

    final RegistrationStatus status = RegistrationStatus.fromWire(
      profile?.registrationStatus,
    );

    return RefreshIndicator(
      onRefresh: () async {
        await session.refresh();
        await _loadExtras();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSizes.screenPadding,
          AppSizes.lg,
          AppSizes.screenPadding,
          AppSizes.xxl,
        ),
        children: <Widget>[
          _Hero(
            profile: profile,
            technician: _technician,
            reputation: _reputation,
            bookings: _bookings,
          ),

          const SizedBox(height: AppSizes.lg),
          _StatusCard(status: status),

          // -------------------------------------------------- availability
          //
          // Vacation days. Only for an active technician: before activation
          // nobody can book them anyway, so "away" would mean nothing.
          if ((profile?.isTechnician ?? false) &&
              profile?.registrationStatus == 'active') ...<Widget>[
            const SizedBox(height: AppSizes.xl),
            const SectionHeader(
              title: 'Availability',
              icon: Icons.beach_access_rounded,
            ),
            const SizedBox(height: AppSizes.md),
            const VacationCard(),
          ],

          // ------------------------------------------------------- details
          if (profile != null) ...<Widget>[
            const SizedBox(height: AppSizes.xl),
            const SectionHeader(
              title: 'Your details',
              icon: Icons.person_outline_rounded,
            ),
            const SizedBox(height: AppSizes.md),
            _Details(profile: profile),
          ],

          // ---------------------------------------------------- everything
          //
          // The rest of the account, as two groups of rows.
          //
          // These used to be two buttons dropped into gaps between cards -
          // Edit between the details table and a note, Sign out alone at the
          // very bottom. Grouped rows say "these are the things you can do
          // here", which is the one sentence the bottom of a profile has to
          // make, and it is where the redesign hung everything the brief asks
          // a profile to reach: addresses, favourites, history, help.
          const SizedBox(height: AppSizes.xl),
          if (profile?.isClient ?? false) ...<Widget>[
            SugoListGroup(
              title: 'Your bookings',
              children: <Widget>[
                SugoListTile(
                  icon: Icons.favorite_border_rounded,
                  title: 'Favourite technicians',
                  subtitle: 'People you have saved on this phone',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TechnicianBrowseScreen(
                        initialFavoritesOnly: true,
                      ),
                    ),
                  ),
                ),
                SugoListTile(
                  icon: Icons.location_on_outlined,
                  title: 'Saved addresses',
                  subtitle: 'Home, work, anywhere you need repairs',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SavedAddressesScreen(),
                    ),
                  ),
                ),
                SugoListTile(
                  icon: Icons.forum_outlined,
                  title: 'Technician community',
                  subtitle: 'Ask a question, read the answers',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        backgroundColor: AppColors.background,
                        body: const SafeArea(
                          child: CommunityFeedView(isClient: true),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSizes.xl),
          ],
          SugoListGroup(
            title: 'Account',
            children: <Widget>[
              // Photo and workshop only - see ProfileSetupScreen for why the
              // name is not editable. Offered once the account is active,
              // because that is when the setup step it reopens exists.
              if (profile?.registrationStatus == 'active')
                SugoListTile(
                  icon: Icons.photo_camera_outlined,
                  title: (profile?.isTechnician ?? false)
                      ? 'Edit photo and workshop'
                      : 'Edit your photo',
                  subtitle: 'Your name is fixed to your verified ID',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ProfileSetupScreen.edit(),
                    ),
                  ),
                ),
              SugoListTile(
                icon: Icons.notifications_none_rounded,
                title: 'Notifications',
                subtitle: 'What you are told about, and where',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const NotificationSettingsScreen(),
                  ),
                ),
              ),
              SugoListTile(
                icon: Icons.help_outline_rounded,
                title: 'Help & support',
                subtitle: 'Answers, and how to reach a person',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const HelpScreen()),
                ),
              ),
              SugoListTile(
                icon: Icons.settings_outlined,
                title: 'Settings',
                subtitle: 'Privacy, location, about SUGO',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen(),
                  ),
                ),
              ),
              SugoListTile(
                icon: Icons.logout_rounded,
                title: 'Sign out',
                subtitle: 'You will need your password to return',
                destructive: true,
                onTap: () => _confirmSignOut(context),
              ),
            ],
          ),

          const SizedBox(height: AppSizes.lg),
          const _ReadOnlyNote(),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final bool out = await showSugoConfirmDialog(
      context: context,
      icon: Icons.logout_rounded,
      title: 'Sign out?',
      message: 'You will need your email and password to sign in again.',
      confirmLabel: 'Sign out',
      cancelLabel: 'Stay',
      destructive: true,
    );

    if (out && context.mounted) {
      await context.read<AuthController>().signOut();
    }
  }
}

/// The identity panel: the cover, the avatar, the name, badges and figures.
///
/// Layout and cover live in [ProfileCoverHeader]; this decides what this
/// account's badges and figures say. Since 2026-11-16 the figures sit inside
/// the panel for both roles - a technician's rating, jobs and community
/// points (they were three tiles under it), and a client's bookings, which
/// the profile never showed, so a client's page was a name and nothing else.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.profile,
    required this.technician,
    required this.reputation,
    required this.bookings,
  });

  final SessionProfile? profile;
  final Technician? technician;
  final ({int points, int helpfulVotes, int answers})? reputation;
  final ClientBookingStats? bookings;

  @override
  Widget build(BuildContext context) {
    final bool isTechnician = profile?.isTechnician ?? false;
    final DateTime? joined =
        profile?.onboardingCompletedAt ?? profile?.roleChosenAt;

    return ProfileCoverHeader(
      name: profile?.displayName ?? 'SUGO user',
      avatarUrl: profile?.avatarUrl,
      verified: isTechnician && (profile?.isVerified ?? false),
      style: isTechnician ? SugoCoverStyle.technician : SugoCoverStyle.client,
      roleLabel: isTechnician ? 'Technician' : 'Client',
      // Photo and workshop only - the name is fixed to the verified ID. The
      // step it reopens exists once the account is active.
      onEdit: profile?.registrationStatus == 'active'
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ProfileSetupScreen.edit(),
              ),
            )
          : null,
      badges: <Widget>[
        if (isTechnician && technician != null)
          ProfileBadge(
            icon: Icons.workspace_premium_rounded,
            label: technician!.tier.label,
            // Elite is the only tier that gets the accent. A badge every
            // technician wears is not a badge.
            tone: technician!.tier == TechnicianTier.elite
                ? ProfileBadgeTone.accent
                : ProfileBadgeTone.brand,
          ),
        if (profile?.isVerified ?? false)
          const ProfileBadge(
            icon: Icons.verified_rounded,
            label: 'ID verified',
            tone: ProfileBadgeTone.success,
          ),
        if (!isTechnician && joined != null)
          ProfileBadge(
            icon: Icons.calendar_month_rounded,
            label: 'Since ${DateFormat('MMM yyyy').format(joined)}',
          ),
      ],
      stats: isTechnician ? _technicianStats() : _clientStats(),
    );
  }

  List<ProfileStat> _technicianStats() {
    final double rating = technician?.rating ?? 0;
    final int? jobs = technician?.totalJobs;
    final int? points = reputation?.points;
    return <ProfileStat>[
      ProfileStat(
        label: 'Rating',
        // Not rolled up: a rating rolling from 0 to 4.8 reads as a slot
        // machine, and it is an average rather than a tally.
        value: rating > 0 ? rating.toStringAsFixed(1) : '—',
        icon: Icons.star_rounded,
        color: AppColors.accent,
      ),
      ProfileStat(
        label: 'Jobs done',
        value: jobs == null ? '—' : '$jobs',
        count: jobs,
        icon: Icons.task_alt_rounded,
        color: AppColors.success,
      ),
      ProfileStat(
        label: 'Points',
        value: points == null ? '—' : '$points',
        count: points,
        icon: Icons.auto_awesome_rounded,
        color: AppColors.accentDark,
      ),
    ];
  }

  List<ProfileStat> _clientStats() {
    final ClientBookingStats? b = bookings;
    final int? active = b?.active;
    return <ProfileStat>[
      ProfileStat(
        label: 'Bookings',
        value: b == null ? '—' : '${b.total}',
        count: b?.total,
        icon: Icons.receipt_long_rounded,
      ),
      ProfileStat(
        label: 'Completed',
        value: b == null ? '—' : '${b.completed}',
        count: b?.completed,
        icon: Icons.task_alt_rounded,
        color: AppColors.success,
      ),
      ProfileStat(
        label: 'In progress',
        value: active == null ? '—' : '$active',
        count: active,
        icon: Icons.bolt_rounded,
        color: AppColors.accentDark,
      ),
    ];
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});

  final RegistrationStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: status.tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSizes.panelRadius),
        border: Border.all(color: status.tone.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: status.tone.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppSizes.radius),
            ),
            child: Icon(status.icon, size: 18, color: status.tone),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  status.label,
                  style: AppTextStyles.titleSmall.copyWith(color: status.tone),
                ),
                const SizedBox(height: 2),
                Text(status.blurb, style: AppTextStyles.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.profile});

  final SessionProfile profile;

  @override
  Widget build(BuildContext context) {
    final List<(IconData, String, String)> rows = <(IconData, String, String)>[
      (
        Icons.phone_rounded,
        'Phone',
        profile.phone?.trim().isNotEmpty ?? false ? profile.phone! : 'Not set',
      ),
      if (profile.isTechnician)
        (
          Icons.verified_user_rounded,
          'Cleared to work',
          profile.canWork ? 'Yes' : 'Not yet — awaiting approval',
        ),
      if (profile.isTechnician && profile.specialization.isNotEmpty)
        (
          Icons.build_rounded,
          'Specialises in',
          profile.specialization.join(', '),
        ),
      (
        Icons.badge_rounded,
        'Identity',
        profile.hasSubmittedId ? 'Submitted' : 'Not submitted',
      ),
    ];

    return SugoCard(
      padding: EdgeInsets.zero,
      elevation: SugoElevation.sm,
      child: Column(
        children: <Widget>[
          for (int i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.lg,
                vertical: AppSizes.md + 2,
              ),
              decoration: BoxDecoration(
                border: i == rows.length - 1
                    ? null
                    : const Border(
                        bottom: BorderSide(color: AppColors.divider),
                      ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // A glyph per row. On a four-row table the icons are what
                  // let the eye jump to the line it wants instead of reading
                  // every label.
                  Icon(rows[i].$1, size: 16, color: AppColors.hint),
                  const SizedBox(width: AppSizes.sm + 2),
                  Expanded(
                    child: Text(
                      rows[i].$2,
                      style: AppTextStyles.micro.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    flex: 2,
                    child: Text(
                      rows[i].$3,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        height: 1.35,
                      ),
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

class _ReadOnlyNote extends StatelessWidget {
  const _ReadOnlyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md + 2),
      decoration: BoxDecoration(
        color: AppColors.primarySofter,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(color: AppColors.primarySoft),
        boxShadow: AppElevation.flat,
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.primary),
          SizedBox(width: AppSizes.sm + 2),
          Expanded(
            child: Text(
              'Verification and account status are set by the SUGO review team '
              'and cannot be changed here. Your name matches your verified ID, '
              'so it cannot be changed either.',
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
