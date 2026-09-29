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
import '../../../core/widgets/sugo_pill.dart';
import '../../../core/widgets/sugo_skeleton.dart';
import '../../../core/widgets/sugo_status_badge.dart';
import '../../bookings/screens/bookings_list_view.dart';
import '../../bookings/screens/job_detail_screen.dart';
import '../../chat/screens/chat_thread_screen.dart';
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
          .map((AppNotification n) => n.id == item.id && n.category !=
                  NotificationCategory.messages
              ? n.copyWith(unread: false)
              : n)
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

    final Widget destination = switch (item.action) {
      // Each role gets the tracking screen built for it: the client watches,
      // the technician drives.
      NotificationAction.openTracking => _isClient
          ? JobTrackingScreen(job: job)
          : TechnicianDeliveryScreen(job: job),
      _ when !_isClient =>
        JobDetailScreen(job: job, role: BookingsRole.technician),
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

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSizes.xxl),
      children: <Widget>[
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
          Padding(
            padding: const EdgeInsets.all(AppSizes.screenPadding),
            child: SugoEmptyState(
              icon: Icons.notifications_none_rounded,
              title: "You're all caught up",
              message:
                  'Booking updates, messages and tracking alerts will appear '
                  'here as they happen.',
            ),
          )
        else
          ..._grouped(visible),
      ],
    );
  }

  List<Widget> _grouped(List<AppNotification> items) {
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
          child: NotificationCard(item: n, onTap: () => _open(n)),
        ),
      );
    }
    return out;
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
              color: tint,
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            leading,
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
    );
  }
}
