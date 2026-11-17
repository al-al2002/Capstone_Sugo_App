import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/widgets/sugo_empty_state.dart';
import '../../../core/widgets/sugo_motion.dart';
import '../../../core/widgets/sugo_image_viewer.dart';
import '../../../core/widgets/sugo_skeleton.dart';
import '../../../core/widgets/sugo_app_bar.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../../rb_cars/models/job_enums.dart';
import '../../rb_cars/models/job.dart';
import '../../rb_cars/screens/client_review_screen.dart';
import '../models/community_models.dart';
import '../services/community_service.dart';
import '../widgets/community_answer_card.dart';
import '../widgets/community_author_row.dart';
import '../widgets/find_technician_button.dart';

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
  const CommunityPostScreen({
    super.key,
    required this.post,
    this.isClient = false,
    this.onChooseService,
    @visibleForTesting this.service,
  });

  /// Tests only (2026-11-17): a fake, so the thread renders offline.
  final CommunityService? service;

  final CommunityPost post;
  final bool isClient;
  final Future<void> Function(ServicePath path)? onChooseService;

  @override
  State<CommunityPostScreen> createState() => _CommunityPostScreenState();
}

class _CommunityPostScreenState extends State<CommunityPostScreen> {
  late final CommunityService _service = widget.service ?? CommunityService();
  final TextEditingController _reply = TextEditingController();
  final ScrollController _scroll = ScrollController();

  late CommunityPost _post = widget.post;
  List<CommunityAnswer> _answers = const <CommunityAnswer>[];
  CommunitySort _sort = CommunitySort.mostHelpful;

  bool _loading = true;
  bool _sending = false;
  bool _converting = false;
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
    final CommunityPost? fresh = await _service
        .post(_post.id)
        .catchError((_) => null);
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

  Future<void> _convertTask(ServicePath path) async {
    if (_converting || !_post.cameFromTaskPost) return;
    setState(() => _converting = true);
    try {
      final List<Job> jobs = await RbCarsService().myJobs();
      final String? symptom = RegExp(
        r'\n\nSymptom:\s*([^.]+)\.',
      ).firstMatch(_post.body)?.group(1)?.trim();
      final Job job = jobs.firstWhere(
        (Job row) =>
            row.id == _post.sourceJobId ||
            (symptom != null && row.problemSymptom == symptom),
      );
      final JobDraft draft = JobDraft.fromJob(job)..servicePathOverride = path;
      final RbCarsService service = RbCarsService();
      final Job updated = await service.updateJob(job.id, draft);
      await service.runMatching(updated.id);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ClientReviewScreen(jobId: updated.id),
        ),
      );
    } on RbCarsFailure catch (failure) {
      if (mounted) UiFeedback.showError(context, failure.message);
    } catch (_) {
      if (mounted) {
        UiFeedback.showError(
          context,
          'Could not switch this post to a service.',
        );
      }
    } finally {
      if (mounted) setState(() => _converting = false);
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
          if (widget.isClient &&
              (widget.onChooseService != null ||
                  _post.cameFromTaskPost)) ...<Widget>[
            _ClientServiceFallback(
              onChooseService: widget.onChooseService ?? _convertTask,
              converting: _converting,
            ),
          ],
          _ReplyBar(controller: _reply, sending: _sending, onSend: _send),
        ],
      ),
    );
  }

  Widget _answerList() {
    if (_loading) return const SugoSkeletonList(count: 2);

    if (_error != null) {
      return SugoEmptyState.error(message: _error!, onAction: _load);
    }

    if (_answers.isEmpty) return const _NoAnswers();

    return Column(
      children: <Widget>[
        for (int i = 0; i < _answers.length; i++)
          // Rises in once per answer (2026-11-17): the thread deals in when
          // it opens, a newly posted answer rises into place, and a re-sort
          // moves existing rows without replaying them, because the key is
          // the answer.
          SugoRiseIn(
            key: ValueKey<String>('rise-${_answers[i].id}'),
            delay: AppMotion.staggerDelay(i),
            child: CommunityAnswerCard(
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
          ),
      ],
    );
  }
}

class _ClientServiceFallback extends StatelessWidget {
  const _ClientServiceFallback({
    required this.onChooseService,
    this.converting = false,
  });

  final Future<void> Function(ServicePath path) onChooseService;
  final bool converting;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPadding,
        AppSizes.sm,
        AppSizes.screenPadding,
        AppSizes.sm,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        // One button, "Still not fixed? Find a technician" (2026-11-16): it
        // opens Home Service / Shop Repair and converts this post without
        // retyping anything.
        child: FindTechnicianButton(
          onChooseService: onChooseService,
          converting: converting,
        ),
      ),
    );
  }
}

