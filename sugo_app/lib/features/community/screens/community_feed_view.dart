import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/widgets/sugo_empty_state.dart';
import '../../../core/widgets/sugo_skeleton.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../models/community_models.dart';
import '../services/community_service.dart';
import '../widgets/community_post_card.dart';
import 'ask_question_sheet.dart';
import 'community_post_screen.dart';

/// The Community tab, shared by both roles.
///
/// ## Why one screen and not two
///
/// A client and a technician see the same feed, sorted the same way, because
/// it is the same conversation. The role changes exactly two things, and both
/// are handled by a single flag rather than a separate widget tree:
///
/// * a client gets the "Ask a question" affordance; a technician does not,
///   because the feed is a place where questions come from the people with
///   the problems;
/// * a technician gets a prompt pointing at unanswered questions, because
///   that is the thing they can do here that nobody else can.
///
/// The empty states differ for the same reason - "ask the first question" is
/// useless advice to someone who is not allowed to ask one.
class CommunityFeedView extends StatefulWidget {
  const CommunityFeedView({super.key, required this.isClient});

  /// Drives the two role differences described above. Passed in rather than
  /// read from the session here, because both dashboards already know the
  /// role and a second source of truth is a second thing to get wrong.
  final bool isClient;

  @override
  State<CommunityFeedView> createState() => CommunityFeedViewState();
}

/// Public, with [openComposer] exposed, so a host screen can open the "ask a
/// question" sheet without reaching into private state.
///
/// Note the client dashboard's "+" button does *not* call this - it opens the
/// job posting flow, because posting a repair is the action the client app is
/// built around. This is here for the feed's own Ask button and its empty
/// state, and so a future entry point does not have to make the state public.
class CommunityFeedViewState extends State<CommunityFeedView> {
  final CommunityService _service = CommunityService();

  List<CommunityPost> _posts = const <CommunityPost>[];
  CommunitySort _sort = CommunitySort.recent;
  CommunityTopic? _topic;

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final List<CommunityPost> posts = await _service.feed(
        sort: _sort,
        topic: _topic,
      );
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _loading = false;
      });
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure.message;
        _loading = false;
      });
    }
  }

  /// Re-reads without clearing the list, so a pull-to-refresh does not blank
  /// the screen it is refreshing.
  Future<void> _refresh() async {
    try {
      final List<CommunityPost> posts = await _service.feed(
        sort: _sort,
        topic: _topic,
      );
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _error = null;
      });
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      UiFeedback.showError(context, failure.message);
    }
  }

  void _setSort(CommunitySort sort) {
    if (_sort == sort) return;
    setState(() => _sort = sort);
    _load();
  }

  void _setTopic(CommunityTopic? topic) {
    if (_topic == topic) return;
    setState(() => _topic = topic);
    _load();
  }

  /// Opens the "ask a question" sheet and folds the new post into the feed.
  ///
  /// The filters are cleared on the way back, and that is not tidiness - it is
  /// the difference between the question appearing and not.
  ///
  /// The feed reloads with whatever sort and topic were active. Ask a question
  /// about a laptop while the feed is filtered to "Phones", or while it is
  /// sorted by Most Helpful, and the new row is genuinely not in the result:
  /// it posts successfully and then does not show up, which reads as the post
  /// having failed.
  ///
  /// Recent + All is the only combination guaranteed to contain a question
  /// posted one second ago.
  Future<void> openComposer() async {
    final CommunityPost? posted = await AskQuestionSheet.show(context);
    if (posted == null || !mounted) return;

    setState(() {
      _sort = CommunitySort.recent;
      _topic = null;
    });

    UiFeedback.showSuccess(context, 'Your question is live.');
    await _refresh();
  }

  Future<void> _open(CommunityPost post) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CommunityPostScreen(post: post),
      ),
    );
    if (!mounted) return;
    // The thread may have gained an answer or a vote, both of which change
    // this row.
    await _refresh();
  }

  Future<void> _delete(CommunityPost post) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Delete this question?'),
        content: const Text(
          'It will be removed along with every answer people have written on '
          'it. This cannot be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _service.deletePost(post.id);
      if (!mounted) return;
      UiFeedback.showSuccess(context, 'Question deleted.');
      await _refresh();
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      UiFeedback.showError(context, failure.message);
    }
  }

  int get _unanswered =>
      _posts.where((CommunityPost post) => !post.isAnswered).length;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppSizes.xxl),
        children: <Widget>[
          _Header(
            isClient: widget.isClient,
            unanswered: _unanswered,
            onAsk: openComposer,
          ),
          const SizedBox(height: AppSizes.lg),

          _SortRow(sort: _sort, onChanged: _setSort),
          const SizedBox(height: AppSizes.md),

          _TopicRow(selected: _topic, onChanged: _setTopic),
          const SizedBox(height: AppSizes.lg),

          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.screenPadding,
            ),
            child: _body(),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const SugoSkeletonList(count: 4);

    if (_error != null) {
      return SugoEmptyState.error(message: _error!, onAction: _load);
    }

    if (_posts.isEmpty) {
      return widget.isClient
          ? SugoEmptyState(
              icon: Icons.forum_rounded,
              title: _topic == null
                  ? 'No questions yet'
                  : 'Nothing under ${_topic!.label}',
              message: _topic == null
                  ? 'Ask the community anything about your device — '
                        'verified technicians answer here.'
                  : 'Be the first to ask about this, or browse another topic.',
              actionLabel: 'Ask a question',
              onAction: openComposer,
            )
          : SugoEmptyState(
              icon: Icons.question_answer_rounded,
              title: _topic == null
                  ? 'No questions yet'
                  : 'Nothing under ${_topic!.label}',
              // No action button: a technician cannot post, so offering one
              // would be a dead end.
              message:
                  'When a client asks something, it appears here. Answering '
                  'well earns you reputation points on your profile.',
            );
    }

    return Column(
      children: <Widget>[
        for (int i = 0; i < _posts.length; i++)
          _Entrance(
            index: i,
            child: CommunityPostCard(
              post: _posts[i],
              onTap: () => _open(_posts[i]),
              onDelete: _posts[i].isMine ? () => _delete(_posts[i]) : null,
            ),
          ),
      ],
    );
  }
}

