import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/services/notification_router.dart';
import '../../../core/theme/app_elevation.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/widgets/sugo_avatar.dart';
import '../../../core/widgets/sugo_bottom_nav.dart';
import '../../../core/widgets/sugo_empty_state.dart';
import '../../../core/widgets/sugo_skeleton.dart';
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
import '../../bookings/widgets/rate_job_sheet.dart';
import '../../rb_cars/models/job.dart';
import '../../rb_cars/models/job_enums.dart';
import '../../rb_cars/models/job_party.dart';
import '../../rb_cars/models/match_result.dart';
import '../../rb_cars/models/technician.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../models/time_off.dart';
import '../providers/technician_dashboard_provider.dart';
import '../widgets/active_job_card.dart';
import '../widgets/availability_hero_card.dart';
import '../widgets/incoming_offer_card.dart';
import '../widgets/job_request_details_sheet.dart';
import '../widgets/recent_reviews_strip.dart';
import '../widgets/technician_stat_cards.dart';
import '../widgets/vacation_card.dart';
import '../../tracking/models/job_tracking.dart';
import '../../tracking/screens/home_visit_trip_screen.dart';
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
      case 'collection':
        UiFeedback.showInfo(
          context,
          'Your client is on the way to collect their unit.',
          actionLabel: 'View',
          onAction: () => _openDeliveryFor(jobId),
        );
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

  void _onProviderChanged() => unawaited(_syncOfferBadges());

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
      // The client coming to collect, or late on the way: their trip is on
      // the delivery screen, not the job summary.
      case 'collection' || 'client_delay':
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

  Future<void> _completeJob(
    TechnicianDashboardProvider provider,
    Job job,
  ) async {
    final CompletionAnswers? answers = await CompleteJobSheet.show(
      context,
      job,
    );
    if (answers == null || !mounted) return;

    final bool completed = await provider.completeJob(
      job.id,
      diagnosisCorrect: answers.diagnosisCorrect,
      reroutedMidJob: answers.reroutedMidJob,
    );
    if (!mounted) return;
    _flash(provider);

    // The client is rated at the moment the work ends, while it is fresh -
    // the sheet opens straight after "complete" instead of waiting for the
    // technician to find the job again in their history. Dismissing it is
    // fine: the Jobs list still offers "Rate" on the card.
    if (completed) await _rateClient(job);
  }

  Future<void> _rateClient(Job job) async {
    final Map<String, JobParty> parties = await RbCarsService().jobParties();
    if (!mounted) return;
    final JobParty? party = parties[job.id];
    // Already rated - possible if the job was closed on another device.
    if (party?.myRating != null) return;

    final bool saved = await RateJobSheet.showForClient(
      context,
      jobId: job.id,
      clientId: job.clientId,
      clientName: party?.clientLabel ?? 'your client',
    );
    if (saved && mounted) {
      UiFeedback.showSuccess(context, 'Thanks - your rating was saved.');
    }
  }

  /// Switches an on-site job to a shop pickup, once the technician has seen it.
  ///
  /// Confirmed first because it is visible to the client immediately: their
  /// booking changes from "someone is coming to fix it" to "someone is taking
  /// it away", and a tracking map appears. That is not something to trigger on
  /// a stray tap.
  Future<void> _markNeedsShop(
    TechnicianDashboardProvider provider,
    Job job,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Take it to the shop?'),
        content: const Text(
          'This tells the client the repair cannot be finished at their home '
          'and that you are collecting the unit. They will see a live map of '
          'the pickup. You cannot switch it back.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep on site'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Collect it'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _respond(provider, () => provider.markNeedsShop(job.id));
  }

  /// Opens the trip screen: the drive to a home visit, or the pickup and
  /// delivery of a rerouted job.
  ///
  /// Reloading on return keeps the dashboard in step with any stage change
  /// made over there.
  Future<void> _openTrip(Job job) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => job.servicePath == ServicePath.homeService
            ? HomeVisitTripScreen(job: job)
            : TechnicianDeliveryScreen(job: job),
      ),
    );
    if (!mounted) return;
    await context.read<TechnicianDashboardProvider>().refresh();
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
      body: SafeArea(
        bottom: false,
        // Only the home tab wraps in the provider's RefreshIndicator; the
        // other tabs own their own loading and pull-to-refresh.
        child: switch (_tab) {
          TechnicianTab.home => RefreshIndicator(
            // Badges refresh here too. They were loaded once in `initState`
            // and again only after the inbox closed, so anything arriving
            // while the technician was on another tab left a stale count
            // until the app restarted.
            onRefresh: () async {
              await Future.wait(<Future<void>>[
                provider.refresh(),
                _loadBadges(),
              ]);
            },
            child: _body(provider),
          ),
          TechnicianTab.jobs => const BookingsListView(
            role: BookingsRole.technician,
          ),
          TechnicianTab.community => const CommunityFeedView(isClient: false),
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
      // dashboard, so the stat row and the offer list do not jump into place
      // when the provider resolves.
      return const Padding(
        padding: EdgeInsets.fromLTRB(
          AppSizes.screenPadding,
          AppSizes.lg,
          AppSizes.screenPadding,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SugoSkeletonRow(),
            SizedBox(height: AppSizes.lg),
            SugoSkeletonList(count: 2, showAvatar: false),
          ],
        ),
      );
    }

    final Technician? technician = provider.technician;

    if (technician == null) {
      return ListView(
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
      );
    }

    final Job? active = provider.currentJob;

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSizes.xxl),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.screenPadding,
          ),
          child: _TopBar(
            technician: technician,
            awayUntil: provider.awayUntil,
            unread: _unread,
            unreadNotifications: _unreadNotifications,
            onOpenInbox: _openInbox,
            onOpenNotifications: _openNotifications,
          ),
        ),
        const SizedBox(height: AppSizes.lg),

        // Can clients book me today? Navy while taking jobs, orange while on
        // vacation - with the actions that change it right there.
        //
        // Then, since the Dispatch redesign, the order of urgency: requests
        // waiting for an answer first, the job in hand next, and the week's
        // numbers after both. The stats used to sit above the requests, which
        // put the one thing a technician must answer quickly below the fold.
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.screenPadding,
          ),
          child: AvailabilityHeroCard(
            vacation: provider.currentVacation,
            onSetVacation: () => _setVacation(provider),
            onEndVacation: () => _endVacation(provider),
            onEditDates: () => _editVacation(provider),
          ),
        ),

        const SizedBox(height: AppSizes.xl),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.screenPadding,
          ),
          child: SectionHeader(
            title: 'Incoming job requests',
            subtitle: provider.awayUntil != null
                ? 'Paused while you are on vacation'
                : null,
            action: provider.offers.isEmpty
                ? null
                : '${provider.offers.length} waiting',
          ),
        ),
        const SizedBox(height: AppSizes.md),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.screenPadding,
          ),
          child: provider.offers.isEmpty
              ? SugoEmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'No requests right now',
                  message: provider.awayUntil != null
                      ? 'Requests resume once you are back.'
                      : 'New requests appear here when a client chooses you '
                            'for a job.',
                  compact: true,
                )
              : Column(
                  children: provider.offers
                      .map(
                        (MatchResult match) => IncomingOfferCard(
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
                      )
                      .toList(growable: false),
                ),
        ),

        const SizedBox(height: AppSizes.xl),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSizes.screenPadding),
          child: SectionHeader(title: 'Active job'),
        ),
        const SizedBox(height: AppSizes.md),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.screenPadding,
          ),
          child: active == null
              ? const SugoEmptyState(
                  icon: Icons.handyman_outlined,
                  title: 'Nothing in progress',
                  message:
                      'Accept a request above and it will show up here with '
                      'the client location and a completion action.',
                  compact: true,
                )
              : ActiveJobCard(
                  job: active,
                  isBusy: provider.isBusy,
                  isCompleting: provider.isDoing(
                    TechnicianAction.complete,
                    active.id,
                  ),
                  onComplete: () => _completeJob(provider, active),
                  onTrack: () => _openTrip(active),
                  onNeedsShop: () => _markNeedsShop(provider, active),
                ),
        ),

        const SizedBox(height: AppSizes.xl),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSizes.screenPadding),
          child: SectionHeader(title: 'This week'),
        ),
        const SizedBox(height: AppSizes.md),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.screenPadding,
          ),
          child: TechnicianStatCardsSection(provider: provider),
        ),

        const SizedBox(height: AppSizes.xl),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSizes.screenPadding),
          child: SectionHeader(title: 'Recent reviews'),
        ),
        const SizedBox(height: AppSizes.md),
        RecentReviewsStrip(outcomes: provider.ratedOutcomes),
      ],
    );
  }
}

