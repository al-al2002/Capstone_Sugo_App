import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/primary_button.dart';
import '../models/assessment.dart';

/// Step 4: the score, the verdict, and what happens next.
///
/// Passing already activated the account server-side before this screen was
/// built - `submit-assessment` set `tier` and `is_verified` in the same request
/// that marked the answers. So "Continue" here is not what grants access; it
/// just re-runs the router, which now finds `is_verified = true` and opens the
/// dashboard.
///
/// Failing records the attempt with `passed = false` and leaves `is_verified`
/// alone, so Retry simply sends them back to the quiz.
class AssessmentResultScreen extends StatelessWidget {
  const AssessmentResultScreen({
    super.key,
    required this.result,
    required this.onContinue,
    required this.onRetry,
  });

  final AssessmentResult result;

  /// Passed: proceed to the dashboard.
  final VoidCallback onContinue;

  /// Failed: back to the quiz.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final bool passed = result.passed;
    final Color accent = passed ? AppColors.success : AppColors.warning;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPadding,
        AppSizes.xl,
        AppSizes.screenPadding,
        AppSizes.xxl,
      ),
      children: <Widget>[
        Center(
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: passed ? AppColors.successSoft : AppColors.warningSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              passed ? Icons.verified_rounded : Icons.refresh_rounded,
              size: 46,
              color: accent,
            ),
          ),
        ),
        const SizedBox(height: AppSizes.lg),

        Text(
          passed ? 'You passed' : 'Not quite yet',
          textAlign: TextAlign.center,
          style: AppTextStyles.headline.copyWith(fontSize: 28),
        ),
        const SizedBox(height: AppSizes.xs),
        Text(
          passed
              ? 'Your account is verified and you can start receiving matched '
                    'jobs.'
              : 'You needed ${result.passThreshold.round()}% and scored '
                    '${result.scoreLabel}. You can retake it right away.',
          textAlign: TextAlign.center,
          style: AppTextStyles.subtitle,
        ),
        const SizedBox(height: AppSizes.xl),

        Container(
          padding: const EdgeInsets.all(AppSizes.lg),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSizes.panelRadius),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  _Figure(
                    value: result.scoreLabel,
                    label: 'Score',
                    color: accent,
                    emphasised: true,
                  ),
                  _Figure(
                    value: '${result.correctCount}/${result.totalQuestions}',
                    label: 'Correct',
                    color: AppColors.textPrimary,
                  ),
                  _Figure(
                    value: passed ? result.tierLabel : '-',
                    label: 'Tier awarded',
                    color: passed ? AppColors.primary : AppColors.hint,
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.lg),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                child: LinearProgressIndicator(
                  value: (result.score / 100).clamp(0, 1).toDouble(),
                  minHeight: 8,
                  backgroundColor: AppColors.divider,
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
              ),
              const SizedBox(height: AppSizes.sm),
              Text(
                'Pass mark ${result.passThreshold.round()}%   •   '
                '75% for Pro   •   90% for Elite',
                textAlign: TextAlign.center,
                style: AppTextStyles.caption.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSizes.xl),

        if (passed)
          _Panel(
            tint: AppColors.successSoft,
            border: AppColors.success,
            icon: Icons.check_circle_rounded,
            title: 'What happens now',
            body:
                'You start at ${result.tierLabel} tier. Your tier feeds the '
                'suitability score, so it affects where you rank when clients '
                'post jobs. Requests will start arriving on your dashboard.',
          )
        else
          _Panel(
            tint: AppColors.warningSoft,
            border: AppColors.warning,
            icon: Icons.lightbulb_outline_rounded,
            title: 'You were ${result.pointsShort} points short',
            body:
                'Nothing is lost. The attempt is recorded and you can retake '
                'the assessment as many times as you need. Your account stays '
                'unverified until you pass, so no jobs will be offered yet.',
          ),

        const SizedBox(height: AppSizes.xl),
        if (passed)
          PrimaryButton(label: 'Continue to dashboard', onPressed: onContinue)
        else
          PrimaryButton(label: 'Retry assessment', onPressed: onRetry),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.value,
    required this.label,
    required this.color,
    this.emphasised = false,
  });

  final String value;
  final String label;
  final Color color;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: emphasised ? 26 : 19,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.tint,
    required this.border,
    required this.icon,
    required this.title,
    required this.body,
  });

  final Color tint;
  final Color border;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(color: border.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 17, color: border),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: border,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            body,
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
