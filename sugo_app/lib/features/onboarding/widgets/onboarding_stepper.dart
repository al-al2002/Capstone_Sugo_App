import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_motion.dart';
import '../models/registration_status.dart';

/// The progress rail at the top of both onboarding flows.
///
/// Shows every step rather than only the current one. A seven-step technician
/// registration feels endless when each screen arrives unannounced; showing
/// the whole shape up front - and which parts are already done - is what makes
/// it feel finite.
///
/// The mandatory ID step is marked with a lock rather than a number when it is
/// still outstanding, because a numbered step reads as "one of several" while
/// a lock reads as "this one is the gate". That is the honest signal: nothing
/// past it is reachable.
///
/// ## The Dispatch stepper (2026-09-29)
///
/// Each segment used to carry its step's name in 9.5px type. At seven steps
/// on a phone a segment is about 45px wide, so at the type scale's 12px floor
/// the names were cut to "Ac…" - and the current step's name is already
/// spelled out in full just above the rail. So a segment is now the rail and
/// an icon that says its state; the name is still spoken to screen readers.
/// Finished steps are SUGO blue, like the distance already covered on the
/// route line, rather than green.
///
/// ## On the brand band (2026-11-17)
///
/// The renovation puts the rail on the same navy band every renovated screen
/// opens with: "Step 3 of 7", the step's name, a ring showing how much of the
/// registration is done, and the segments in white - cyan once finished. The
/// ring and the segments animate as steps complete; under reduced motion they
/// simply change.
class OnboardingStepper extends StatelessWidget {
  const OnboardingStepper({
    super.key,
    required this.steps,
    required this.currentIndex,
    required this.completedSteps,
    this.onStepTapped,
  });

  final List<OnboardingStepId> steps;
  final int currentIndex;

  /// Steps already satisfied. Not simply "everything before the current
  /// index": a resumed flow can land the user on step 5 with step 4 still
  /// outstanding, and pretending otherwise would hide real work.
  final Set<OnboardingStepId> completedSteps;

  /// Tapping a step navigates back to it. Null disables navigation, which the
  /// host does while a submission is in flight.
  final ValueChanged<int>? onStepTapped;

