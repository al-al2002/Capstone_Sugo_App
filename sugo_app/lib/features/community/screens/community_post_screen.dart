import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_elevation.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_empty_state.dart';
import '../../../core/widgets/sugo_image_viewer.dart';
import '../../../core/widgets/sugo_skeleton.dart';
import '../../../core/widgets/sugo_app_bar.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../models/community_models.dart';
import '../services/community_service.dart';
import '../widgets/community_answer_card.dart';
import '../widgets/community_author_row.dart';

/// One question and its answers.
///
/// ## Who sees the composer
///
/// The answer box is shown to everyone the database would accept an answer
/// from, which in practice means everyone signed in - but the *framing*
/// changes by role. A technician is told their answer earns reputation; a
/// client replying on their own thread is not, because it does not.
///
/// The alternative - hiding the box from clients entirely - was rejected
/// because a client clarifying their own question ("sorry, it is the 2019
/// model") is a normal and useful thing to do, and blocking it would push that
/// conversation into a second question.
class CommunityPostScreen extends StatefulWidget {
  const CommunityPostScreen({super.key, required this.post});

  final CommunityPost post;

  @override
  State<CommunityPostScreen> createState() => _CommunityPostScreenState();
}

class _CommunityPostScreenState extends State<CommunityPostScreen> {
  final CommunityService _service = CommunityService();
  final TextEditingController _reply = TextEditingController();
  final ScrollController _scroll = ScrollController();

  late CommunityPost _post = widget.post;
  List<CommunityAnswer> _answers = const <CommunityAnswer>[];
  CommunitySort _sort = CommunitySort.mostHelpful;

  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final List<CommunityAnswer> answers = await _service.answers(
        _post.id,
        sort: _sort,
      );
      if (!mounted) return;
      setState(() {
        _answers = answers;
        _loading = false;
        _error = null;
      });
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure.message;
        _loading = false;
      });
    }
  }

  /// Re-reads the post row too, so the answer count in the header stays true.
  Future<void> _refresh() async {
    final CommunityPost? fresh = await _service.post(_post.id).catchError(
      (_) => null,
    );
    if (!mounted) return;
    if (fresh != null) setState(() => _post = fresh);
    await _load();
  }

  void _setSort(CommunitySort sort) {
    if (_sort == sort) return;
    setState(() => _sort = sort);
    _load();
  }

  /// Rates an answer.
  ///
  /// Applied locally first, then sent. A vote that waits for a round trip
  /// before the button responds feels broken on a slow connection, and the
  /// server is the authority either way - a failure restores the old row and
  /// says why.
  Future<void> _toggleHelpful(CommunityAnswer answer, bool helpful) async {
    final int index = _answers.indexWhere(
      (CommunityAnswer row) => row.id == answer.id,
    );
    if (index < 0) return;

    final List<CommunityAnswer> optimistic = List<CommunityAnswer>.of(_answers);
    optimistic[index] = answer.toggledVote();
    setState(() => _answers = optimistic);

    try {
      await _service.setHelpful(answerId: answer.id, helpful: helpful);
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;

      final List<CommunityAnswer> reverted = List<CommunityAnswer>.of(_answers);
      // Re-found rather than reused: the list may have been re-sorted by a
      // refresh while the request was in flight.
      final int at = reverted.indexWhere(
        (CommunityAnswer row) => row.id == answer.id,
      );
      if (at >= 0) reverted[at] = answer;

      setState(() => _answers = reverted);
      UiFeedback.showError(context, failure.message);
    }
  }

  Future<void> _send() async {
    final String body = _reply.text.trim();
    if (body.isEmpty || _sending) return;

    setState(() => _sending = true);

    try {
      await _service.answer(postId: _post.id, body: body);
      if (!mounted) return;
      _reply.clear();
      FocusScope.of(context).unfocus();
      setState(() => _sending = false);
      await _refresh();
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      setState(() => _sending = false);
      UiFeedback.showError(context, failure.message);
    }
  }

  Future<void> _deleteAnswer(CommunityAnswer answer) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Delete this answer?'),
        content: Text(
          answer.helpfulCount > 0
              // Worth saying plainly: the points go with it.
              ? 'It has been rated helpful ${answer.helpfulCount} '
                    '${answer.helpfulCount == 1 ? 'time' : 'times'}, and the '
                    'reputation points it earned will be removed too.'
              : 'This cannot be undone.',
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
      await _service.deleteAnswer(answer.id);
      if (!mounted) return;
      await _refresh();
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      UiFeedback.showError(context, failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const SugoAppBar(title: 'Question'),
      body: Column(
        children: <Widget>[
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.screenPadding,
                  0,
                  AppSizes.screenPadding,
                  AppSizes.xl,
                ),
                children: <Widget>[
                  _QuestionCard(post: _post),
                  const SizedBox(height: AppSizes.xl),
                  _AnswersHeader(
                    count: _answers.length,
                    sort: _sort,
                    onSortChanged: _setSort,
                  ),
                  const SizedBox(height: AppSizes.md),
                  _answerList(),
                ],
              ),
            ),
          ),
          _ReplyBar(
            controller: _reply,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  Widget _answerList() {
    if (_loading) return const SugoSkeletonList(count: 2);

    if (_error != null) {
      return SugoEmptyState.error(message: _error!, onAction: _load);
    }

    if (_answers.isEmpty) {
      return const SugoEmptyState(
        icon: Icons.lightbulb_outline_rounded,
        title: 'No answers yet',
        message:
            'Nobody has answered this one. If you know the answer, yours '
            'will be the first.',
        compact: true,
      );
    }

    return Column(
      children: <Widget>[
        for (int i = 0; i < _answers.length; i++)
          CommunityAnswerCard(
            // Keyed by id so re-sorting animates rows rather than rebuilding
            // them in place - without this, switching sort order makes every
            // vote button flicker through the wrong state.
            key: ValueKey<String>(_answers[i].id),
            answer: _answers[i],
            onToggleHelpful: (bool helpful) =>
                _toggleHelpful(_answers[i], helpful),
            onDelete: _answers[i].isMine
                ? () => _deleteAnswer(_answers[i])
                : null,
          ),
      ],
    );
  }
}