/// The question itself, at the top of the thread.
///
/// Since 2026-11-17 it opens on the brand band - topic, title, and whether it
/// has been answered - with the words, the photo and the asker below on
/// white. The band is the same one every renovated screen opens with.
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.post});

  final CommunityPost post;

  @override
  Widget build(BuildContext context) {
    const Radius corner = Radius.circular(AppSizes.cardRadius);
    final bool answered = post.isAnswered;

    return SugoRiseIn(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.all(corner),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SugoHeroBand(
              borderRadius: const BorderRadius.vertical(top: corner),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // A Wrap, so on a small phone at large text the status
                  // pill drops under the topic instead of overflowing.
                  Wrap(
                    spacing: AppSizes.sm,
                    runSpacing: AppSizes.xs + 2,
                    children: <Widget>[
                      _GlassPill(
                        icon: post.topic.icon,
                        label: post.topic.label,
                      ),
                      _GlassPill(
                        icon: answered
                            ? Icons.check_circle_rounded
                            : Icons.hourglass_bottom_rounded,
                        label: answered
                            ? 'Answered · ${post.commentCount}'
                            : 'Waiting for an answer',
                        tint: answered
                            ? const Color(0xFF4ADE80)
                            : AppColors.accent,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSizes.md),
                  Text(
                    post.title,
                    style: AppTextStyles.title.copyWith(
                      fontSize: 20,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSizes.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(post.body, style: AppTextStyles.body),

                  // Full width here, unlike the thumbnail on the feed card.
                  // This is the screen where a technician is actually trying
                  // to read the fault off the picture, so it gets the space -
                  // and a tap opens the same zoomable viewer the job photos
                  // use, because "is that a capacitor or a burn mark" is a
                  // question that needs pinch-zoom.
                  if (CommunityService.publicPhotoUrl(post.imagePath)
                      case final String url) ...<Widget>[
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
            ),
          ],
        ),
      ),
    );
  }
}

/// A small frosted pill on the band: an icon in [tint] and a white label.
class _GlassPill extends StatelessWidget {
  const _GlassPill({
    required this.icon,
    required this.label,
    this.tint = Colors.white,
  });

  final IconData icon;
  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: tint),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.micro.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
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
                  return const SugoSkeleton(
                    height: 180,
                    width: double.infinity,
                  );
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
    // The count takes the free space and the sort button may shrink
    // (2026-11-17): side by side at fixed widths they overflowed a small
    // phone at large text.
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            count == 1 ? '1 answer' : '$count answers',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.sectionTitle,
          ),
        ),
        // Hidden below two answers: there is nothing to sort, and a control
        // that cannot change anything is noise.
        if (count > 1)
          Flexible(
            child: PopupMenuButton<CommunitySort>(
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
                    Flexible(
                      child: Text(
                        sort.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.micro.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
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
      // A floating tray, like the chat composer (2026-11-17).
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppSizes.sheetRadius),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
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

/// The reply's send button: the brand gradient, leaning forward when there is
/// an answer to send (2026-11-17), the same as the chat's.
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
    return AnimatedRotation(
      turns: enabled ? -0.06 : 0,
      duration: AppMotion.base,
      curve: AppMotion.emphasized,
      child: AnimatedContainer(
        duration: AppMotion.base,
        curve: AppMotion.standard,
        width: AppSizes.buttonHeight,
        height: AppSizes.buttonHeight,
        decoration: BoxDecoration(
          gradient: enabled || sending
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[AppColors.primary, AppColors.secondary],
                )
              : null,
          color: enabled || sending ? null : AppColors.divider,
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
      ),
    );
  }
}

/// No answers yet: a lightbulb that swings once, then the invitation.
class _NoAnswers extends StatelessWidget {
  const _NoAnswers();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.lg),
      child: Column(
        children: <Widget>[
          SugoRiseIn(
            child: Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[AppColors.accentSoft, AppColors.accentSofter],
                ),
              ),
              child: const SugoWiggle(
                swings: 2,
                angle: 0.25,
                child: Icon(
                  Icons.lightbulb_rounded,
                  size: 36,
                  color: AppColors.accent,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSizes.md),
          SugoRiseIn(
            delay: AppMotion.staggerDelay(2),
            child: Column(
              children: <Widget>[
                Text(
                  'No answers yet',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.titleSmall,
                ),
                const SizedBox(height: AppSizes.xs),
                Text(
                  'Nobody has answered this one. If you know the answer, '
                  'yours will be the first.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
