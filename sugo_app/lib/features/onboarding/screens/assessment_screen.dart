import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_elevation.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_skeleton.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/sugo_app_bar.dart';
import '../../technician/models/assessment.dart';
import '../controllers/technician_registration_controller.dart';
import '../models/specialization_catalog.dart';
import '../services/technician_registration_service.dart';

/// One specialisation's assessment: question list, submit, result.
///
/// ## The app cannot mark this paper
///
/// `assessment_questions.correct_choice_index` was revoked from client roles in
/// migration 20260906000002, so the answer key is genuinely unreadable here -
/// not merely omitted from the select. Answers go to the `submit-assessment`
/// edge function, which reads the key on the service role, scores the attempt
/// and calls `record_assessment_result()`.
///
/// That is what makes the result trustworthy: a technician who tampers with
/// the app can change which answers are sent, never what they are worth.
class AssessmentScreen extends StatefulWidget {
  const AssessmentScreen({
    super.key,
    required this.assessment,
    required this.controller,
  });

  /// The track being sat, and how many specialisations it covers.
  final PendingAssessment assessment;

  final TechnicianRegistrationController controller;

  @override
  State<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends State<AssessmentScreen> {
  List<AssessmentQuestion> _questions = const <AssessmentQuestion>[];
  final Map<String, int> _answers = <String, int>{};

  bool _isLoading = true;
  bool _isSubmitting = false;
  AssessmentOutcome? _outcome;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<AssessmentQuestion>? questions = await widget.controller
        .loadQuestions(widget.assessment.track);

    if (!mounted) return;
    setState(() {
      _questions = questions ?? const <AssessmentQuestion>[];
      _error = questions == null ? widget.controller.error : null;
      _isLoading = false;
    });
  }