/// The question itself, at the top of the thread.
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.post});

  final CommunityPost post;

  @override
  Widget build(BuildContext context) {
    return SugoCard(
      padding: const EdgeInsets.all(AppSizes.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(AppSizes.pillRadius),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(post.topic.icon, size: 11, color: AppColors.primaryDark),
                const SizedBox(width: 4),
                Text(
                  post.topic.label,
                  style: AppTextStyles.overline.copyWith(
                    color: AppColors.primaryDark,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          Text(post.title, style: AppTextStyles.title.copyWith(fontSize: 20)),
          const SizedBox(height: AppSizes.sm),
          Text(post.body, style: AppTextStyles.body),

          // Full width here, unlike the thumbnail on the feed card. This is
          // the screen where a technician is actually trying to read the
          // fault off the picture, so it gets the space - and a tap opens the
          // same zoomable viewer the job photos use, because "is that a
          // capacitor or a burn mark" is a question that needs pinch-zoom.
          if (CommunityService.publicPhotoUrl(post.imagePath) case final String url) ...<Widget>[
            const SizedBox(height: AppSizes.md),
            _QuestionPhoto(url: url),
          ],

          const SizedBox(height: AppSizes.lg),
          const Divider(height: 1),
          const SizedBox(height: AppSizes.md),
          CommunityAuthorRow(
            author: post.author,
            timestamp: post.createdAt,
            dense: true,
          ),
        ],
      ),
    );
  }
}

