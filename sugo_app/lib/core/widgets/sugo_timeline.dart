import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../theme/app_motion.dart';
import '../theme/app_text_styles.dart';

/// Where a step stands relative to "now".
enum SugoStepState { done, current, upcoming }

/// One row of a [SugoTimeline].
class SugoTimelineStep {
  const SugoTimelineStep({
    required this.title,
    required this.state,
    this.subtitle,
    this.icon,
    this.trailing,
  });

  final String title;
  final SugoStepState state;

  /// Shown under the title. For a done step this is typically a time; for the
  /// current step, what it means for the reader.
  final String? subtitle;

  /// Glyph for the current and upcoming nodes. Done nodes always show a tick.
  final IconData? icon;

  /// A time or small label at the right edge.
  final String? trailing;
}

/// A vertical progress timeline: done, current, upcoming.
///
/// ## Three states, three shapes
///
/// The brief asked that completed, current and upcoming be clearly
/// differentiated, and colour alone does not do that (see
/// [SugoStatusBadge]). Each state therefore has its own *shape*:
///
/// * **Done** - a filled SUGO-blue disc with a tick, and a solid connector
///   below.
/// * **Current** - a navy disc with the step's own icon inside a soft halo,
///   the title in bold, and a "Now" label spoken to screen readers.
/// * **Upcoming** - a hollow ring and a dashed connector, the title in the
///   hint tone.
///
/// Anyone can tell the three apart in greyscale, which is the test.
///
/// This is the vertical form of `SugoRouteLine`, and since the Dispatch
/// redesign the two share their colours: the distance already travelled is
/// SUGO blue in both (it used to be green here), the current stop is navy,
/// and what is still ahead is a dashed hairline.
class SugoTimeline extends StatelessWidget {
  const SugoTimeline({super.key, required this.steps, this.compact = false});

  final List<SugoTimelineStep> steps;

  /// Tighter rows, and subtitles only on the current step.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (int i = 0; i < steps.length; i++)
          _Row(
            step: steps[i],
            isLast: i == steps.length - 1,
            nextState: i + 1 < steps.length ? steps[i + 1].state : null,
            compact: compact,
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.step,
    required this.isLast,
    required this.nextState,
    required this.compact,
  });

  final SugoTimelineStep step;
  final bool isLast;
  final SugoStepState? nextState;
  final bool compact;

  static const double _node = 28;

  @override
  Widget build(BuildContext context) {
    final bool done = step.state == SugoStepState.done;
    final bool current = step.state == SugoStepState.current;

    final bool showSubtitle =
        step.subtitle != null && (!compact || current);

    final String spoken = switch (step.state) {
      SugoStepState.done => 'Done',
      SugoStepState.current => 'Now',
      SugoStepState.upcoming => 'Upcoming',
    };

    return Semantics(
      label: '$spoken: ${step.title}${step.subtitle == null ? '' : '. ${step.subtitle}'}',
      excludeSemantics: true,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: _node + 8,
              child: Column(
                children: <Widget>[
                  _Node(step: step, size: _node),
                  if (!isLast)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: _Connector(
                          // Solid once the step below it has been reached.
                          solid: done && nextState != SugoStepState.upcoming,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  top: 3,
                  bottom: isLast ? 0 : (compact ? AppSizes.md : AppSizes.lg + 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            step.title,
                            style: AppTextStyles.titleSmall.copyWith(
                              fontWeight: current
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: step.state == SugoStepState.upcoming
                                  ? AppColors.hint
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (current && step.trailing == null)
                          const _NowTag()
                        else if (step.trailing != null)
                          Text(
                            step.trailing!,
                            style: AppTextStyles.micro.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    if (showSubtitle) ...<Widget>[
                      const SizedBox(height: 3),
                      Text(
                        step.subtitle!,
                        style: AppTextStyles.caption.copyWith(
                          color: step.state == SugoStepState.upcoming
                              ? AppColors.hint
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Node extends StatelessWidget {
  const _Node({required this.step, required this.size});

  final SugoTimelineStep step;
  final double size;

  @override
  Widget build(BuildContext context) {
    switch (step.state) {
      case SugoStepState.done:
        return Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: AppColors.secondary,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
        );
      case SugoStepState.current:
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.7, end: 1),
          duration: AppMotion.reduced(context) ? Duration.zero : AppMotion.slow,
          curve: AppMotion.playful,
          builder: (BuildContext context, double scale, Widget? child) =>
              Transform.scale(scale: scale, child: child),
          child: Container(
            width: size + 8,
            height: size + 8,
            decoration: const BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Container(
              width: size,
              height: size,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                step.icon ?? Icons.more_horiz_rounded,
                size: 15,
                color: Colors.white,
              ),
            ),
          ),
        );
      case SugoStepState.upcoming:
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border, width: 2),
          ),
          child: Icon(
            step.icon ?? Icons.circle_outlined,
            size: 13,
            color: AppColors.hint,
          ),
        );
    }
  }
}

class _Connector extends StatelessWidget {
  const _Connector({required this.solid});

  final bool solid;

  @override
  Widget build(BuildContext context) {
    if (solid) {
      return Container(
        width: 2.5,
        decoration: BoxDecoration(
          color: AppColors.secondary,
          borderRadius: BorderRadius.circular(2),
        ),
      );
    }
    // Painted rather than built from a LayoutBuilder of dash widgets: each row
    // sits inside an IntrinsicHeight, and LayoutBuilder cannot report an
    // intrinsic size - Flutter asserts and the whole timeline fails to lay out.
    return const CustomPaint(
      size: Size(2, double.infinity),
      painter: _DashPainter(),
    );
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter();

  static const double _dash = 4;
  static const double _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final double x = size.width / 2;
    for (double y = 0; y < size.height; y += _dash + _gap) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, (y + _dash).clamp(0, size.height)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter oldDelegate) => false;
}

class _NowTag extends StatelessWidget {
  const _NowTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      ),
      child: const Text(
        'Now',
        style: TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          height: 1.2,
        ),
      ),
    );
  }
}
