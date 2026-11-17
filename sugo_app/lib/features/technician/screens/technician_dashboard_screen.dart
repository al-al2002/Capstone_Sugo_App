import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/services/notification_router.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/widgets/sugo_bottom_nav.dart';
import '../../../core/widgets/sugo_empty_state.dart';
import '../../../core/widgets/sugo_skeleton.dart';
import '../../../core/widgets/sugo_staggered_column.dart';
import '../../community/screens/community_feed_view.dart';
import '../../community/services/community_service.dart';
import '../../bookings/screens/bookings_list_view.dart';
import '../../bookings/screens/job_detail_screen.dart';
import '../../chat/screens/chat_thread_screen.dart';
import '../../chat/screens/conversation_list_view.dart';
import '../../chat/services/chat_service.dart';
import '../../notifications/screens/notifications_screen.dart';
import '../../notifications/services/notification_feed_service.dart';
import '../../profile/screens/profile_view.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_app_bar.dart';
import '../../rb_cars/models/job.dart';
import '../../rb_cars/models/match_result.dart';
import '../../rb_cars/models/technician.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../models/time_off.dart';
import '../providers/technician_dashboard_provider.dart';
import '../widgets/active_job_card.dart';
import '../widgets/incoming_offer_card.dart';
import '../widgets/job_request_details_sheet.dart';
import '../widgets/recent_reviews_strip.dart';
import '../widgets/technician_home_header.dart';
import '../widgets/urgent_offer_alert.dart';
import '../widgets/trust_badge_progress_card.dart';
import '../widgets/vacation_card.dart';
import '../../tracking/models/job_tracking.dart';
import '../../tracking/screens/technician_delivery_screen.dart';
import '../../tracking/services/tracking_service.dart';
import '../../tracking/widgets/delay_alert_dialog.dart';

/// The technician's landing screen.
///
/// Entirely separate from `ClientDashboardScreen`, not a variant of it. The two
/// roles want different things at a glance: a client wants to find someone, a
/// technician wants to know what work is waiting and whether they are earning.
/// Sharing one screen with `if (isTechnician)` branches would mean every future
/// change to either side risks breaking the other.
///
/// Reached only through `SessionController.destination`, which routes here on
/// `role = 'technician'` and `is_verified = true`.
class TechnicianDashboardScreen extends StatelessWidget {
  const TechnicianDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<TechnicianDashboardProvider>(
      create: (_) => TechnicianDashboardProvider()..load(),
      child: const _TechnicianDashboardView(),
    );
  }
}

/// Technician tabs. A different set from the client's, on purpose.
///
/// `earnings` was dropped first: nothing backed it. There is no payments table
/// in the schema, so the figure on the home card is an *estimate* derived from
/// tier rates (see `TechnicianDashboardProvider`), and a whole tab of
/// estimates would have read as real money.
///
/// `chat` then became `community`. The cross-job inbox it opened is still
/// reachable from the envelope in the header, and a conversation about a
/// specific repair was always better reached from that repair. Community is
/// the thing a technician can do here that nobody else can - answering builds
/// the reputation shown on their profile.
///
/// Note there is no compose tab and no "+" button: a technician posts neither
/// jobs nor questions.
enum TechnicianTab { home, jobs, community, profile }

class _TechnicianDashboardView extends StatefulWidget {
  const _TechnicianDashboardView();

  @override
  State<_TechnicianDashboardView> createState() =>
      _TechnicianDashboardViewState();
}

class _TechnicianDashboardViewState extends State<_TechnicianDashboardView> {
  TechnicianTab _tab = TechnicianTab.home;

  final ChatService _chat = ChatService();
  final CommunityService _community = CommunityService();
  final NotificationFeedService _notifications = NotificationFeedService(
    audience: NotificationAudience.technician,
  );

  /// Unread messages across every thread, for the nav badge.
  ///
  /// Loaded here rather than inside the chat tab because the badge has to be
  /// right *before* anyone opens that tab - that is the whole point of it.
  int _unread = 0;