/// The question's photo, tappable into the shared zoomable viewer.
class _QuestionPhoto extends StatelessWidget {
  const _QuestionPhoto({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => openSugoImageViewer(context, urls: <String>[url]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        child: ConstrainedBox(
          // Capped rather than free: a portrait photo from a phone camera is
          // three times taller than it is wide, and unconstrained it would
          // push the answers - the reason this screen exists - off the first
          // screenful entirely.
          constraints: const BoxConstraints(maxHeight: 320),
          child: Image.network(
            url,
            width: double.infinity,
            fit: BoxFit.cover,
            loadingBuilder:
                (BuildContext context, Widget child, ImageChunkEvent? loading) {
                  if (loading == null) return child;
                  return const SugoSkeleton(height: 180, width: double.infinity);
                },
            errorBuilder:
                (BuildContext context, Object error, StackTrace? stack) {
                  return Container(
                    height: 120,
                    color: AppColors.fieldFill,
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(
                          Icons.broken_image_outlined,
                          size: 18,
                          color: AppColors.hint,
                        ),
                        const SizedBox(width: AppSizes.sm),
                        Text(
                          'Photo could not be loaded',
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ),
                  );
                },
          ),
        ),
      ),
    );
  }
}

class _AnswersHeader extends StatelessWidget {
  const _AnswersHeader({
    required this.count,
    required this.sort,
    required this.onSortChanged,
  });

  final int count;
  final CommunitySort sort;
  final ValueChanged<CommunitySort> onSortChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(
          count == 1 ? '1 answer' : '$count answers',
          style: AppTextStyles.sectionTitle,
        ),
        const Spacer(),
        // Hidden below two answers: there is nothing to sort, and a control
        // that cannot change anything is noise.
        if (count > 1)
          PopupMenuButton<CommunitySort>(
            initialValue: sort,
            onSelected: onSortChanged,
            tooltip: 'Sort answers',
            position: PopupMenuPosition.under,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.tileRadius),
            ),
            itemBuilder: (_) => CommunitySort.values
                .map(
                  (CommunitySort option) => PopupMenuItem<CommunitySort>(
                    value: option,
                    child: Row(
                      children: <Widget>[
                        Icon(
                          option.icon,
                          size: 15,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: AppSizes.sm),
                        Text(option.label, style: AppTextStyles.field),
                      ],
                    ),
                  ),
                )
                .toList(growable: false),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.md,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(sort.icon, size: 13, color: AppColors.textSecondary),
                  const SizedBox(width: 5),
                  Text(
                    sort.label,
                    style: AppTextStyles.micro.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Icon(
                    Icons.expand_more_rounded,
                    size: 15,
                    color: AppColors.hint,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The answer composer, pinned below the thread.
///
/// Pinned rather than placed at the end of the list so it is reachable without
/// scrolling past every existing answer - which on a popular question is the
/// difference between a reply and no reply.
class _ReplyBar extends StatefulWidget {
  const _ReplyBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  State<_ReplyBar> createState() => _ReplyBarState();
}

class _ReplyBarState extends State<_ReplyBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final bool canSend =
        widget.controller.text.trim().isNotEmpty && !widget.sending;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPadding,
        AppSizes.md,
        AppSizes.screenPadding,
        AppSizes.md,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        boxShadow: AppElevation.navBar,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: ConstrainedBox(
                // Grows with the answer up to a ceiling, then scrolls. A
                // single-line box discourages the considered answers the feed
                // is for; an unbounded one would eventually eat the thread.
                constraints: const BoxConstraints(maxHeight: 120),
                child: TextField(
                  controller: widget.controller,
                  minLines: 1,
                  maxLines: null,
                  maxLength: 4000,
                  textCapitalization: TextCapitalization.sentences,
                  style: AppTextStyles.field,
                  decoration: const InputDecoration(
                    hintText: 'Write an answer…',
                    counterText: '',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: AppSizes.lg,
                      vertical: AppSizes.md,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            _SendButton(
              enabled: canSend,
              sending: widget.sending,
              onTap: widget.onSend,
            ),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.sending,
    required this.onTap,
  });

  final bool enabled;
  final bool sending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.base,
      curve: AppMotion.standard,
      width: AppSizes.buttonHeight,
      height: AppSizes.buttonHeight,
      decoration: BoxDecoration(
        color: enabled ? AppColors.primary : AppColors.divider,
        borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
          child: Center(
            child: sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Icon(
                    Icons.send_rounded,
                    size: 19,
                    color: enabled ? Colors.white : AppColors.hint,
                  ),
          ),
        ),
      ),
    );
  }
}
