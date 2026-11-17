import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/sugo_avatar.dart';
import '../../../core/widgets/sugo_empty_state.dart';
import '../../../core/widgets/sugo_motion.dart';
import '../../../core/widgets/sugo_skeleton.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../../rb_cars/widgets/press_scale.dart';
import '../models/chat_models.dart';
import '../services/chat_service.dart';
import 'chat_thread_screen.dart';

/// Which threads the inbox shows (2026-11-17).
enum _InboxFilter { all, unread, offers }

/// The Chat tab, shared by both dashboards.
///
/// Renovated 2026-11-17 ("Dispatch, levelled up"): a summary band with the
/// unread count, a sliding All / Unread / Pending filter, rows that deal
/// in once when the inbox opens, and an illustrated empty state. The rows
/// themselves say the same things they did.
///
/// A body rather than a Scaffold: each dashboard supplies its own app bar and
/// bottom navigation, and this drops into the content area. The same list
/// serves both roles because a conversation is symmetric - each side sees the
/// other, resolved by `job_conversations` from the caller's own point of view.
class ConversationListView extends StatefulWidget {
  const ConversationListView({
    super.key,
    this.emptyHint,
    @visibleForTesting this.service,
  });

  /// Tests only. The app always uses the real service.
  final ChatService? service;

  /// Role-specific line for the empty state. A client is told to book; a
  /// technician is told to accept a job - the same words would be wrong for
  /// one of them.
  final String? emptyHint;

  @override
  State<ConversationListView> createState() => _ConversationListViewState();
}

class _ConversationListViewState extends State<ConversationListView> {
  late final ChatService _service = widget.service ?? ChatService();

  List<Conversation> _conversations = const <Conversation>[];
  bool _isLoading = true;
  String? _error;
  _InboxFilter _filter = _InboxFilter.all;

  /// Rows rise in only the first time the list appears. Rows that scroll
  /// into view later, or come back after a reload, simply appear.
  bool _entrancePlayed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<Conversation> rows = await _service.conversations();
      if (!mounted) return;
      setState(() {
        _conversations = rows;
        _isLoading = false;
        _error = null;
      });
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _open(Conversation conversation) async {
    await openChatThread(
      context,
      jobId: conversation.jobId,
      title: conversation.counterpartName,
      avatarUrl: conversation.counterpartAvatarUrl,
      subtitle: jobThreadSubtitle(
        conversation.deviceType,
        conversation.problemSymptom,
        conversation.jobStatus,
      ),
    );
    // Reload on return so the unread badge and the preview line reflect what
    // just happened in the thread.
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      // Skeleton rows rather than a spinner, so the list does not jump when
      // the threads land - see `SugoSkeleton` for why that matters.
      return ListView(
        padding: const EdgeInsets.all(AppSizes.md),
        children: const <Widget>[SugoSkeletonList(count: 4)],
      );
    }

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(AppSizes.screenPadding),
        children: <Widget>[
          SugoEmptyState.error(
            title: 'Your messages did not load',
            message: '$_error Check your connection, then try again.',
            onAction: () {
              setState(() {
                _isLoading = true;
                _error = null;
              });
              _load();
            },
          ),
        ],
      );
    }

    if (_conversations.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(AppSizes.screenPadding),
          children: <Widget>[
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.06),
            _EmptyInbox(
              message:
                  widget.emptyHint ??
                  'A chat opens automatically once a job is accepted.',
            ),
          ],
        ),
      );
    }

    final int unreadThreads = _conversations
        .where((Conversation c) => c.hasUnread)
        .length;
    final int offers = _conversations
        .where((Conversation c) => c.isPendingOffer)
        .length;
    // The Offers segment exists only while there is an offer to show.
    final _InboxFilter filter = _filter == _InboxFilter.offers && offers == 0
        ? _InboxFilter.all
        : _filter;
    final List<Conversation> visible = switch (filter) {
      _InboxFilter.all => _conversations,
      _InboxFilter.unread =>
        _conversations.where((Conversation c) => c.hasUnread).toList(),
      _InboxFilter.offers =>
        _conversations.where((Conversation c) => c.isPendingOffer).toList(),
    };

    final bool animate = !_entrancePlayed;
    if (animate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _entrancePlayed = true;
      });
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(
          AppSizes.md,
          AppSizes.md,
          AppSizes.md,
          AppSizes.xxl,
        ),
        // One extra row on top: the summary band and the filter.
        itemCount: (visible.isEmpty ? 1 : visible.length) + 1,
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SugoRiseIn(
                    enabled: animate,
                    child: _InboxSummary(
                      unread: unreadThreads,
                      total: _conversations.length,
                    ),
                  ),
                  const SizedBox(height: AppSizes.md),
                  SugoRiseIn(
                    enabled: animate,
                    delay: AppMotion.staggerStep,
                    child: SugoSegmentedFilter<_InboxFilter>(
                      selected: filter,
                      onChanged: (_InboxFilter f) =>
                          setState(() => _filter = f),
                      segments: <SugoSegment<_InboxFilter>>[
                        const SugoSegment<_InboxFilter>(
                          value: _InboxFilter.all,
                          label: 'All',
                        ),
                        SugoSegment<_InboxFilter>(
                          value: _InboxFilter.unread,
                          label: 'Unread',
                          count: unreadThreads,
                        ),
                        if (offers > 0)
                          SugoSegment<_InboxFilter>(
                            value: _InboxFilter.offers,
                            label: 'Pending',
                            count: offers,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
          if (visible.isEmpty) {
            final bool unreadTab = filter == _InboxFilter.unread;
            return Padding(
              padding: const EdgeInsets.only(top: AppSizes.lg),
              child: SugoEmptyState(
                icon: unreadTab
                    ? Icons.mark_chat_read_outlined
                    : Icons.hourglass_empty_rounded,
                title: unreadTab ? 'Nothing unread' : 'No pending offers',
                message: unreadTab
                    ? 'You have read every message.'
                    : 'Every conversation here is about an accepted booking.',
                compact: true,
              ),
            );
          }
          final Conversation conversation = visible[index - 1];
          return SugoRiseIn(
            // Keyed by thread, so a row keeps its state across filters.
            key: ValueKey<String>(conversation.jobId),
            enabled: animate,
            delay: AppMotion.staggerDelay(index + 1),
            child: _ConversationTile(
              conversation: conversation,
              onTap: () => _open(conversation),
            ),
          );
        },
      ),
    );
  }
}