  @override
  Widget build(BuildContext context) {
    final int done = steps.where(completedSteps.contains).length;
    final Duration swap = AppMotion.reduced(context)
        ? Duration.zero
        : AppMotion.base;

    return SugoHeroBand(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.lg,
        AppSizes.md + 2,
        AppSizes.lg,
        AppSizes.sm,
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
                    // The same words the posting flow uses, so a user who
                    // has posted a job recognises the shape of a SUGO
                    // multi-step flow immediately.
                    Text(
                      'Step ${currentIndex + 1} of ${steps.length}',
                      style: AppTextStyles.overline.copyWith(
                        color: Colors.white.withValues(alpha: 0.72),
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    AnimatedSwitcher(
                      duration: swap,
                      transitionBuilder: (Widget child, Animation<double> a) =>
                          FadeTransition(
                            opacity: a,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.35),
                                end: Offset.zero,
                              ).animate(a),
                              child: child,
                            ),
                          ),
                      child: Text(
                        steps[currentIndex].label,
                        key: ValueKey<OnboardingStepId>(steps[currentIndex]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 20,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSizes.md),
              _ProgressRing(done: done, total: steps.length),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          Row(
            children: List<Widget>.generate(steps.length, (int i) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: i == steps.length - 1 ? 0 : 4,
                  ),
                  child: _Segment(
                    step: steps[i],
                    isCurrent: i == currentIndex,
                    isComplete: completedSteps.contains(steps[i]),
                    // Only a completed step is navigable. Allowing a jump
                    // forward would let someone reach the assessment without
                    // choosing a specialisation first.
                    onTap:
                        (onStepTapped != null &&
                            completedSteps.contains(steps[i]) &&
                            i != currentIndex)
                        ? () => onStepTapped!(i)
                        : null,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// How much of the registration is done, as a ring that sweeps to its new
/// value whenever a step completes.
class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final double target = total == 0 ? 0 : done / total;
    return Semantics(
      label: '$done of $total steps done',
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: target),
        duration: AppMotion.reduced(context)
            ? Duration.zero
            : const Duration(milliseconds: 700),
        curve: AppMotion.emphasized,
        builder: (BuildContext context, double v, Widget? _) => SizedBox(
          width: 54,
          height: 54,
          child: CustomPaint(
            painter: _RingPainter(v),
            child: Center(
              child: Text(
                '${(v * 100).round()}%',
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.value);

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect box = Offset.zero & size;
    final Rect arc = box.deflate(4);
    canvas.drawArc(
      arc,
      0,
      6.2832,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = Colors.white.withValues(alpha: 0.18),
    );
    if (value <= 0) return;
    canvas.drawArc(
      arc,
      -1.5708, // from twelve o'clock
      6.2832 * value.clamp(0, 1),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(
          colors: <Color>[AppColors.cyan, Colors.white],
        ).createShader(box),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value;
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.step,
    required this.isCurrent,
    required this.isComplete,
    this.onTap,
  });

  final OnboardingStepId step;
  final bool isCurrent;
  final bool isComplete;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // On the navy band: finished steps cyan (the covered distance), the
    // current one white, the rest a faint white.
    final Color fill = isComplete
        ? AppColors.cyan
        : isCurrent
        ? Colors.white
        : Colors.white.withValues(alpha: 0.22);

    final bool isLockedGate = step == OnboardingStepId.identity && !isComplete;

    return Semantics(
      label:
          '${step.label}, '
          '${isComplete
              ? 'complete'
              : isCurrent
              ? 'current step'
              : 'not started'}',
      button: onTap != null,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        // The tap area reaches the 48dp floor; the rail and icon above it are
        // what is drawn.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSizes.touchTarget),
          child: Column(
            children: <Widget>[
              // Animated rather than switched. A step filling in on
              // completion is the most satisfying moment in a seven-step
              // registration, and it is worth the 240ms to let it land.
              AnimatedContainer(
                duration: AppMotion.base,
                curve: AppMotion.standard,
                height: AppSizes.stepRailHeight,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                  boxShadow: isCurrent
                      ? <BoxShadow>[
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.45),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(height: 6),
              // Three states, one slot. A finished step shows a tick because
              // that is the only thing worth saying about it; the ID gate
              // shows a lock while outstanding, which reads as "this one
              // blocks the rest"; everything else shows what the step is.
              AnimatedSwitcher(
                duration: AppMotion.reduced(context)
                    ? Duration.zero
                    : AppMotion.base,
                transitionBuilder: (Widget child, Animation<double> a) =>
                    ScaleTransition(scale: a, child: child),
                child: Icon(
                  isComplete
                      ? Icons.check_circle_rounded
                      : isLockedGate
                      ? Icons.lock_outline_rounded
                      : step.icon,
                  key: ValueKey<String>(
                    isComplete ? 'done' : (isLockedGate ? 'lock' : 'step'),
                  ),
                  size: 16,
                  color: isComplete
                      ? AppColors.cyan
                      : isCurrent
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Save and continue later", shown in the app bar on resumable steps.
///
/// Deliberately absent on the account and identity steps. Offering it there
/// would imply the ID check is optional, and there is nothing saved to return
/// to until it is done - see [OnboardingStepId.allowsSaveAndExit].
class SaveAndExitAction extends StatelessWidget {
  const SaveAndExitAction({
    super.key,
    required this.step,
    required this.onSaveAndExit,
    this.isBusy = false,
  });

  final OnboardingStepId step;
  final Future<void> Function() onSaveAndExit;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    if (!step.allowsSaveAndExit) return const SizedBox.shrink();

    return TextButton.icon(
      onPressed: isBusy ? null : () => _confirm(context),
      icon: const Icon(Icons.bookmark_outline_rounded, size: 16),
      label: const Text('Save & exit'),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
      ),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final bool? leave = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Save and continue later?'),
        content: const Text(
          'Your progress is saved. You can pick up from this step next time '
          'you sign in.\n\nYour account stays inactive until registration is '
          'finished and approved.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Save & exit'),
          ),
        ],
      ),
    );

    if (leave ?? false) await onSaveAndExit();
  }
}