/// Split out so the stat row can read the provider without the whole screen
/// rebuilding when only a counter changes.
class TechnicianStatCardsSection extends StatelessWidget {
  const TechnicianStatCardsSection({super.key, required this.provider});

  final TechnicianDashboardProvider provider;

  @override
  Widget build(BuildContext context) {
    final Technician? technician = provider.technician;
    if (technician == null) return const SizedBox.shrink();

    return TechnicianStatCards(
      technician: technician,
      earningsToday: provider.estimatedEarningsToday,
      jobsThisWeek: provider.jobsThisWeek,
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.technician,
    required this.awayUntil,
    required this.unread,
    required this.unreadNotifications,
    required this.onOpenInbox,
    required this.onOpenNotifications,
  });

  final Technician technician;

  /// Last day of today's vacation, or null when they are taking jobs.
  final DateTime? awayUntil;

  /// Unread job messages. The Chat tab became Community, so the inbox and its
  /// badge live in this header now.
  final int unread;

  /// Unread items in the notification centre - new requests, and what a
  /// client has decided about a job in hand.
  final int unreadNotifications;

  final VoidCallback onOpenInbox;
  final VoidCallback onOpenNotifications;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            // The availability ring, in the same two colours as the card
            // below it: blue while they can be booked, orange while away.
            SugoAvatar(
              name: technician.displayName,
              imageUrl: technician.avatarUrl,
              size: AppSizes.avatarMd,
              verified: technician.isVerified,
              ringColor: awayUntil == null ? AppColors.primary : AppColors.accent,
            ),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    technician.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.title.copyWith(fontSize: 16),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    technician.headline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.micro,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            // Messages and notifications. Sign-out was removed from this
            // header at the client's request, and it belongs on the Profile
            // tab anyway - sitting one slip away from the inbox is a poor
            // place for the one action that ends the session.
            _HeaderAction(
              icon: Icons.mail_outline_rounded,
              tooltip: 'Messages',
              badgeCount: unread,
              onTap: onOpenInbox,
            ),
            const SizedBox(width: AppSizes.sm),
            // The bell the technician side never had. Push told them a
            // request had arrived and then it was gone - a notification
            // swiped away on a lock screen was unrecoverable, and the only
            // way to find out what had come in was to scroll the dashboard.
            _HeaderAction(
              icon: Icons.notifications_none_rounded,
              tooltip: 'Notifications',
              badgeCount: unreadNotifications,
              onTap: onOpenNotifications,
            ),
          ],
        ),
      ],
    );
  }
}

/// A round header action, optionally carrying an unread count.
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final int badgeCount;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                  boxShadow: AppElevation.sm,
                ),
                child: Icon(icon, size: 18, color: AppColors.textPrimary),
              ),
              if (badgeCount > 0)
                Positioned(
                  top: -3,
                  right: -3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    constraints: const BoxConstraints(minWidth: 18),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                      border: Border.all(color: AppColors.surface, width: 1.5),
                    ),
                    child: Text(
                      badgeCount > 9 ? '9+' : '$badgeCount',
                      textAlign: TextAlign.center,
                      // Ink on the orange: white on it is 2.1:1.
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.onAccent,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