/// "3 unread conversations", on the navy band, with a bubble badge.
class _InboxSummary extends StatelessWidget {
  const _InboxSummary({required this.unread, required this.total});

  final int unread;
  final int total;

  @override
  Widget build(BuildContext context) {
    return SugoHeroBand(
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'YOUR INBOX',
                  style: AppTextStyles.overline.copyWith(
                    color: Colors.white.withValues(alpha: 0.75),
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  unread == 0
                      ? 'All caught up'
                      : '$unread unread '
                            '${unread == 1 ? 'conversation' : 'conversations'}',
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
                  '$total ${total == 1 ? 'chat' : 'chats'}, one per job',
                  style: AppTextStyles.micro.copyWith(
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSizes.md),
          _BubbleBadge(unread: unread),
        ],
      ),
    );
  }
}

/// Two chat bubbles that pop in one after the other, with the unread count
/// (or a double tick) in the front one.
class _BubbleBadge extends StatelessWidget {
  const _BubbleBadge({required this.unread});

  final int unread;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 60,
      child: Stack(
        children: <Widget>[
          Positioned(
            right: 0,
            top: 0,
            child: SugoRiseIn(
              delay: const Duration(milliseconds: 180),
              child: _bubble(
                40,
                Colors.white.withValues(alpha: 0.18),
                const SizedBox.shrink(),
              ),
            ),
          ),
          Positioned(
            left: 0,
            bottom: 0,
            child: SugoRiseIn(
              delay: const Duration(milliseconds: 320),
              child: _bubble(
                48,
                Colors.white,
                unread == 0
                    ? const Icon(
                        Icons.done_all_rounded,
                        color: AppColors.primary,
                        size: 22,
                      )
                    : SugoCountUp(
                        value: unread,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _bubble(double size, Color color, Widget child) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(size / 2),
        topRight: Radius.circular(size / 2),
        bottomRight: Radius.circular(size / 2),
        bottomLeft: const Radius.circular(6),
      ),
    ),
    child: child,
  );
}

/// No conversations at all: two bubbles trade a "hello", then the words.
class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    Widget bubble(String text, {required bool mine}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: mine ? AppColors.primary : AppColors.surface,
        border: mine ? null : Border.all(color: AppColors.border),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(AppSizes.sheetRadius),
          topRight: const Radius.circular(AppSizes.sheetRadius),
          bottomLeft: Radius.circular(mine ? AppSizes.sheetRadius : 4),
          bottomRight: Radius.circular(mine ? 4 : AppSizes.sheetRadius),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: mine ? Colors.white : AppColors.textPrimary,
        ),
      ),
    );

