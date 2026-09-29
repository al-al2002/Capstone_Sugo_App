import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/services/notification_router.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/session/session_state.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/widgets/sugo_app_bar.dart';
import '../../../core/widgets/sugo_bottom_nav.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_delete_animation.dart';
import '../../../core/widgets/sugo_dialog.dart';
import '../../auth/data/models/app_user.dart';
import '../../auth/presentation/controllers/auth_controller.dart';
import '../../bookings/screens/bookings_list_view.dart';
import '../../bookings/screens/job_detail_screen.dart';
import '../../bookings/widgets/rate_job_sheet.dart';
import '../../chat/screens/chat_thread_screen.dart';
import '../../chat/screens/conversation_list_view.dart';
import '../../chat/services/chat_service.dart';
import '../../community/screens/community_feed_view.dart';
import '../../community/services/community_service.dart';
import '../../notifications/screens/notifications_screen.dart';
import '../../notifications/services/notification_feed_service.dart';
import '../../onboarding/models/client_onboarding_models.dart';
import '../../onboarding/services/client_registration_service.dart';
import '../../profile/screens/profile_view.dart';
import '../../rb_cars/models/device_category.dart';
import '../../rb_cars/models/job.dart';
import '../../rb_cars/models/job_enums.dart';
import '../../rb_cars/models/job_party.dart';
import '../../rb_cars/models/job_technician.dart';
import '../../rb_cars/models/technician.dart';
import '../../rb_cars/providers/technician_directory_provider.dart';
import '../../rb_cars/screens/client_review_screen.dart';
import '../../rb_cars/screens/job_posting_screen.dart';
import '../../rb_cars/screens/technician_browse_screen.dart';
import '../../rb_cars/screens/technician_detail_screen.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../../search/search_screen.dart';
import '../../tracking/models/job_tracking.dart';
import '../../tracking/screens/job_tracking_screen.dart';
import '../../tracking/services/tracking_service.dart';
import '../widgets/active_booking_card.dart';
import '../widgets/home_header.dart';
import '../widgets/home_hero_banner.dart';
import '../widgets/home_hero_slot.dart';
import '../widgets/recommended_technicians.dart';
import '../widgets/service_category_row.dart';

/// The client's landing screen and their navigation hub.
///
/// Entirely separate from `TechnicianDashboardScreen`, not a variant of it. A
/// client wants to find someone and track a booking; a technician wants to see
/// incoming work and whether they are earning. Sharing one screen with
/// `if (isTechnician)` branches would mean every change to either side risks
/// breaking the other.
///
/// Deliberately not part of `rb_cars` either: this is where every feature is
/// reachable from, and RB-CARS is one of the things it launches. It routes into
/// the matching flow but knows nothing about scoring.
///
/// Reached only through `SessionController.destination`, on `role = 'client'`.
class ClientDashboardScreen extends StatefulWidget {
  const ClientDashboardScreen({super.key});

  @override
  State<ClientDashboardScreen> createState() => _ClientDashboardScreenState();
}

/// The client's tabs.
///
/// ## Why Community has the fourth tab and Messages does not
///
/// Both were tried. **Community is a destination** - you go there to browse,
/// read answers and ask something, and a destination needs a tab you can find
/// without remembering where it lives. **Messages is a reply** - it always
/// concerns one booking you already know about, and it is reached from that
/// booking, from a notification, or from the header icon that carries its
/// unread count.
///
/// So the bar is Home · Bookings · **+** · Community · Profile, and the
/// header carries messages and notifications as icons. Five tabs plus the
/// compose button is a crowded bar on a 360dp phone; two header icons cost
/// nothing and keep the compose button, which is the single action this whole
/// app exists for.
enum ClientTab { home, bookings, community, profile }

