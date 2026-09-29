import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/primary_button.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../models/assessment.dart';
import '../services/onboarding_service.dart';

/// The skills assessment.
///
/// ## The screen cannot mark its own paper
///
/// `fetchQuestions` selects `id, specialization, question, choices` and nothing
/// else, because `correct_choice_index` is revoked from the `authenticated`
/// role. Asking for it returns `permission denied`.
///
/// The answers are handed up through [onAnswer] and held in memory. Submitting
/// posts them to `complete-registration`, which reads the answer key with the
/// service role, scores the attempt, and writes the account only if it passes.
/// That is what stops someone marking themselves 100% and self-activating as
/// elite.
///
/// Reading the question bank is the one database call the registration flow
/// makes before it commits, and it is a read of public reference data - no row
/// belonging to this person is created by it.
class QuizScreen extends StatefulWidget {
  const QuizScreen({
    super.key,
    required this.specialization,
    required this.answers,
    required this.onAnswer,
    required this.onSubmit,
    this.isSubmitting = false,
  });

  final Specialization specialization;
  final Map<String, int> answers;
  final void Function(String questionId, int choiceIndex) onAnswer;
  final VoidCallback onSubmit;
  final bool isSubmitting;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final OnboardingService _service = OnboardingService();

  List<AssessmentQuestion> _questions = <AssessmentQuestion>[];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final List<AssessmentQuestion> questions = await _service.fetchQuestions(
        widget.specialization,
      );
      if (!mounted) return;
      setState(() {
        _questions = questions;
        _isLoading = false;
      });
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure.message;
        _isLoading = false;
      });
    }
  }

  int get _answeredCount => widget.answers.length;

  bool get _allAnswered =>
      _questions.isNotEmpty && _answeredCount == _questions.length;

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.cloud_off_rounded,
                size: 40,
                color: AppColors.hint,
              ),
              const SizedBox(height: AppSizes.md),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: AppTextStyles.subtitle,
              ),
              const SizedBox(height: AppSizes.lg),
              OutlinedButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }

    if (_questions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.xxl),
          child: Text(
            'No questions are available for '
            '${widget.specialization.label.toLowerCase()} yet.',
            textAlign: TextAlign.center,
            style: AppTextStyles.subtitle,
          ),
        ),
      );
    }

    return Column(
      children: <Widget>[
        _ProgressBar(answered: _answeredCount, total: _questions.length),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.screenPadding,
              AppSizes.lg,
              AppSizes.screenPadding,
              AppSizes.xxl,
            ),
            children: <Widget>[
              Text(
                '${widget.specialization.label} assessment',
                style: AppTextStyles.headline,
              ),
              const SizedBox(height: AppSizes.xs),
              Text(
                'Answer all ${_questions.length} questions. You need 60% to '
                'pass, and your score sets your starting tier. Your account is '
                'created only once you pass.',
                style: AppTextStyles.subtitle,
              ),
              const SizedBox(height: AppSizes.xl),

              ...List<Widget>.generate(_questions.length, (int index) {
                final AssessmentQuestion question = _questions[index];
                return _QuestionCard(
                  number: index + 1,
                  question: question,
                  selected: widget.answers[question.id],
                  onSelect: (int choice) =>
                      widget.onAnswer(question.id, choice),
                );
              }),

              const SizedBox(height: AppSizes.lg),
              PrimaryButton(
                label: 'Submit assessment',
                isLoading: widget.isSubmitting,
                onPressed: _allAnswered ? widget.onSubmit : null,
              ),
              const SizedBox(height: AppSizes.sm),
              Text(
                _allAnswered
                    ? 'Your answers are marked on our servers.'
                    : 'Answer all ${_questions.length} questions to submit '
                          '($_answeredCount done).',
                textAlign: TextAlign.center,
                style: AppTextStyles.caption.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.answered, required this.total});

  final int answered;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.screenPadding),
      child: Row(
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSizes.pillRadius),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : answered / total,
                minHeight: 6,
                backgroundColor: AppColors.divider,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSizes.md),
          Text(
            '$answered/$total',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.number,
    required this.question,
    required this.selected,
    required this.onSelect,
  });

  final int number;
  final AssessmentQuestion question;
  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.lg),
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(
          color: selected == null ? AppColors.border : AppColors.primarySoft,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: selected == null
                      ? AppColors.divider
                      : AppColors.primary,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$number',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected == null
                        ? AppColors.textSecondary
                        : Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Text(
                  question.question,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          ...List<Widget>.generate(question.choices.length, (int index) {
            final bool active = selected == index;
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.sm),
              child: InkWell(
                onTap: () => onSelect(index),
                borderRadius: BorderRadius.circular(AppSizes.md),
                child: Container(
                  padding: const EdgeInsets.all(AppSizes.md),
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.primarySofter
                        : AppColors.background,
                    borderRadius: BorderRadius.circular(AppSizes.md),
                    border: Border.all(
                      color: active ? AppColors.primary : AppColors.border,
                      width: active ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        active
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 18,
                        color: active ? AppColors.primary : AppColors.border,
                      ),
                      const SizedBox(width: AppSizes.md),
                      Expanded(
                        child: Text(
                          question.choices[index],
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.w400,
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
