import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/sugo_app_bar.dart';
import '../../../core/widgets/sugo_avatar.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_empty_state.dart';
import '../../../core/widgets/sugo_motion.dart';
import '../../../core/widgets/sugo_pill.dart';
import '../../../core/widgets/sugo_skeleton.dart';
import '../../../core/widgets/sugo_status_badge.dart';
import '../../bookings/screens/bookings_list_view.dart';
import '../../bookings/screens/job_detail_screen.dart';
import '../../chat/screens/chat_thread_screen.dart';
import '../../client/screens/client_dashboard_screen.dart';
import '../../rb_cars/models/job.dart';
import '../../rb_cars/models/job_enums.dart';
import '../../rb_cars/screens/client_review_screen.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../../tracking/screens/job_tracking_screen.dart';
import '../../tracking/screens/technician_delivery_screen.dart';
import '../models/app_notification.dart';
import '../services/notification_feed_service.dart';
import 'notification_settings_screen.dart';

/// The notification centre.
///
/// Opened from the bell on the home header. What it shows, and why:
///
/// * **Unread items are distinct in three ways at once** - a navy dot, a bold
///   title and a faint blue wash across the row - so "new" survives a glance,
///   greyscale and a bright screen.
/// * **Filters appear only for categories that have something in them.** A
///   "Payment" tab that is always empty is a broken promise.
/// * **Grouped by day**, because "what happened today" is the question most
///   people open this with.
/// * **Every row goes somewhere** - the booking, the chat, the live map - and
///   opening it marks it read.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    this.audience = NotificationAudience.client,
    this.service,
    this.jobs,
  });

  /// Whose notifications these are. Decides both what the feed is built from
  /// and where a tapped row goes - a technician's "new job request" has no
  /// booking screen to open, because the job is not theirs to read until they
  /// accept it.
  final NotificationAudience audience;

  /// Tests only.
  final NotificationFeedService? service;
  final RbCarsService? jobs;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final NotificationFeedService _feed =
      widget.service ?? NotificationFeedService(audience: widget.audience);

  bool get _isClient => widget.audience == NotificationAudience.client;
  late final RbCarsService _jobs = widget.jobs ?? RbCarsService();

  List<AppNotification> _items = const <AppNotification>[];
  bool _loading = true;
  String? _error;
  NotificationCategory? _filter;

  /// Rows deal in only the first time the list appears (2026-11-17).
  bool _entrancePlayed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<AppNotification> items = await _feed.load();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
        // A filter whose last item disappeared falls back to All.
        if (_filter != null &&
            !items.any((AppNotification n) => n.category == _filter)) {
          _filter = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'We could not load your notifications.';
      });
    }
  }

  Future<void> _markAllRead() async {
    await _feed.markSeen(_items);
    if (!mounted) return;
    setState(() {
      _items = _items
          .map(
            (AppNotification n) => n.category == NotificationCategory.messages
                ? n
                : n.copyWith(unread: false),
          )
          .toList();
    });
  }

  Future<void> _open(AppNotification item) async {
    await _feed.markSeen(<AppNotification>[item]);
    if (!mounted) return;
    setState(() {
      _items = _items
          .map(
            (AppNotification n) =>
                n.id == item.id && n.category != NotificationCategory.messages
                ? n.copyWith(unread: false)
                : n,
          )
          .toList();
    });

    // A request the technician has not accepted lives on the dashboard and
    // nowhere else, so this row's job is to take them back to it.
    if (item.action == NotificationAction.openOffers) {
      Navigator.of(context).maybePop();
      return;
    }

    final String? jobId = item.jobId;
    if (jobId == null) return;

    if (item.action == NotificationAction.openChat) {
      await openChatThread(
        context,
        jobId: jobId,
        title: item.counterpartName ?? 'Messages',
        avatarUrl: item.counterpartAvatarUrl,
      );
      await _load();
      return;
    }

    final Job? job = await _jobs.jobById(jobId).catchError((Object _) => null);
    if (!mounted) return;
    if (job == null) {
      setState(() => _error = 'That booking is no longer available.');
      return;
    }

    // A Technician Community question has no technician shortlist yet.
    // Opening the community destination keeps this notification separate from
    // the matching flow; the shortlist only becomes valid after conversion to
    // Home Service or Shop Pickup.
    if (_isClient && job.servicePath == ServicePath.itCommunity) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              const ClientDashboardScreen(initialTab: ClientTab.community),
        ),
      );
      await _load();
      return;
    }

    final Widget destination = switch (item.action) {
      // Each role gets the tracking screen built for it: the client watches,
      // the technician drives.
      NotificationAction.openTracking =>
        _isClient
            ? JobTrackingScreen(job: job)
            : TechnicianDeliveryScreen(job: job),
      _ when !_isClient => JobDetailScreen(
        job: job,
        role: BookingsRole.technician,
      ),
      _ =>
        job.status == JobStatus.pending || job.status == JobStatus.matched
            ? ClientReviewScreen(jobId: job.id)
            : JobDetailScreen(job: job, role: BookingsRole.client),
    };
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => destination));
    await _load();
  }

  List<AppNotification> get _visible => _filter == null
      ? _items
      : _items.where((AppNotification n) => n.category == _filter).toList();

  @override
  Widget build(BuildContext context) {
    final bool anyUnread = _items.any(
      (AppNotification n) =>
          n.unread && n.category != NotificationCategory.messages,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: SugoAppBar(
        title: 'Notifications',
        actions: <Widget>[
          if (anyUnread)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read'),
            ),
          IconButton(
            tooltip: 'Notification settings',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const NotificationSettingsScreen(),
                ),
              );
              if (mounted) await _load();
            },
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.all(AppSizes.screenPadding),
        children: const <Widget>[SugoSkeletonList(count: 6)],
      );
    }

    if (_error != null && _items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(AppSizes.screenPadding),
        children: <Widget>[
          SugoEmptyState.error(
            title: 'Notifications did not load',
            message: '$_error Check your connection, then try again.',
            onAction: () {
              setState(() => _loading = true);
              _load();
            },
          ),
        ],
      );
    }

    final Set<NotificationCategory> present = _items
        .map((AppNotification n) => n.category)
        .toSet();

    final List<AppNotification> visible = _visible;
    final int fresh = _items.where((AppNotification n) => n.unread).length;

    final bool animate = !_entrancePlayed;
    if (animate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _entrancePlayed = true;
      });
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSizes.xxl),
      children: <Widget>[
        // The summary band (2026-11-17): how much is new, with a bell that
        // rings once when there is something to ring about.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSizes.screenPadding,
            AppSizes.md,
            AppSizes.screenPadding,
            AppSizes.md,
          ),
          child: SugoRiseIn(
            enabled: animate,
            child: _NotificationSummary(fresh: fresh, isClient: _isClient),
          ),
        ),
        if (present.length > 1)
          SizedBox(
            height: AppSizes.filterTabHeight + AppSizes.md,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(
                AppSizes.screenPadding,
                0,
                AppSizes.screenPadding,
                AppSizes.md,
              ),
              children: <Widget>[
                SugoPill(
                  label: 'All',
                  selected: _filter == null,
                  onTap: () => setState(() => _filter = null),
                ),
                for (final NotificationCategory c
                    in NotificationCategory.values)
                  if (present.contains(c)) ...<Widget>[
                    const SizedBox(width: AppSizes.sm),
                    SugoPill(
                      label: c.label,
                      icon: c.icon,
                      selected: _filter == c,
                      onTap: () => setState(() => _filter = c),
                    ),
                  ],
              ],
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.screenPadding,
              0,
              AppSizes.screenPadding,
              AppSizes.md,
            ),
            child: Text(_error!, style: AppTextStyles.caption),
          ),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.all(AppSizes.screenPadding),
            child: _AllCaughtUp(),
          )
        else
          ..._grouped(visible, animate: animate),
      ],
    );
  }

  List<Widget> _grouped(List<AppNotification> items, {required bool animate}) {
    final List<Widget> out = <Widget>[];
    String? heading;
    for (int i = 0; i < items.length; i++) {
      final AppNotification n = items[i];
      final String h = Fmt.dayHeading(n.at);
      if (h != heading) {
        heading = h;
        out.add(
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSizes.screenPadding,
              i == 0 ? AppSizes.xs : AppSizes.lg,
              AppSizes.screenPadding,
              AppSizes.sm,
            ),
            // Sentence case since the Dispatch redesign.
            child: Text(h, style: AppTextStyles.overline),
          ),
        );
      }
      out.add(
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.screenPadding,
          ),
          child: SugoRiseIn(
            key: ValueKey<String>(n.id),
            enabled: animate,
            delay: AppMotion.staggerDelay(i + 1),
            // No extra press effect: a tappable SugoCard already answers a
            // tap itself, and two responses to one tap read as a glitch.
            child: NotificationCard(item: n, onTap: () => _open(n)),
          ),
        ),
      );
    }
    return out;
  }
}

