import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/sugo_avatar.dart';
import '../../../core/widgets/sugo_empty_state.dart';
import '../../../core/widgets/sugo_skeleton.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../models/chat_models.dart';
import '../services/chat_service.dart';
import 'chat_thread_screen.dart';

/// The Chat tab, shared by both dashboards.
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
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.08),
            SugoEmptyState(
              icon: Icons.forum_outlined,
              title: 'No conversations yet',
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

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(
          AppSizes.md,
          AppSizes.sm,
          AppSizes.md,
          AppSizes.xxl,
        ),
        // One extra row on top: how many threads want attention.
        itemCount: _conversations.length + 1,
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSizes.xs,
                AppSizes.xs,
                AppSizes.xs,
                AppSizes.md,
              ),
              child: Text(
                unreadThreads == 0
                    ? 'All caught up'
                    : '$unreadThreads unread '
                          '${unreadThreads == 1 ? 'conversation' : 'conversations'}',
                style: AppTextStyles.overline,
              ),
            );
          }
          final Conversation conversation = _conversations[index - 1];
          return _ConversationTile(
            conversation: conversation,
            onTap: () => _open(conversation),
          );
        },
      ),
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
                    SugoAvatar(
                      name: conversation.counterpartName,
                      imageUrl: conversation.counterpartAvatarUrl,
                      size: 48,
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
    );
  }
}