class _ClientDashboardScreenState extends State<ClientDashboardScreen>
    with WidgetsBindingObserver {
  final TechnicianDirectoryProvider _directory = TechnicianDirectoryProvider();
  final RbCarsService _service = RbCarsService();
  final ClientRegistrationService _profile = ClientRegistrationService();
  final ChatService _chat = ChatService();
  final CommunityService _community = CommunityService();
  final TrackingService _tracking = TrackingService();
  final NotificationFeedService _notifications = NotificationFeedService();

  ClientTab _tab = ClientTab.home;

  /// Unread messages across every thread, for the Messages tab badge.
  int _unreadMessages = 0;

  /// Unread notifications, for the header bell.
  int _unreadNotifications = 0;

  /// Unseen Community activity, for the card on the home feed.
  int _communityUnread = 0;

  List<Job> _jobs = <Job>[];
  bool _jobsLoading = true;

  /// Who is on each job, keyed by job id. Loaded beside the jobs rather than
  /// inside each tile: one request for the whole list, not one per row.
  Map<String, JobTechnician> _technicians = <String, JobTechnician>{};

  /// Live tracking for the job in the hero card, when it is a pickup job that
  /// has actually set off. One lookup, for one job - the rest of the list does
  /// not need it.
  JobTracking? _heroTracking;

  /// The hero job's delete or withdraw is in flight.
  bool _heroBusy = false;

  /// The client's position, for distances on technician cards.
  double? _originLat;
  double? _originLon;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationRouter.pending.addListener(_onNotificationTap);
    // A tap that launched the app is already waiting by the time this exists.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onNotificationTap());
    _directory.load();
    _loadJobs().then((_) => _maybeAskForRating());
    _loadBadges();
    _resolveOrigin();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationRouter.pending.removeListener(_onNotificationTap);
    _directory.dispose();
    super.dispose();
  }

  /// Back from the background - typically from tapping a push notification.
  /// The list and the badges are stale by then, and a job that finished while
  /// the app was closed is the one to ask about.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _loadBadges();
    _loadJobs().then((_) => _maybeAskForRating());
  }

  // ------------------------------------------------------------- loading

  /// Both badge counts plus the community dot.
  ///
  /// Each source swallows its own failures and returns 0: a badge is
  /// decoration, and it must never put an error over the dashboard.
  Future<void> _loadBadges() async {
    final (int messages, int community, int notifications) = await (
      _chat.unreadTotal(),
      _community.unreadCount(),
      _notifications.unreadCount(),
    ).wait;

    if (!mounted) return;
    setState(() {
      _unreadMessages = messages;
      _communityUnread = community;
      _unreadNotifications = notifications;
    });
  }

  Future<void> _loadJobs() async {
    try {
      // Together: the second call swallows its own failures, so a technician
      // lookup that fails still leaves a fully rendered job list.
      final (List<Job> jobs, Map<String, JobTechnician> people) = await (
        _service.myJobs(),
        _service.bookedTechnicians(),
      ).wait;

      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _technicians = people;
        _jobsLoading = false;
      });

      await _loadHeroTracking();

      // The jobs are the fallback origin, and they usually arrive after the
      // first attempt at one. The guard inside keeps this from undoing a GPS
      // fix that landed first.
      await _originFromRecentJob();
    } on RbCarsFailure {
      if (!mounted) return;
      setState(() => _jobsLoading = false);
    }
  }

  /// Reads the tracking row for the hero job, if it travels.
  Future<void> _loadHeroTracking() async {
    final Job? hero = _heroJob;
    if (hero == null || hero.servicePath != ServicePath.pickup) {
      if (mounted && _heroTracking != null) {
        setState(() => _heroTracking = null);
      }
      return;
    }
    try {
      final JobTracking? live = await _tracking.fetch(hero.id);
      if (mounted) setState(() => _heroTracking = live);
    } catch (_) {
      // No tracking is a normal state, not an error worth showing.
    }
  }

  Future<void> _refresh() async {
    await Future.wait(<Future<void>>[
      _directory.refresh(),
      _loadJobs(),
      _loadBadges(),
    ]);
  }

  // -------------------------------------------------------------- origin

  /// Works out roughly where the client is, so technician cards can say how
  /// far away each one is.
  ///
  /// Deliberately never prompts. A permission dialog the moment the home
  /// screen opens - for a distance label - is the kind of thing that gets an
  /// app denied location for good, and the posting flow needs that permission
  /// far more than this row does. So it takes what is already available, most
  /// dependable first:
  ///
  /// 1. **The saved default address**, a mandatory registration step, so every
  ///    registered client has one - and it is where their repairs happen.
  /// 2. **The last position the OS cached**, and only if permission is already
  ///    granted. `getLastKnownPosition` costs no fix and no dialog.
  /// 3. **The most recent job's coordinates.**
  ///
  /// If none resolves, cards carry no distance - the honest outcome rather
  /// than a guessed one.
  Future<void> _resolveOrigin() async {
    if (await _originFromSavedAddress()) return;
    if (await _originFromLastKnownPosition()) return;
    await _originFromRecentJob();
  }

  Future<void> _setOrigin(double latitude, double longitude) async {
    _originLat = latitude;
    _originLon = longitude;
    await _directory.setOrigin(latitude: latitude, longitude: longitude);
  }

  Future<bool> _originFromSavedAddress() async {
    try {
      // Ordered default-first by the service, so the first row with real
      // coordinates is the client's home.
      final List<SavedAddress> addresses = await _profile.loadAddresses();

      for (final SavedAddress address in addresses) {
        // 0,0 is what `SavedAddress.fromJson` substitutes for a missing
        // coordinate, and it is in the Atlantic. Treat it as absent.
        if (address.latitude == 0 && address.longitude == 0) continue;
        if (!mounted) return false;
        await _setOrigin(address.latitude, address.longitude);
        return true;
      }
    } catch (_) {
      // A client who has not finished registration has no address yet. That
      // is a normal state, not an error worth putting over the dashboard.
    }
    return false;
  }

  Future<bool> _originFromLastKnownPosition() async {
    try {
      final LocationPermission permission = await Geolocator.checkPermission();
      final bool granted =
          permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
      if (!granted) return false;

      final Position? last = await Geolocator.getLastKnownPosition();
      if (last == null || !mounted) return false;

      await _setOrigin(last.latitude, last.longitude);
      return true;
    } catch (_) {
      // A platform that cannot answer at all falls through to the job below.
      return false;
    }
  }

  Future<void> _originFromRecentJob() async {
    // A GPS fix already won. Replacing it with an older job location would be
    // a downgrade, and it would cost a second round trip to do it.
    if (_directory.hasOrigin) return;

    // `_jobs` is ordered newest first by `myJobs`, so the first row with
    // coordinates is the most recent place they asked for a repair.
    for (final Job job in _jobs) {
      final double? lat = job.latitude;
      final double? lon = job.longitude;
      if (lat != null && lon != null) {
        if (!mounted) return;
        await _setOrigin(lat, lon);
        return;
      }
    }
  }

  // --------------------------------------------------------- notifications

  /// Opens what a tapped push notification is about.
  ///
  /// A message opens its chat. A job moving - collected, at the shop, out for
  /// delivery - or running late opens the live tracking for it. "Job
  /// completed" asks for the rating, which is what the notification said to
  /// tap for. Anything else about a job opens that job.
  Future<void> _onNotificationTap() async {
    final NotificationTap? tap = NotificationRouter.take();
    if (tap == null || !mounted) return;

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
      case 'completed':
        await _loadJobs();
        await _maybeAskForRating();
      default:
        final String? jobId = tap.jobId;
        if (jobId == null) return;
        final Job? job = await _service
            .jobById(jobId)
            .catchError((Object _) => null);
        if (job == null || !mounted) return;
        final bool travelling = tap.type == 'stage' || tap.type == 'job_delay';
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => travelling
                ? JobTrackingScreen(job: job)
                : JobDetailScreen(job: job, role: BookingsRole.client),
          ),
        );
        if (mounted) await _loadJobs();
    }
  }

  /// Every thread, from the header icon.
  ///
  /// A pushed screen rather than a tab: a client arrives here knowing which
  /// conversation they want, deals with it, and leaves. Back returns them to
  /// whatever they were doing instead of parking them in an inbox.
  Future<void> _openInbox() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: AppColors.background,
          appBar: const SugoAppBar(title: 'Messages'),
          body: const SafeArea(
            child: ConversationListView(
              emptyHint:
                  'Once you send a booking request, your chat with that '
                  'technician opens here.',
            ),
          ),
        ),
      ),
    );
    // Opening a thread marks it read, so the badge is stale on return.
    if (mounted) await _loadBadges();
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
    );
    if (mounted) await _loadBadges();
  }

  // --------------------------------------------------------------- rating

  /// Jobs this app session has already asked about, so a dismissed sheet does
  /// not come back on every refresh. Static, so it survives this screen being
  /// rebuilt; not persisted, so someone who waved it away is asked once more
  /// the next time they open the app - and only within the week.
  static final Set<String> _askedToRate = <String>{};

  bool _ratingSheetOpen = false;

  /// Asks the client to rate their technician on a job that finished in the
  /// last week and that they have not rated yet - one job at a time, newest
  /// first.
  Future<void> _maybeAskForRating() async {
    if (_ratingSheetOpen || !mounted) return;

    final List<String> recent = await _service.recentlyCompletedJobIds();
    final List<String> candidates = recent
        .where((String id) => !_askedToRate.contains(id))
        .toList(growable: false);
    if (candidates.isEmpty || !mounted) return;

    final Map<String, JobParty> parties = await _service.jobParties();
    if (!mounted) return;

    JobParty? party;
    for (final String id in candidates) {
      final JobParty? candidate = parties[id];
      if (candidate != null &&
          candidate.technicianId != null &&
          candidate.myRating == null) {
        party = candidate;
        break;
      }
    }
    if (party == null) return;

    _askedToRate.add(party.jobId);
    _ratingSheetOpen = true;
    final bool saved = await RateJobSheet.show(
      context,
      jobId: party.jobId,
      technicianId: party.technicianId!,
      technicianName: party.technicianLabel,
    );
    _ratingSheetOpen = false;

    if (saved && mounted) {
      UiFeedback.showSuccess(context, 'Thanks - your rating was saved.');
    }
  }

  // ------------------------------------------------------------ the hero

  /// Everything still in play, newest first.
  List<Job> get _activeJobs => _jobs
      .where(
        (Job job) =>
            job.status != JobStatus.completed &&
            job.status != JobStatus.cancelled,
      )
      .toList(growable: false);

  /// The one booking the client most likely opened the app for.
  ///
  /// Ranked by how much is happening rather than by date: a technician on the
  /// way beats a request posted an hour ago, even though the request is newer.
  Job? get _heroJob {
    final List<Job> active = _activeJobs;
    if (active.isEmpty) return null;

    int weight(Job job) => switch (job.status) {
      JobStatus.inProgress => 5,
      JobStatus.confirmed => 4,
      JobStatus.matched => 3,
      JobStatus.pending => 2,
      _ => 1,
    };

    return active.reduce((Job a, Job b) => weight(b) > weight(a) ? b : a);
  }

  ActiveBookingState _stateFor(Job job, JobTechnician? who) {
    if (job.status == JobStatus.inProgress) {
      return ActiveBookingState.inProgress;
    }
    if (job.status == JobStatus.confirmed) {
      final JobTracking? live = _heroTracking;
      return live != null && !live.stage.isFinished
          ? ActiveBookingState.travelling
          : ActiveBookingState.confirmed;
    }
    if (job.status == JobStatus.matched) {
      return who != null && who.isAwaiting
          ? ActiveBookingState.awaiting
          : ActiveBookingState.choosing;
    }
    return ActiveBookingState.finding;
  }

  // ------------------------------------------------------------- actions

  void _startPosting({DeviceCategory? category, String? symptomCode}) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => JobPostingScreen(
              initialCategory: category,
              initialSymptomCode: symptomCode,
            ),
          ),
        )
        .then((_) => _loadJobs());
  }

  void _openTechnician(Technician technician) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TechnicianDetailScreen(
          technicianId: technician.id,
          initialTechnician: technician,
        ),
      ),
    );
  }

  void _browseTechnicians({bool favoritesOnly = false}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TechnicianBrowseScreen(
          latitude: _originLat,
          longitude: _originLon,
          initialFavoritesOnly: favoritesOnly,
        ),
      ),
    );
  }

  Future<void> _openSearch() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SearchScreen(
          latitude: _originLat,
          longitude: _originLon,
          onCategory: (DeviceCategory category) {
            Navigator.of(context).pop();
            _startPosting(category: category);
          },
          onIssue: (DeviceCategory category, issue) {
            Navigator.of(context).pop();
            _startPosting(category: category, symptomCode: issue.code);
          },
          onTechnician: (Technician technician) {
            Navigator.of(context).pop();
            _openTechnician(technician);
          },
        ),
      ),
    );
  }

  /// Opens a job at the screen that matches where it actually is.
  ///
  /// A job nobody has taken yet still has a decision to make, so it opens on
  /// the shortlist. Everything else opens on the booking, because the choosing
  /// is finished and the record is what matters.
  void _openJob(Job job) {
    final Widget destination = switch (job.status) {
      JobStatus.pending ||
      JobStatus.matched => ClientReviewScreen(jobId: job.id),
      _ => JobDetailScreen(job: job, role: BookingsRole.client),
    };

    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => destination))
        .then((_) => _loadJobs());
  }

  Future<void> _trackJob(Job job) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => JobTrackingScreen(job: job)),
    );
    if (mounted) await _loadJobs();
  }

  Future<void> _messageAbout(Job job, JobTechnician who) async {
    await openChatThread(
      context,
      jobId: job.id,
      title: who.displayName,
      avatarUrl: who.avatarUrl,
      subtitle: jobThreadSubtitle(
        job.deviceType.wire,
        job.problemSymptom,
        job.status,
      ),
    );
    if (mounted) await _loadBadges();
  }

  /// Removes a job nobody has taken. Confirmed first: it cannot be undone, and
  /// the matching run behind it goes with it.
  ///
  /// The delete runs under the bin animation (`runWithDeleteAnimation`), and
  /// the hero slot then eases from the card to the "Need a tech fix?" banner
  /// rather than snapping - see the switcher in [_homeFeed].
  Future<void> _deleteJob(Job job) async {
    final bool confirmed = await showSugoConfirmDialog(
      context: context,
      icon: Icons.delete_outline_rounded,
      iconColor: AppColors.textPrimary,
      iconTint: AppColors.divider,
      title: 'Delete this request?',
      message:
          'Nobody has taken it yet, so it will be removed along with the '
          'matches we found. This cannot be undone.',
      confirmLabel: 'Delete',
      cancelLabel: 'Keep it',
      destructive: true,
    );
    if (!confirmed || !mounted || _heroBusy) return;

    setState(() => _heroBusy = true);
    try {
      await runWithDeleteAnimation(context, _service.deleteJob(job.id));
      if (!mounted) return;
      setState(() {
        _jobs = _jobs.where((Job j) => j.id != job.id).toList(growable: false);
        _heroBusy = false;
      });
      await _loadJobs();
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      setState(() => _heroBusy = false);
      UiFeedback.showError(context, failure.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _heroBusy = false);
      UiFeedback.showError(context, 'Could not delete that request.');
    }
  }

  /// Takes back a request a technician has not answered, then reopens the
  /// shortlist so the client can choose again.
  ///
  /// Confirmed first, but gently: this is reversible in the sense that the
  /// same person can be re-chosen immediately, and the dialog says so. The
  /// thing worth warning about is the opposite risk - cancelling somebody who
  /// was about to accept.
  Future<void> _withdrawTechnician(Job job, JobTechnician who) async {
    final bool confirmed = await showSugoConfirmDialog(
      context: context,
      icon: Icons.undo_rounded,
      title: 'Cancel your request to ${who.firstName}?',
      message:
          'They have not answered yet, so nothing is lost — and this is not '
          'recorded against them. Your other matches stay ready, so you can '
          'pick somebody else straight away.',
      confirmLabel: 'Cancel request',
      cancelLabel: 'Keep waiting',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    try {
      await _service.withdrawTechnician(job.id);
      if (!mounted) return;

      UiFeedback.showSuccess(
        context,
        'Request cancelled. Pick another technician.',
      );
      await _loadJobs();
      if (!mounted) return;

      // Straight back to the shortlist. Cancelling and then being left on the
      // dashboard to find your own way back would make the whole action feel
      // like a dead end.
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ClientReviewScreen(jobId: job.id),
        ),
      );
      if (!mounted) return;
      await _loadJobs();
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      UiFeedback.showError(context, failure.message);
      // Most likely cause is that they accepted while the dialog was open, so
      // refresh rather than leaving a stale row on screen.
      await _loadJobs();
    }
  }

  // ---------------------------------------------------------------- build

  List<SugoNavItem> get _navItems => <SugoNavItem>[
    const SugoNavItem(
      label: 'Home',
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
    ),
    const SugoNavItem(
      label: 'Bookings',
      icon: Icons.event_note_outlined,
      activeIcon: Icons.event_note_rounded,
    ),
    SugoNavItem(
      label: 'Community',
      icon: Icons.forum_outlined,
      activeIcon: Icons.forum_rounded,
      showBadge: _communityUnread > 0,
    ),
    const SugoNavItem(
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();
    final AppUser? user = auth.user;

    // The name from the profile SessionController holds, falling back to the
    // auth user's metadata before the profile has loaded. (The avatar is no
    // longer on the home header - the 2026-09-28 reference has none - so only
    // the name is read here.)
    final SessionProfile? profile = context.watch<SessionController>().profile;
    final String? name = profile?.fullName ?? user?.displayName;

    return Scaffold(
      backgroundColor: AppColors.background,
      // Each tab owns its own scrolling and refresh, so the home feed is built
      // only while it is the visible tab rather than kept alive behind the
      // others.
      //
      // Home is the one tab without a top SafeArea: its header runs under the
      // status bar and pads itself by the inset, so the pull-to-refresh
      // spinner and the scroll both start at the very top. Since the Dispatch
      // redesign the header is on the light Paper ground, so the status-bar
      // icons are dark.
      body: _tab == ClientTab.home
          ? AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle.dark,
              child: _homeFeed(name),
            )
          : SafeArea(
              bottom: false,
              child: switch (_tab) {
                ClientTab.home => const SizedBox.shrink(),
                ClientTab.bookings => BookingsListView(
                  role: BookingsRole.client,
                  onPostJob: _startPosting,
                ),
                ClientTab.community => const _CommunityTab(),
                ClientTab.profile => const ProfileView(),
              },
            ),
      bottomNavigationBar: SugoBottomNav(
        items: _navItems,
        currentIndex: _tab.index,
        // The client's compose button. Client-side only: a technician has no
        // repair to post, and their bar simply omits this.
        composeAction: SugoComposeAction(onTap: _startPosting),
        onChanged: (int index) {
          final ClientTab next = ClientTab.values[index];
          setState(() => _tab = next);

          // Opening Community is what marks it seen. Done here rather than in
          // the feed's initState so it fires on every visit, not only the
          // first time the tab is built.
          if (next == ClientTab.community) {
            _community.markSeen().then((_) {
              if (mounted) setState(() => _communityUnread = 0);
            });
          }
        },
      ),
    );
  }

  /// The home feed - four things, in the order a client needs them.
  ///
  /// 1. **The header**: greeting, search, the inbox and the bell.
  /// 2. **One hero card**: the active booking, drawn as its route (Posted,
  ///    Matched, Booked, Fixed), when there is one; otherwise the "Need a
  ///    tech fix?" invitation. Never both - a client with a repair under way
  ///    does not need to be invited to book one.
  /// 3. **Services**: how a repair starts.
  /// 4. **Top-rated technicians**: the one thing here that no tab shows.
  ///
  /// ## What was taken off on 2026-09-28, and where it still is
  ///
  /// The client asked for a home that is not crowded and has no duplicates.
  /// Everything removed was a second way to reach something already on
  /// screen, so nothing became unreachable:
  ///
  /// | Removed                 | Still reachable through            |
  /// |-------------------------|------------------------------------|
  /// | Common repairs          | the Services grid - same categories |
  /// | Recommended for you     | the Services grid - same categories |
  /// | Recent bookings         | the Bookings tab, and the hero card |
  /// | How it works            | the "Need a tech fix?" card         |
  /// | Community promo         | the Community tab, which has its own unread badge |
  Widget _homeFeed(String? name) {
    final Job? hero = _heroJob;
    final JobTechnician? heroWho = hero == null ? null : _technicians[hero.id];

    return RefreshIndicator(
      onRefresh: _refresh,
      // Below the status bar, so the spinner is not drawn under the clock.
      edgeOffset: MediaQuery.paddingOf(context).top,
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppSizes.xxl + AppSizes.xl),
        children: <Widget>[
          HomeHeader(
            name: name,
            unreadNotifications: _unreadNotifications,
            unreadMessages: _unreadMessages,
            onOpenNotifications: _openNotifications,
            onOpenMessages: _openInbox,
            onSearch: _openSearch,
            topInset: MediaQuery.paddingOf(context).top,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.screenPadding,
              AppSizes.lg,
              AppSizes.screenPadding,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // ------------------------------------------ one hero card
                //
                // `HomeHeroSlot` animates between the three and, unlike a bare
                // AnimatedSwitcher, keeps each card at full width.
                HomeHeroSlot(
                  child: _jobsLoading && _jobs.isEmpty
                      ? const ActiveBookingSkeleton(
                          key: ValueKey<String>('hero-loading'),
                        )
                      : hero != null
                      ? ActiveBookingCard(
                          key: ValueKey<String>('hero-${hero.id}'),
                          job: hero,
                          state: _stateFor(hero, heroWho),
                          technician: heroWho,
                          tracking: _heroTracking,
                          moreCount: _activeJobs.length - 1,
                          onSeeAll: () =>
                              setState(() => _tab = ClientTab.bookings),
                          onPrimary: () {
                            if (_stateFor(hero, heroWho) ==
                                ActiveBookingState.travelling) {
                              _trackJob(hero);
                            } else {
                              _openJob(hero);
                            }
                          },
                          // Chat opens only once a technician has accepted, which
                          // is the same rule the database enforces - so the button
                          // is never offered for a thread it would refuse.
                          onMessage: heroWho != null && heroWho.isAccepted
                              ? () => _messageAbout(hero, heroWho)
                              : null,
                          onCancel: _heroBusy
                              ? null
                              : heroWho != null && heroWho.canWithdraw
                              ? () => _withdrawTechnician(hero, heroWho)
                              : hero.canBeDeletedByClient
                              ? () => _deleteJob(hero)
                              : null,
                        )
                      : HomeHeroBanner(
                          key: const ValueKey<String>('hero-banner'),
                          onBookNow: _startPosting,
                        ),
                ),
                const SizedBox(height: AppSizes.xxl),

                // ------------------------------------------------ services
                const SectionHeader(
                  title: 'Services',
                  subtitle: 'Pick one and we will recommend three technicians',
                ),
                const SizedBox(height: AppSizes.lg),
                ServiceCategoryGrid(
                  onSelect: (HomeServiceCategory category) =>
                      resolveHomeCategory(
                        context,
                        category,
                        onResolved: (DeviceCategory? device) =>
                            _startPosting(category: device),
                      ),
                ),
                const SizedBox(height: AppSizes.xxl),

                // ------------------------------------ top-rated technicians
                SectionHeader(
                  title: 'Top-rated technicians',
                  // Says what the row is: a shortlist, not a directory.
                  subtitle: '20+ jobs completed, consistently well reviewed',
                  action: 'See all',
                  onActionTap: _browseTechnicians,
                ),
                const SizedBox(height: AppSizes.md),
              ],
            ),
          ),
          ListenableBuilder(
            listenable: _directory,
            builder: (BuildContext context, Widget? _) =>
                RecommendedTechnicians(
                  provider: _directory,
                  onSelect: _openTechnician,
                ),
          ),
        ],
      ),
    );
  }
}

/// The Community tab: questions the client can ask and read answers to.
class _CommunityTab extends StatelessWidget {
  const _CommunityTab();

  @override
  Widget build(BuildContext context) {
    return const CommunityFeedView(isClient: true);
  }
}