/// "3 new updates" on the navy band, with a bell that rings once.
class _NotificationSummary extends StatelessWidget {
  const _NotificationSummary({required this.fresh, required this.isClient});

  final int fresh;
  final bool isClient;

  @override
  Widget build(BuildContext context) {
    final Widget bell = Container(
      width: 56,
      height: 56,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: Icon(
        fresh == 0
            ? Icons.notifications_none_rounded
            : Icons.notifications_active_rounded,
        size: 28,
        color: fresh == 0 ? AppColors.primary : AppColors.accent,
      ),
    );

    return SugoHeroBand(
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'UPDATES',
                  style: AppTextStyles.overline.copyWith(
                    color: Colors.white.withValues(alpha: 0.75),
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  fresh == 0
                      ? 'Nothing new'
                      : '$fresh new ${fresh == 1 ? 'update' : 'updates'}',
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 20,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isClient
                      ? 'Bookings, messages and live trips, newest first.'
                      : 'Requests, messages and trips, newest first.',
                  style: AppTextStyles.micro.copyWith(
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSizes.md),
          // A bell rings only when there is news.
          fresh == 0 ? bell : SugoWiggle(child: bell),
        ],
      ),
    );
  }
}

/// Nothing in this view: a bell that rings once, then the words.
class _AllCaughtUp extends StatelessWidget {
  const _AllCaughtUp();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const SizedBox(height: AppSizes.lg),
        SugoRiseIn(
          child: Container(
            width: 92,
            height: 92,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[AppColors.primarySoft, AppColors.cyanSoft],
              ),
            ),
            child: const SugoWiggle(
              swings: 2,
              child: Icon(
                Icons.notifications_rounded,
                size: 42,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSizes.lg),
        SugoRiseIn(
          delay: AppMotion.staggerDelay(2),
          child: Column(
            children: <Widget>[
              Text(
                "You're all caught up",
                textAlign: TextAlign.center,
                style: AppTextStyles.title,
              ),
              const SizedBox(height: AppSizes.xs),
              Text(
                'Booking updates, messages and tracking alerts will appear '
                'here as they happen.',
                textAlign: TextAlign.center,
                style: AppTextStyles.subtitle,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One notification row.
class NotificationCard extends StatelessWidget {
  const NotificationCard({super.key, required this.item, required this.onTap});

  final AppNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (Color tint, Color ink) = item.tone.colors;

    final Widget leading = item.category == NotificationCategory.messages
        ? SugoAvatar(
            name: item.counterpartName,
            imageUrl: item.counterpartAvatarUrl,
            size: 44,
          )
        : Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[tint, Color.lerp(tint, Colors.white, 0.55)!],
              ),
              borderRadius: BorderRadius.circular(AppSizes.radius),
            ),
            child: Icon(item.icon, size: 21, color: ink),
          );

    return Semantics(
      button: true,
      label:
          '${item.unread ? 'Unread. ' : ''}${item.title}. ${item.body}. '
          '${Fmt.relative(item.at)}',
      excludeSemantics: true,
      child: SugoCard(
        margin: const EdgeInsets.only(bottom: AppSizes.sm),
        padding: const EdgeInsets.all(AppSizes.md + 2),
        elevation: item.unread ? SugoElevation.md : SugoElevation.sm,
        background: item.unread ? AppColors.primarySofter : AppColors.surface,
        borderColor: item.unread ? AppColors.primarySoft : null,
        onTap: onTap,
        // The accent edge (2026-11-17): a full-height gradient bar while the
        // item is unread, which slides away once it has been opened.
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AnimatedContainer(
                duration: AppMotion.base,
                curve: AppMotion.standard,
                width: item.unread ? 4 : 0,
                margin: EdgeInsets.only(
                  right: item.unread ? AppSizes.sm + 2 : 0,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[AppColors.secondary, AppColors.cyan],
                  ),
                ),
              ),
              Align(alignment: Alignment.topCenter, child: leading),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.titleSmall.copyWith(
                              fontSize: 15,
                              fontWeight: item.unread
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSizes.sm),
                        Text(
                          Fmt.relative(item.at),
                          style: AppTextStyles.micro.copyWith(
                            color: item.unread
                                ? AppColors.secondaryDark
                                : AppColors.hint,
                            fontWeight: item.unread
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption,
                    ),
                    const SizedBox(height: AppSizes.sm),
                    Row(
                      children: <Widget>[
                        SugoStatusBadge(
                          label: item.category.label,
                          icon: item.category.icon,
                          tone: SugoTone.neutral,
                          dense: true,
                        ),
                        const Spacer(),
                        AnimatedOpacity(
                          opacity: item.unread ? 1 : 0,
                          duration: AppMotion.base,
                          child: Container(
                            width: 9,
                            height: 9,
                            decoration: const BoxDecoration(
                              color: AppColors.secondary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
