import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../theme/app_motion.dart';
import '../theme/app_text_styles.dart';

/// The progress rail shared by every multi-step flow in the app.
///
/// ## Why one widget for two different flows
///
/// Posting a job and registering an account are unrelated features with
/// unrelated step models - one is five fixed screens, the other is a
/// role-dependent list that can be resumed part-finished. Before the
/// renovation they each drew their own rail, and the two drifted: different
/// segment heights, different gaps, one animated and one not.
///
/// A user does not experience them as two features. They experience "this app
/// shows me how far through I am", and that impression is only as strong as
/// its weakest copy. So the *rail* is shared and the *step semantics* stay
/// with each flow - [OnboardingStepper] still owns its lock-and-tick logic and
/// simply renders this underneath.
///
/// ## The travelling fill
///
/// Segments do not switch colour on arrival; the active one fills from left to
/// right over [AppMotion.slow]. The distinction matters on a five-step flow:
/// a segment that snaps to blue says "you are on step three", while one that
/// fills says "you are moving through step three", and the second is what
/// makes a long registration feel like it is going somewhere.
class SugoStepRail extends StatelessWidget {
  const SugoStepRail({
    super.key,
    required this.currentIndex,
    required this.stepCount,
    this.completed,
    this.activeColor = AppColors.primary,
    this.completeColor = AppColors.success,
    this.gap = 6,
  });

  /// Zero-based position in the flow.
  final int currentIndex;

  final int stepCount;

  /// Which steps count as finished. Defaults to "everything before the current
  /// index", which is right for a linear flow - but registration can be
  /// resumed with an earlier step still outstanding, so it passes its own set
  /// rather than letting the rail assume.
  final bool Function(int index)? completed;

  final Color activeColor;
  final Color completeColor;
  final double gap;

  bool _isComplete(int index) =>
      completed?.call(index) ?? (index < currentIndex);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step ${currentIndex + 1} of $stepCount',
      child: Row(
        children: List<Widget>.generate(stepCount, (int index) {
          final bool done = _isComplete(index);
          final bool active = index == currentIndex;

          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: index == stepCount - 1 ? 0 : gap),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                child: Stack(
                  children: <Widget>[
                    Container(
                      height: AppSizes.stepRailHeight,
                      color: AppColors.divider,
                    ),
                    // A finished segment is filled outright; the current one
                    // animates its width from zero. Future steps stay at 0.
                    AnimatedFractionallySizedBox(
                      duration: AppMotion.slow,
                      curve: AppMotion.emphasized,
                      widthFactor: done
                          ? 1
                          : active
                          ? 1
                          : 0,
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: AppSizes.stepRailHeight,
                        decoration: BoxDecoration(
                          color: done ? completeColor : activeColor,
                          borderRadius: BorderRadius.circular(
                            AppSizes.pillRadius,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// "Step 2 of 5" with the current step's name, sitting above a [SugoStepRail].
///
/// Naming the step as well as numbering it is what turns a progress bar into
/// an orientation aid: "3 of 5" tells you how much is left, "Where and when"
/// tells you what you are being asked, and a flow needs both.
class SugoStepLabel extends StatelessWidget {
  const SugoStepLabel({
    super.key,
    required this.currentIndex,
    required this.stepCount,
    required this.label,
    this.accent = AppColors.primary,
  });

  final int currentIndex;
  final int stepCount;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppSizes.pillRadius),
          ),
          child: Text(
            'Step ${currentIndex + 1} of $stepCount',
            style: AppTextStyles.overline.copyWith(
              color: accent,
              letterSpacing: 0.4,
            ),
          ),
        ),
        const SizedBox(width: AppSizes.sm),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: AppTextStyles.micro.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