/// Fades and lifts a row into place, staggered by its position.
///
/// Capped by [AppMotion.maxStaggerIndex], so a long feed does not animate its
/// twentieth row a second and a half late.
class _Entrance extends StatelessWidget {
  const _Entrance({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: AppMotion.slow,
      curve: AppMotion.standard,
      builder: (BuildContext context, double t, Widget? inner) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - t)),
            child: inner,
          ),
        );
      },
      child: child,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.isClient,
    required this.unanswered,
    required this.onAsk,
  });

  final bool isClient;
  final int unanswered;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPadding,
        AppSizes.lg,
        AppSizes.screenPadding,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Community', style: AppTextStyles.display),
                    const SizedBox(height: 2),
                    Text(
                      isClient
                          ? 'Ask anything. Verified technicians answer.'
                          : unanswered > 0
                          ? '$unanswered question${unanswered == 1 ? '' : 's'} '
                                'waiting for an answer'
                          : 'Answer questions to earn reputation points.',
                      style: AppTextStyles.subtitle,
                    ),
                  ],
                ),
              ),
              if (isClient) ...<Widget>[
                const SizedBox(width: AppSizes.md),
                _AskButton(onTap: onAsk),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _AskButton extends StatelessWidget {
  const _AskButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
        child: const Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSizes.md + 2,
            vertical: 10,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.edit_outlined, size: 15, color: Colors.white),
              SizedBox(width: 6),
              Text(
                'Ask',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Recent / Most Helpful, as a segmented control.
///
/// A segmented control rather than a dropdown: there are two options, both
/// worth showing, and a dropdown would hide half the choice behind a tap while
/// taking up the same room.
class _SortRow extends StatelessWidget {
  const _SortRow({required this.sort, required this.onChanged});

  final CommunitySort sort;
  final ValueChanged<CommunitySort> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.screenPadding),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.primarySofter,
          borderRadius: BorderRadius.circular(AppSizes.pillRadius),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: CommunitySort.values.map((CommunitySort option) {
            final bool active = option == sort;

            return Expanded(
              child: GestureDetector(
                onTap: () => onChanged(option),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: AppMotion.base,
                  curve: AppMotion.standard,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: active ? AppColors.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                    // The thumb rests on the track: a hairline edge rather
                    // than a shadow since the Dispatch redesign.
                    border: active
                        ? Border.all(color: AppColors.border)
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        option.icon,
                        size: 14,
                        color: active
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      // Flexible, because half of a 360dp screen is not much
                      // and "Most Helpful" is the longest label the control
                      // has. Without it the row overflows - by 18px in the
                      // test harness, and by however much a wide font or a
                      // large accessibility text scale adds on a real device.
                      Flexible(
                        child: Text(
                          option.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: active
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(growable: false),
        ),
      ),
    );
  }
}

/// Horizontally scrolling topic filter, with "All" pinned first.
class _TopicRow extends StatelessWidget {
  const _TopicRow({required this.selected, required this.onChanged});

  final CommunityTopic? selected;
  final ValueChanged<CommunityTopic?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.screenPadding,
        ),
        children: <Widget>[
          _Chip(
            label: 'All',
            icon: Icons.apps_rounded,
            active: selected == null,
            onTap: () => onChanged(null),
          ),
          for (final CommunityTopic topic in CommunityTopic.values)
            _Chip(
              label: topic.label,
              icon: topic.icon,
              active: selected == topic,
              onTap: () => onChanged(selected == topic ? null : topic),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSizes.sm),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSizes.pillRadius),
          child: AnimatedContainer(
            duration: AppMotion.base,
            curve: AppMotion.standard,
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.md + 2),
            decoration: BoxDecoration(
              color: active ? AppColors.primary : AppColors.surface,
              borderRadius: BorderRadius.circular(AppSizes.pillRadius),
              border: Border.all(
                color: active ? AppColors.primary : AppColors.border,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  icon,
                  size: 14,
                  color: active ? Colors.white : AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: active ? Colors.white : AppColors.textSecondary,
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