  /// Unseen Community activity, for the Community tab's badge.
  ///
  /// For a technician this means *new unanswered questions* - work waiting -
  /// not replies. See `community_unread_count()` in migration
  /// 20260921000004 for why the two roles count different things.
  int _communityUnread = 0;

  /// Unread items in the notification centre, for the bell.
  int _unreadNotifications = 0;

  /// Unread messages on each *offered* job, keyed by job id.
  ///
  /// Counted separately from [_unread] because these threads are not in the
  /// conversation list at all - see `ChatService.unreadForJob`. Without this
  /// a client's "can you do it for ₱2,000?" would sit unanswered behind a
  /// button with nothing on it.
  final Map<String, int> _offerUnread = <String, int>{};

  /// The offer set the counts above were fetched for, so the listener below
  /// refetches when the offers change and not on every notification.
  Set<String> _offerUnreadFor = <String>{};

  late final TechnicianDashboardProvider _provider = context
      .read<TechnicianDashboardProvider>();

  @override
  void initState() {
    super.initState();
    _loadBadges();
    _provider.addListener(_onProviderChanged);
    NotificationRouter.pending.addListener(_onNotificationTap);
    NotificationRouter.arrived.addListener(_onPushArrived);
    // A tap that launched the app is already waiting by the time this exists.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onNotificationTap());
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderChanged);
    NotificationRouter.pending.removeListener(_onNotificationTap);
    NotificationRouter.arrived.removeListener(_onPushArrived);
    super.dispose();
  }

  /// A push that landed while the app was open, about a client coming to
  /// collect (2026-09-29). Android shows nothing for its own foreground app,
  /// so this is where the technician hears it.
  ///
  /// * The client set off: a note, with a way to their live position.
  /// * The client is running late: the same "Running late" pop-up the client
  ///   gets about a technician, once per trip.
  Future<void> _onPushArrived() async {
    final NotificationTap? push = NotificationRouter.arrived.value;
    final String? jobId = push?.jobId;
    if (push == null || jobId == null || !mounted) return;

    switch (push.type) {
      // An urgent request: fetch it, and the alert above takes the screen.
      case 'urgent_offer':
        await _provider.refresh();
        await _maybeAlertUrgent();
      case 'urgent_missed':
        UiFeedback.showInfo(
          context,
          'You missed an urgent request - it went to another technician.',
        );
        await _provider.refresh();
      case 'collection':
        UiFeedback.showInfo(
          context,
          'Your client is on the way to your shop.',
          actionLabel: 'View',
          onAction: () => _openDeliveryFor(jobId),
        );
      // 2026-11-17: the client almost there, and arrived.
      case 'client_arriving':
        UiFeedback.showInfo(
          context,
          'Your client is almost at your shop.',
          actionLabel: 'View',
          onAction: () => _openDeliveryFor(jobId),
        );
      case 'client_arrived':
        UiFeedback.showSuccess(
          context,
          'Your client has arrived at your shop.',
          actionLabel: 'View',
          onAction: () => _openDeliveryFor(jobId),
        );
      // The client cancelled the request this technician was looking at.
      case 'request_cancelled':
        UiFeedback.showInfo(context, 'A client cancelled their request.');
        await _provider.refresh();
      case 'client_delay':
        final JobTracking? trip = await TrackingService()
            .fetch(jobId)
            .catchError((Object _) => null);
        if (trip == null || !mounted) return;
        final bool look = await maybeShowDelayAlert(
          context,
          trip,
          clientTrip: true,
          offerTracking: true,
        );
        if (look && mounted) await _openDeliveryFor(jobId);
    }
  }

  /// The pickup-and-delivery screen for [jobId], where the client's trip is
  /// drawn.
  Future<void> _openDeliveryFor(String jobId) async {
    final Job? job = await RbCarsService()
        .jobById(jobId)
        .catchError((Object _) => null);
    if (job == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TechnicianDeliveryScreen(job: job),
      ),
    );
    if (mounted) await context.read<TechnicianDashboardProvider>().refresh();
  }

  void _onProviderChanged() {
    unawaited(_syncOfferBadges());
    unawaited(_maybeAlertUrgent());
  }

  /// Urgent requests already shown in the full-screen alert, so each rings
  /// once - not again on every refresh.
  final Set<String> _urgentAlerted = <String>{};
  bool _urgentAlertOpen = false;

  /// The in-app "hard notify" (2026-11-17): a live urgent request this
  /// technician has not yet been alerted to takes the whole screen, with its
  /// five minutes running. Runs on every change of the offers, so it fires
  /// whether the request arrived by push or was found on a refresh - a push
  /// can be missed, the dashboard cannot.
  Future<void> _maybeAlertUrgent() async {
    if (!mounted || _urgentAlertOpen) return;
    final DateTime now = DateTime.now();
    MatchResult? urgent;
    for (final MatchResult m in _provider.offers) {
      final DateTime? deadline = m.urgentDeadline;
      if (deadline != null &&
          deadline.isAfter(now) &&
          !_urgentAlerted.contains(m.id)) {
        urgent = m;
        break;
      }
    }
    if (urgent == null) return;

    _urgentAlerted.add(urgent.id);
    _urgentAlertOpen = true;
    final UrgentOfferChoice? choice = await showUrgentOfferAlert(
      context,
      urgent,
    );
    _urgentAlertOpen = false;
    if (!mounted) return;

    final MatchResult picked = urgent;
    switch (choice) {
      case UrgentOfferChoice.accept:
        await _respond(_provider, () => _provider.acceptOffer(picked.id));
      case UrgentOfferChoice.decline:
        await _respond(_provider, () => _provider.declineOffer(picked.id));
      case UrgentOfferChoice.details:
        showJobRequestDetails(
          context,
          match: picked,
          isBusy: _provider.isBusy,
          onAccept: () =>
              _respond(_provider, () => _provider.acceptOffer(picked.id)),
          onDecline: () =>
              _respond(_provider, () => _provider.declineOffer(picked.id)),
          onMessage: () => _openOfferChat(picked),
        );
      case null:
        // Time ran out: it has gone to someone else.
        await _provider.refresh();
    }
  }

  /// Fetches the unread count for every offered job, once per change of set.
  Future<void> _syncOfferBadges() async {
    final Set<String> ids = _provider.offers
        .map((MatchResult match) => match.jobId)
        .toSet();

    if (setEquals(ids, _offerUnreadFor)) return;
    _offerUnreadFor = ids;

    final Map<String, int> counts = <String, int>{};
    for (final String jobId in ids) {
      counts[jobId] = await _chat.unreadForJob(jobId);
    }

    if (!mounted) return;
    setState(() {
      _offerUnread
        ..clear()
        ..addAll(counts);
    });
  }

  /// The negotiation thread on a job that has not been accepted yet.
  ///
  /// The title is "Client", not a name: the job row stays hidden until
  /// acceptance, so the technician genuinely does not know who this is. That
  /// is the deliberate trade - they can discuss the price without being
  /// handed a stranger's identity and address first.
  Future<void> _openOfferChat(MatchResult match) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatThreadScreen(
          jobId: match.jobId,
          title: 'Client',
          subtitle: match.job?.title ?? 'Job request',
        ),
      ),
    );
    if (!mounted) return;

    // Opening the thread marked it read, so the dot has to go.
    final int fresh = await _chat.unreadForJob(match.jobId);
    if (!mounted) return;
    setState(() => _offerUnread[match.jobId] = fresh);
  }

  /// Opens what a tapped notification is about.
  ///
  /// A message opens its chat; a booking brings the Home tab, where the new
  /// request waits to be accepted; anything about a specific job - the client
  /// choosing pickup, the client closing it - opens that job.
  Future<void> _onNotificationTap() async {
    final NotificationTap? tap = NotificationRouter.take();
    if (tap == null || !mounted) return;
    final TechnicianDashboardProvider provider = context
        .read<TechnicianDashboardProvider>();

    switch (tap.type) {
      case 'message':
        final String? jobId = tap.jobId;
        if (jobId == null) return;
        await openChatThread(
          context,
          jobId: jobId,
          title: tap.name ?? 'Messages',
        );
        if (mounted) await _loadBadges();
      case 'booked':
        setState(() => _tab = TechnicianTab.home);
        await provider.refresh();
      // A request that was cancelled (2026-11-17) has no job left to open:
      // the Home tab, refreshed, shows it gone.
      case 'request_cancelled':
        setState(() => _tab = TechnicianTab.home);
        await provider.refresh();
      // A tapped urgent push: straight to the request, alert and clock.
      case 'urgent_offer' || 'urgent_missed':
        setState(() => _tab = TechnicianTab.home);
        await provider.refresh();
        await _maybeAlertUrgent();
      // The client coming to the shop - on the way, late, almost there or
      // arrived: their trip is on the delivery screen, not the job summary.
      case 'collection' ||
          'client_delay' ||
          'client_arriving' ||
          'client_arrived':
        final String? jobId = tap.jobId;
        if (jobId == null) return;
        await _openDeliveryFor(jobId);
      default:
        final String? jobId = tap.jobId;
        if (jobId == null) return;
        final Job? job = await RbCarsService()
            .jobById(jobId)
            .catchError((Object _) => null);
        if (job == null || !mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                JobDetailScreen(job: job, role: BookingsRole.technician),
          ),
        );
        if (mounted) await provider.refresh();
    }
  }

  // ------------------------------------------------------------- vacation

  Future<void> _setVacation(TechnicianDashboardProvider provider) async {
    if (await addVacationFlow(context, service: provider.timeOff)) {
      await provider.refresh();
    }
  }

  Future<void> _endVacation(TechnicianDashboardProvider provider) async {
    final TimeOff? vacation = provider.currentVacation;
    if (vacation == null) return;
    if (await endVacationFlow(
      context,
      service: provider.timeOff,
      period: vacation,
    )) {
      await provider.refresh();
    }
  }

  Future<void> _editVacation(TechnicianDashboardProvider provider) async {
    final TimeOff? vacation = provider.currentVacation;
    if (vacation == null) return;
    if (await editVacationEndFlow(
      context,
      service: provider.timeOff,
      period: vacation,
    )) {
      await provider.refresh();
    }
  }

  /// Both badges together.
  ///
  /// Each service swallows its own failures and returns 0: a badge is
  /// decoration, and it must never put an error over the dashboard.
  Future<void> _loadBadges() async {
    final (int messages, int community, int notifications) = await (
      _chat.unreadTotal(),
      _community.unreadCount(),
      _notifications.unreadCount(),
    ).wait;

    if (!mounted) return;
    setState(() {
      _unread = messages;
      _communityUnread = community;
      _unreadNotifications = notifications;
    });
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const NotificationsScreen(
          audience: NotificationAudience.technician,
        ),
      ),
    );
    if (!mounted) return;
    // Opening an item marks it read, so the bell is stale on return. The
    // dashboard itself is refreshed too: a request tapped from the centre
    // pops straight back here expecting to find the offer card.
    await Future.wait(<Future<void>>[_loadBadges(), _provider.refresh()]);
  }

  List<SugoNavItem> get _navItems => <SugoNavItem>[
    SugoNavItem(
      label: 'Home',
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
    ),
    SugoNavItem(
      label: 'Jobs',
      icon: Icons.work_outline_rounded,
      activeIcon: Icons.work_rounded,
    ),
    SugoNavItem(
      label: 'Community',
      icon: Icons.forum_outlined,
      activeIcon: Icons.forum_rounded,
      showBadge: _communityUnread > 0,
    ),
    SugoNavItem(
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
    ),
  ];

  /// Opens the inbox that used to be a tab.
  ///
  /// Job chat itself is unchanged and still reachable from a job; this is the
  /// cross-job list, which lost its home when Chat became Community.
  Future<void> _openInbox() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: AppColors.background,
          appBar: const SugoAppBar(title: 'Messages'),
          body: const SafeArea(
            child: ConversationListView(
              emptyHint:
                  'Accept a job and your chat with the client opens here.',
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    // Opening a thread marks it read, so the badge is stale on return.
    await _loadBadges();
  }

  void _flash(TechnicianDashboardProvider provider) {
    final String? notice = provider.notice;
    final String? error = provider.error;

    if (error != null) {
      UiFeedback.showError(context, error);
      provider.clearError();
    } else if (notice != null) {
      UiFeedback.showSuccess(context, notice);
      provider.clearNotice();
    }
  }

  /// Opens the active job, where its trip, completion and shop actions are
  /// (moved off this card on 2026-09-29). Reloads on return, since any of
  /// them may have changed the job.
  Future<void> _openJob(Job job) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            JobDetailScreen(job: job, role: BookingsRole.technician),
      ),
    );
    if (mounted) await context.read<TechnicianDashboardProvider>().refresh();
  }

  Future<void> _respond(
    TechnicianDashboardProvider provider,
    Future<bool> Function() action,
  ) async {
    await action();
    if (!mounted) return;
    _flash(provider);
  }

  @override
  Widget build(BuildContext context) {
    final TechnicianDashboardProvider provider = context
        .watch<TechnicianDashboardProvider>();

    return Scaffold(
      backgroundColor: AppColors.background,
      // The home tab runs under the status bar since 2026-11-16: its header
      // is the navy cover and pads itself by the inset, with white status-bar
      // icons. The other tabs keep their SafeArea.
      body: _tab == TechnicianTab.home
          ? AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle.light,
              // Only the home tab wraps in the provider's RefreshIndicator;
              // the other tabs own their own loading and pull-to-refresh.
              child: RefreshIndicator(
                // Below the status bar, so the spinner is not drawn under
                // the clock.
                edgeOffset: MediaQuery.paddingOf(context).top,
                // Badges refresh here too. They were loaded once in
                // `initState` and again only after the inbox closed, so
                // anything arriving while the technician was on another tab
                // left a stale count until the app restarted.
                onRefresh: () async {
                  await Future.wait(<Future<void>>[
                    provider.refresh(),
                    _loadBadges(),
                  ]);
                },
                child: _body(provider),
              ),
            )
          : SafeArea(
              bottom: false,
              child: switch (_tab) {
                TechnicianTab.home => const SizedBox.shrink(),
                TechnicianTab.jobs => const BookingsListView(
                  role: BookingsRole.technician,
                ),
                TechnicianTab.community => const CommunityFeedView(
                  isClient: false,
                ),
                TechnicianTab.profile => const ProfileView(),
              },
            ),
      bottomNavigationBar: SugoBottomNav(
        items: _navItems,
        currentIndex: _tab.index,
        // No compose button. A technician has no repair to post, and they
        // cannot ask a community question either - so the bar spreads four
        // tabs evenly rather than leaving a gap where the client's "+" sits.
        onChanged: (int index) {
          final TechnicianTab next = TechnicianTab.values[index];
          setState(() => _tab = next);

          // Opening Community is what marks it read.
          if (next == TechnicianTab.community) {
            _community.markSeen().then((_) {
              if (mounted) setState(() => _communityUnread = 0);
            });
          }
        },
      ),
    );
  }

  Widget _body(TechnicianDashboardProvider provider) {
    if (provider.isLoading && provider.technician == null) {
      // Skeletons rather than a centred spinner: they hold the shape of the
      // dashboard, so the header and the offer list do not jump into place
      // when the provider resolves.
      return const SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSizes.screenPadding,
            AppSizes.lg,
            AppSizes.screenPadding,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SugoSkeleton(height: 280, radius: AppSizes.panelRadius),
              SizedBox(height: AppSizes.lg),
              SugoSkeletonList(count: 2, showAvatar: false),
            ],
          ),
        ),
      );
    }

    final Technician? technician = provider.technician;

    if (technician == null) {
      return SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.all(AppSizes.screenPadding),
          children: <Widget>[
            const SizedBox(height: AppSizes.xxl),
            SugoEmptyState.error(
              title: 'Could not load your profile',
              message:
                  provider.error ?? 'Could not load your technician profile.',
              onAction: provider.refresh,
            ),
          ],
        ),
      );
    }

    final Job? active = provider.currentJob;

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSizes.xxl),
      children: <Widget>[
        // Who and what's new, can clients book me, how is my week - one
        // panel on the dusk cover (2026-11-16). The availability card and
        // the "This week" figures used to be two separate blocks.
        TechnicianHomeHeader(
          technician: technician,
          vacation: provider.currentVacation,
          unreadMessages: _unread,
          unreadNotifications: _unreadNotifications,
          onOpenInbox: _openInbox,
          onOpenNotifications: _openNotifications,
          onSetVacation: () => _setVacation(provider),
          onEndVacation: () => _endVacation(provider),
          onEditDates: () => _editVacation(provider),
          earningsToday: provider.estimatedEarningsToday,
          jobsThisWeek: provider.jobsThisWeek,
          topInset: MediaQuery.paddingOf(context).top,
        ),

        // Then the order of urgency: requests waiting for an answer, the job
        // in hand, the trust badge. Dealt in once, top to bottom.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSizes.screenPadding,
            AppSizes.xl,
            AppSizes.screenPadding,
            0,
          ),
          child: SugoStaggeredColumn(
            children: <Widget>[
              SectionHeader(
                title: 'Job requests',
                icon: Icons.inbox_rounded,
                subtitle: provider.awayUntil != null
                    ? 'Paused while you are on vacation'
                    : null,
                action: provider.offers.isEmpty
                    ? null
                    : '${provider.offers.length} waiting',
              ),
              const SizedBox(height: AppSizes.md),
              if (provider.offers.isEmpty)
                SugoEmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'No requests right now',
                  message: provider.awayUntil != null
                      ? 'Requests resume once you are back.'
                      : 'New requests appear here when a client chooses you '
                            'for a job.',
                  compact: true,
                )
              else
                for (final MatchResult match in provider.offers)
                  IncomingOfferCard(
                    match: match,
                    isBusy: provider.isBusy,
                    isAccepting: provider.isDoing(
                      TechnicianAction.accept,
                      match.id,
                    ),
                    unreadMessages: _offerUnread[match.jobId] ?? 0,
                    onAccept: () => _respond(
                      provider,
                      () => provider.acceptOffer(match.id),
                    ),
                    onDecline: () => _respond(
                      provider,
                      () => provider.declineOffer(match.id),
                    ),
                    onViewDetails: () => showJobRequestDetails(
                      context,
                      match: match,
                      isBusy: provider.isBusy,
                      onAccept: () => _respond(
                        provider,
                        () => provider.acceptOffer(match.id),
                      ),
                      onDecline: () => _respond(
                        provider,
                        () => provider.declineOffer(match.id),
                      ),
                      onMessage: () => _openOfferChat(match),
                    ),
                    onMessage: () => _openOfferChat(match),
                  ),

              const SizedBox(height: AppSizes.xl),
              const SectionHeader(
                title: 'Active job',
                icon: Icons.handyman_rounded,
              ),
              const SizedBox(height: AppSizes.md),
              if (active == null)
                const SugoEmptyState(
                  icon: Icons.handyman_outlined,
                  title: 'Nothing in progress',
                  message:
                      'Accept a request above and it will show up here. Open '
                      'it for the route, the trip and the completion.',
                  compact: true,
                )
              else
                ActiveJobCard(job: active, onView: () => _openJob(active)),

              // The Progressive Trust Badge and the path to the next rung.
              // After the work: requests and the active job are what the
              // technician opens the app for.
              if (provider.trustBadge != null) ...<Widget>[
                const SizedBox(height: AppSizes.xl),
                const SectionHeader(
                  title: 'Trust badge',
                  icon: Icons.verified_user_rounded,
                ),
                const SizedBox(height: AppSizes.md),
                TrustBadgeProgressCard(progress: provider.trustBadge!),
              ],

              const SizedBox(height: AppSizes.xl),
              const SectionHeader(
                title: 'Recent reviews',
                icon: Icons.reviews_rounded,
              ),
              const SizedBox(height: AppSizes.md),
            ],
          ),
        ),
        RecentReviewsStrip(outcomes: provider.ratedOutcomes),
      ],
    );
  }
}