  bool get _isComplete => _answers.length == _questions.length;

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);

    final AssessmentOutcome? outcome = await widget.controller.submitAssessment(
      track: widget.assessment.track,
      answers: _answers,
    );

    if (!mounted) return;
    setState(() {
      _outcome = outcome;
      _error = outcome == null ? widget.controller.error : null;
      _isSubmitting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: SugoAppBar(title: widget.assessment.track.label),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_isLoading) {
      // Shaped like the questions that are coming, so the list does not jump
      // into place around a spinner that occupied none of its room.
      return const Padding(
        padding: EdgeInsets.all(AppSizes.screenPadding),
        child: Column(
          children: <Widget>[
            SugoSkeleton(height: 5, radius: AppSizes.pillRadius),
            SizedBox(height: AppSizes.xl),
            SugoSkeletonList(count: 3, showAvatar: false),
          ],
        ),
      );
    }
    if (_outcome != null) {
      return _ResultView(
        outcome: _outcome!,
        assessment: widget.assessment,
        onDone: () => Navigator.of(context).pop(),
      );
    }
    if (_error != null) {
      return _ErrorView(message: _error!, onRetry: _load);
    }

    return Column(
      children: <Widget>[
        _progressBar(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(AppSizes.screenPadding),
            itemCount: _questions.length,
            itemBuilder: (BuildContext context, int index) =>
                _questionCard(_questions[index], index),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(AppSizes.screenPadding),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            boxShadow: AppElevation.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (!_isComplete)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSizes.sm),
                  child: Text(
                    '${_questions.length - _answers.length} question'
                    '${_questions.length - _answers.length == 1 ? '' : 's'} left',
                    style: AppTextStyles.caption,
                  ),
                ),
              PrimaryButton(
                label: 'Submit answers',
                isLoading: _isSubmitting,
                // Every question must be answered. Partial submission would
                // score the blanks as wrong and burn one of the attempts that
                // the 24-hour cooldown makes expensive.
                onPressed: _isComplete && !_isSubmitting ? _submit : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _progressBar() {
    final double progress = _questions.isEmpty
        ? 0
        : _answers.length / _questions.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPadding,
        0,
        AppSizes.screenPadding,
        AppSizes.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '${_answers.length} of ${_questions.length} answered',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              const Spacer(),
              Text(
                '${SkillLevel.passMark.round()}% to pass',
                style: AppTextStyles.caption,
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          // Tweened rather than set, so answering a question visibly advances
          // the bar. A survey that fills as you go is measurably more likely
          // to be finished than one that only reports a count.
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSizes.pillRadius),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: progress),
              duration: AppMotion.slow,
              curve: AppMotion.emphasized,
              builder: (BuildContext context, double value, Widget? _) =>
                  LinearProgressIndicator(
                    value: value,
                    minHeight: AppSizes.stepRailHeight + 2,
                    backgroundColor: AppColors.divider,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _questionCard(AssessmentQuestion question, int index) {
    final int? chosen = _answers[question.id];

    final bool answered = chosen != null;

    return SugoCard(
      margin: const EdgeInsets.only(bottom: AppSizes.md),
      padding: const EdgeInsets.all(AppSizes.lg),
      radius: AppSizes.tileRadius,
      elevation: SugoElevation.sm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // The question number carries its own answered state. On a list of
          // ten questions this is what lets a technician scroll back and find
          // the one they skipped, instead of re-reading all of them.
          Row(
            children: <Widget>[
              Text(
                'Question ${index + 1}',
                style: AppTextStyles.overline.copyWith(
                  color: answered ? AppColors.success : AppColors.primary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 5),
              AnimatedScale(
                scale: answered ? 1 : 0,
                duration: AppMotion.base,
                curve: AppMotion.playful,
                child: const Icon(
                  Icons.check_circle_rounded,
                  size: 13,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            question.question,
            style: const TextStyle(
              fontSize: 15,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSizes.md),
          ...List<Widget>.generate(question.choices.length, (int i) {
            final bool selected = chosen == i;
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.sm),
              child: InkWell(
                onTap: () => setState(() => _answers[question.id] = i),
                borderRadius: BorderRadius.circular(AppSizes.sm),
                child: AnimatedContainer(
                  duration: AppMotion.fast,
                  curve: AppMotion.standard,
                  padding: const EdgeInsets.all(AppSizes.md),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primarySoft
                        : AppColors.fieldFill,
                    borderRadius: BorderRadius.circular(AppSizes.sm + 2),
                    border: Border.all(
                      color: selected ? AppColors.primary : AppColors.border,
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        selected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 17,
                        color: selected ? AppColors.primary : AppColors.hint,
                      ),
                      const SizedBox(width: AppSizes.sm),
                      Expanded(
                        child: Text(
                          question.choices[i],
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.3,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// The score, and what it earned.
class _ResultView extends StatelessWidget {
  const _ResultView({
    required this.outcome,
    required this.assessment,
    required this.onDone,
  });

  final AssessmentOutcome outcome;
  final PendingAssessment assessment;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final bool passed = outcome.passed;

    return Padding(
      padding: const EdgeInsets.all(AppSizes.screenPadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: passed ? AppColors.successSoft : AppColors.warningSoft,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              outcome.scoreLabel,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: passed ? AppColors.success : AppColors.warning,
              ),
            ),
          ),
          const SizedBox(height: AppSizes.xl),
          Text(
            passed ? 'Qualified' : 'Not this time',
            style: AppTextStyles.headline,
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            passed
                ? 'You are now listed as '
                      '${outcome.skillLevel?.label ?? 'qualified'} for '
                      '${assessment.track.label}.'
                : 'You needed ${outcome.pointsShort} more point'
                      '${outcome.pointsShort == 1 ? '' : 's'} to pass. '
                      'Your other assessments are unaffected.',
            textAlign: TextAlign.center,
            style: AppTextStyles.subtitle,
          ),

          // The payoff of grouping, said out loud: one sitting qualified them
          // for every brand they declared in this track.
          if (passed && outcome.specializationsVerified > 1) ...<Widget>[
            const SizedBox(height: AppSizes.md),
            Container(
              padding: const EdgeInsets.all(AppSizes.md),
              decoration: BoxDecoration(
                color: AppColors.successSoft,
                borderRadius: BorderRadius.circular(AppSizes.tileRadius),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.done_all_rounded,
                    size: 17,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(
                    child: Text(
                      'That one assessment qualified all '
                      '${outcome.specializationsVerified} of your '
                      '${assessment.track.label.toLowerCase()} '
                      'specialisations.',
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSizes.lg),

          Container(
            padding: const EdgeInsets.all(AppSizes.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSizes.tileRadius),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: <Widget>[
                _row(
                  'Correct',
                  '${outcome.correctCount} of ${outcome.totalQuestions}',
                ),
                _row('Attempt', '#${outcome.attemptNumber}'),
                if (!passed && outcome.retakeAvailableAt != null)
                  _row(
                    'Retake from',
                    _formatRetake(outcome.retakeAvailableAt!),
                  ),
              ],
            ),
          ),

          if (!passed) ...<Widget>[
            const SizedBox(height: AppSizes.lg),
            // The cooldown, explained rather than merely imposed. Its purpose
            // is to make studying the fastest route to passing, not to punish.
            const Text(
              'There is a 24-hour wait before a retake, so the quickest way '
              'through is to read up on the topics you missed.',
              textAlign: TextAlign.center,
              style: AppTextStyles.caption,
            ),
          ],

          const SizedBox(height: AppSizes.xxl),
          PrimaryButton(label: 'Back to assessments', onPressed: onDone),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label, style: AppTextStyles.caption),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  String _formatRetake(DateTime at) {
    final Duration left = at.difference(DateTime.now());
    if (left.isNegative) return 'Now';
    if (left.inHours > 0) {
      return 'in ${left.inHours}h ${left.inMinutes.remainder(60)}m';
    }
    return 'in ${left.inMinutes}m';
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSizes.screenPadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(
            Icons.error_outline_rounded,
            size: 34,
            color: AppColors.error,
          ),
          const SizedBox(height: AppSizes.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.subtitle,
          ),
          const SizedBox(height: AppSizes.xl),
          PrimaryButton(label: 'Try again', onPressed: onRetry),
        ],
      ),
    );
  }
}