    return Column(
      children: <Widget>[
        SizedBox(
          width: 220,
          child: Column(
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: SugoRiseIn(
                  delay: const Duration(milliseconds: 120),
                  child: bubble('Hi! When can you come?', mine: false),
                ),
              ),
              const SizedBox(height: AppSizes.sm),
              Align(
                alignment: Alignment.centerRight,
                child: SugoRiseIn(
                  delay: const Duration(milliseconds: 520),
                  child: bubble('Tomorrow at 10?', mine: true),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSizes.xl),
        SugoRiseIn(
          delay: const Duration(milliseconds: 700),
          child: Column(
            children: <Widget>[
              Text(
                'No conversations yet',
                textAlign: TextAlign.center,
                style: AppTextStyles.title,
              ),
              const SizedBox(height: AppSizes.xs),
              Text(
                message,
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

/// One thread: who, the last thing said, and the job it is about.
///
/// A card rather than a divided row, tinted while it has unread messages, so
/// the threads that need an answer stand out before any text is read.
class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.onTap});

  final Conversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool unread = conversation.hasUnread;
    final BorderRadius radius = BorderRadius.circular(AppSizes.tileRadius);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: PressScale(
        scale: 0.98,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: AnimatedContainer(
              duration: AppMotion.base,
              padding: const EdgeInsets.all(AppSizes.md),
              decoration: BoxDecoration(
                color: unread ? AppColors.primarySofter : AppColors.surface,
                borderRadius: radius,
                border: Border.all(
                  color: unread ? AppColors.primarySoft : AppColors.divider,
                ),
              ),
              child: Row(
                children: <Widget>[
                  Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      // A gradient ring while there is something to read.
                      AnimatedContainer(
                        duration: AppMotion.base,
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: unread
                              ? const LinearGradient(
                                  colors: <Color>[
                                    AppColors.secondary,
                                    AppColors.cyan,
                                  ],
                                )
                              : null,
                          color: unread ? null : Colors.transparent,
                        ),
                        child: SugoAvatar(
                          name: conversation.counterpartName,
                          imageUrl: conversation.counterpartAvatarUrl,
                          size: 46,
                        ),
                      ),
                      if (unread)
                        Positioned(
                          right: -1,
                          top: -1,
                          child: Container(
                            width: 13,
                            height: 13,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                conversation.counterpartName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: unread
                                      ? FontWeight.w800
                                      : FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            if (conversation.lastMessageAt != null)
                              Text(
                                Fmt.relative(conversation.lastMessageAt!),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: unread
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                  color: unread
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                conversation.preview,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.3,
                                  fontWeight: unread
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: unread
                                      ? AppColors.textPrimary
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                            if (unread) ...<Widget>[
                              const SizedBox(width: AppSizes.sm),
                              // A pill, not a circle: "12" in a circle sized for
                              // "3" squeezes into an oval.
                              Container(
                                constraints: const BoxConstraints(
                                  minWidth: 20,
                                  minHeight: 20,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(
                                    AppSizes.pillRadius,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  conversation.unreadCount > 99
                                      ? '99+'
                                      : '${conversation.unreadCount}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: AppSizes.sm),
                        // The job, so two threads with the same person are
                        // distinguishable at a glance - plus, when this is a
                        // technician who has not accepted yet, a chip that says
                        // so. Without it a negotiation looks exactly like a
                        // booking, and "my technician is coming" is not a thing
                        // to leave someone believing by accident.
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: <Widget>[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(
                                  AppSizes.pillRadius,
                                ),
                                border: Border.all(color: AppColors.divider),
                              ),
                              child: Text(
                                jobThreadSubtitle(
                                  conversation.deviceType,
                                  conversation.problemSymptom,
                                  conversation.jobStatus,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            if (conversation.isPendingOffer)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.accentSoft,
                                  borderRadius: BorderRadius.circular(
                                    AppSizes.pillRadius,
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(
                                      Icons.hourglass_bottom_rounded,
                                      size: 11,
                                      color: AppColors.accentDark,
                                    ),
                                    SizedBox(width: 3),
                                    Text(
                                      'Not accepted yet',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.accentDark,
                                      ),
                                    ),
                                  ],
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
        ),
      ),
    );
  }
}
