import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/widgets/sugo_empty_state.dart';
import '../../../core/widgets/sugo_motion.dart';
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
///
/// Renovated 2026-11-17 ("Dispatch, levelled up"): a summary band like every
/// other list in the app, the shared sliding control for the sort, topic
/// chips that pop when chosen, questions that deal in (every load replays it,
/// because a new sort or topic is a new list), and animated empty states.
class CommunityFeedView extends StatefulWidget {
  const CommunityFeedView({
    super.key,
    required this.isClient,
    @visibleForTesting this.service,
  });

  /// Tests only (2026-11-17), so the feed can be rendered with questions in
  /// it rather than only in its offline error state.
  final CommunityService? service;

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
  late final CommunityService _service = widget.service ?? CommunityService();

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
        builder: (_) =>
            CommunityPostScreen(post: post, isClient: widget.isClient),
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
          ? _EmptyCommunity(
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
          : _EmptyCommunity(
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
          SugoRiseIn(
            // Keyed by sort and topic as well as the post, so each new list
            // deals in afresh.
            key: ValueKey<String>(
              '${_sort.name}-${_topic?.name}-${_posts[i].id}',
            ),
            delay: AppMotion.staggerDelay(i),
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

/// The feed's summary band (2026-11-17): the same navy band as every other
/// list, with the one role difference that matters here on the right - a
/// client's Ask button, or the count of questions a technician could answer.
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
      child: SugoRiseIn(
        child: SugoHeroBand(
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Community',
                      style: AppTextStyles.display.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isClient
                          ? 'Ask anything. Verified technicians answer.'
                          : unanswered > 0
                          ? '$unanswered question${unanswered == 1 ? '' : 's'} '
                                'waiting for an answer'
                          : 'Answer questions to earn reputation points.',
                      style: AppTextStyles.subtitle.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSizes.md),
              if (isClient)
                _AskButton(onTap: onAsk)
              else if (unanswered > 0)
                _WaitingBubble(count: unanswered),
            ],
          ),
        ),
      ),
    );
  }
}

/// White on the navy band, so the one action on the screen is the brightest
/// thing on it.
class _AskButton extends StatelessWidget {
  const _AskButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
        child: const Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSizes.md + 2,
            vertical: 11,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.edit_rounded, size: 15, color: AppColors.primary),
              SizedBox(width: 6),
              Text(
                'Ask',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The technician's side of the band: how many questions are waiting.
class _WaitingBubble extends StatelessWidget {
  const _WaitingBubble({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 74,
      padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSizes.radius + 4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SugoCountUp(
            value: count,
            style: const TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 24,
              height: 1.1,
              fontWeight: FontWeight.w800,
              color: AppColors.accentDark,
            ),
          ),
          Text(
            'to answer',
            style: AppTextStyles.micro.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Recent / Most Helpful, as a segmented control.
///
/// A segmented control rather than a dropdown: there are two options, both
/// worth showing, and a dropdown would hide half the choice behind a tap while
/// taking up the same room. Since 2026-11-17 the shared [SugoSegmentedFilter],
/// whose highlight slides - the same control as the inbox and the bookings.
/// Its labels shrink to fit, which covers the "Most Helpful" overflow the old
/// control had to guard against by hand.
class _SortRow extends StatelessWidget {
  const _SortRow({required this.sort, required this.onChanged});

  final CommunitySort sort;
  final ValueChanged<CommunitySort> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.screenPadding),
      child: SugoSegmentedFilter<CommunitySort>(
        selected: sort,
        onChanged: onChanged,
        segments: <SugoSegment<CommunitySort>>[
          for (final CommunitySort option in CommunitySort.values)
            SugoSegment<CommunitySort>(value: option, label: option.label),
        ],
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
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.screenPadding),
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
          // The chosen topic pops a little (2026-11-17).
          child: AnimatedScale(
            scale: active ? 1.05 : 1,
            duration: AppMotion.base,
            curve: AppMotion.playful,
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
      ),
    );
  }
}

/// An empty feed: its icon swinging once on a gradient disc, then the words,
/// then the action when the reader is allowed one.
class _EmptyCommunity extends StatelessWidget {
  const _EmptyCommunity({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const SizedBox(height: AppSizes.lg),
        SugoRiseIn(
          child: Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[AppColors.primarySoft, AppColors.cyanSoft],
              ),
            ),
            child: SugoWiggle(
              swings: 2,
              angle: 0.22,
              alignment: Alignment.bottomCenter,
              child: Icon(icon, size: 42, color: AppColors.primary),
            ),
          ),
        ),
        const SizedBox(height: AppSizes.lg),
        SugoRiseIn(
          delay: AppMotion.staggerDelay(2),
          child: Column(
            children: <Widget>[
              Text(
                title,
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
        if (actionLabel != null && onAction != null) ...<Widget>[
          const SizedBox(height: AppSizes.xl),
          SugoRiseIn(
            delay: AppMotion.staggerDelay(4),
            child: FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.edit_rounded, size: 17),
              label: Text(actionLabel!),
            ),
          ),
        ],
      ],
    );
  }
}
