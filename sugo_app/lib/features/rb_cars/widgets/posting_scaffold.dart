import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_elevation.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/widgets/primary_button.dart';
import '../theme/posting_text.dart';

/// The frame every step of the posting flow is drawn in.
///
/// Five screens previously carried their own copy of the progress rail, their
/// own `AppBar`, and their own trailing button inside the scroll view. There
/// is now one, so a change here is a change to all six steps.
///
/// ## The 2026-11-16 renovation
///
/// At the user's request ("renovate the whole posting screen, make it cool,
/// add some animation"), with the motion kept to things that explain the form
/// rather than decorate it:
///
/// * **A navy header**, the same navy-to-blue gradient as the home screen's
///   hero, so posting reads as part of the app that launched it. It carries
///   the step's question, a faint icon for the step, and the progress.
/// * **Progress that moves.** On each step the current segment fills as the
///   screen arrives, so the client sees themselves advance instead of
///   counting segments.
/// * **Content dealt in.** The step's sections rise into place a few frames
///   apart ([AppMotion.staggerStep]), top first - the order they are read in.
/// * **Steps slide.** [PostingRoute] moves forward to the left and back to the
///   right, so the direction of travel matches the direction of the rail.
///
/// All of it collapses to an instant change under the system's reduce-motion
/// setting ([AppMotion.reduced]).
///
/// ## Kept from before
///
/// * **The CTA is pinned, not scrolled**, so "Continue" is reachable without
///   scrolling to the bottom of a long step.
/// * **A disabled CTA says why** ([ctaHint]). A greyed button with no
///   explanation is the most common dead end in a form.
/// * **The footer floats** on [AppElevation.xl]: the content genuinely
///   scrolls beneath it.
class PostingScaffold extends StatefulWidget {
  const PostingScaffold({
    super.key,
    required this.step,
    required this.title,
    required this.children,
    required this.ctaLabel,
    required this.onCta,
    this.subtitle,
    this.stepName,
    this.ctaLoading = false,
    this.ctaHint,
    this.onBack,
  });

  /// 1-based position in the flow, used to fill the rail.
  final int step;

  /// Total steps in the flow. The rail renders one segment each.
  ///
  /// Six since 2026-11-15, when "Your technician" (the client preference
  /// pre-filter) became step 2.
  static const int stepCount = 6;

  final String title;

  /// One line under the title, saying what this step is for.
  final String? subtitle;

  /// Short name for the progress label, e.g. "Where and when". Falls back to
  /// [title], which is usually a question and too long for the pill.
  final String? stepName;

  final List<Widget> children;

  final String ctaLabel;

  /// Null disables the button - the step is not answered yet.
  final VoidCallback? onCta;
  final bool ctaLoading;

  /// Shown under a disabled CTA, saying what is still missing.
  final String? ctaHint;

  final VoidCallback? onBack;

  /// The faint icon in each step's header.
  static IconData iconFor(int step) => switch (step) {
    1 => Icons.devices_other_rounded,
    2 => Icons.tune_rounded,
    3 => Icons.build_circle_outlined,
    4 => Icons.info_outline_rounded,
    5 => Icons.place_outlined,
    _ => Icons.fact_check_outlined,
  };

  @override
  State<PostingScaffold> createState() => _PostingScaffoldState();
}

class _PostingScaffoldState extends State<PostingScaffold>
    with SingleTickerProviderStateMixin {
  /// Items after this many share the last slot, so a long step does not keep
  /// the bottom of the list waiting.
  static const int _maxStaggered = 8;

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: AppMotion.slow + AppMotion.staggerStep * _maxStaggered,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entrance.isDismissed) {
      AppMotion.reduced(context) ? _entrance.value = 1 : _entrance.forward();
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  /// The slice of [_entrance] that item [index] animates over.
  Animation<double> _slot(int index) {
    final double total = _entrance.duration!.inMilliseconds.toDouble();
    final double start =
        AppMotion.staggerStep.inMilliseconds *
        index.clamp(0, _maxStaggered) /
        total;
    final double end = (start + AppMotion.slow.inMilliseconds / total).clamp(
      0,
      1,
    );
    // A CurveTween, not a CurvedAnimation: this runs on every build, and a
    // CurvedAnimation registers a listener on its parent that nothing here
    // would ever remove.
    return CurveTween(
      curve: Interval(start, end, curve: AppMotion.emphasized),
    ).animate(_entrance);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // White status-bar icons over the navy header.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: <Widget>[
            _Header(
              step: widget.step,
              title: widget.title,
              subtitle: widget.subtitle,
              stepName: widget.stepName ?? widget.title,
              onBack: widget.onBack ?? () => Navigator.of(context).maybePop(),
              titleIn: _slot(0),
              subtitleIn: _slot(1),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.screenPadding,
                  AppSizes.xl,
                  AppSizes.screenPadding,
                  AppSizes.xl,
                ),
                children: <Widget>[
                  for (int i = 0; i < widget.children.length; i++)
                    PostingRise(
                      animation: _slot(i + 1),
                      child: widget.children[i],
                    ),
                ],
              ),
            ),
            _CtaBar(
              label: widget.ctaLabel,
              onPressed: widget.onCta,
              isLoading: widget.ctaLoading,
              hint: widget.ctaHint,
            ),
          ],
        ),
      ),
    );
  }
}

/// Fades in while rising a short way - the one entrance used across the
/// posting flow, so every step arrives the same way.
class PostingRise extends StatelessWidget {
  const PostingRise({super.key, required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.12),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.stepName,
    required this.onBack,
    required this.titleIn,
    required this.subtitleIn,
  });

  final int step;
  final String title;
  final String? subtitle;
  final String stepName;
  final VoidCallback onBack;
  final Animation<double> titleIn;
  final Animation<double> subtitleIn;

  static const double _radius = 28;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(_radius),
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[AppColors.navy, AppColors.navyLift],
          ),
        ),
        child: Stack(
          children: <Widget>[
            // The step's icon, large and faint, half off the corner - it
            // names the step at a glance without competing with the title.
            Positioned(
              right: -28,
              top: -10,
              child: ExcludeSemantics(
                child: FadeTransition(
                  opacity: titleIn,
                  child: Transform.rotate(
                    angle: -0.18,
                    child: Icon(
                      PostingScaffold.iconFor(step),
                      size: 150,
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.screenPadding - 4,
                  AppSizes.sm,
                  AppSizes.screenPadding,
                  AppSizes.xl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        _BackButton(onTap: onBack),
                        const Spacer(),
                        _StepPill(step: step, name: stepName),
                      ],
                    ),
                    const SizedBox(height: AppSizes.md),
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          PostingRise(
                            animation: titleIn,
                            child: Semantics(
                              header: true,
                              child: Text(
                                title,
                                style: PostingText.title.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          if (subtitle != null) ...<Widget>[
                            const SizedBox(height: AppSizes.xs),
                            PostingRise(
                              animation: subtitleIn,
                              child: Text(
                                subtitle!,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.4,
                                  color: Colors.white.withValues(alpha: 0.78),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSizes.lg),
                          _ProgressRail(step: step),
                        ],
                      ),
                    ),
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

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // A 40px glass disc inside the 48dp touch target IconButton keeps.
    return IconButton(
      tooltip: 'Back',
      onPressed: onTap,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.14),
        foregroundColor: Colors.white,
        fixedSize: const Size(40, 40),
      ),
      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 17),
    );
  }
}

/// "Step 3 of 6 · Symptom" - the count and the step's own name, because a
/// bar alone says how much is left but not what is being asked.
class _StepPill extends StatelessWidget {
  const _StepPill({required this.step, required this.name});

  final int step;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 210),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: 'Step $step of ${PostingScaffold.stepCount}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            TextSpan(
              text: '  ·  $name',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

/// One segment per step. Finished steps are full; this step's segment fills
/// as the screen arrives.
class _ProgressRail extends StatelessWidget {
  const _ProgressRail({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final bool reduced = AppMotion.reduced(context);

    return Semantics(
      label: 'Step $step of ${PostingScaffold.stepCount}',
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: reduced ? 1 : 0, end: 1),
        duration: reduced ? Duration.zero : AppMotion.page + AppMotion.base,
        curve: AppMotion.emphasized,
        builder: (BuildContext context, double fill, Widget? _) => Row(
          children: <Widget>[
            for (int i = 1; i <= PostingScaffold.stepCount; i++) ...<Widget>[
              if (i > 1) const SizedBox(width: 6),
              Expanded(
                child: _Segment(
                  fill: i < step
                      ? 1
                      : i == step
                      ? fill
                      : 0,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.fill});

  final double fill;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      child: SizedBox(
        height: 5,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ColoredBox(color: Colors.white.withValues(alpha: 0.2)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fill.clamp(0, 1),
              child: const ColoredBox(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _CtaBar extends StatelessWidget {
  const _CtaBar({
    required this.label,
    required this.onPressed,
    required this.isLoading,
    required this.hint,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final bool showHint = hint != null && onPressed == null;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPadding,
        AppSizes.md,
        AppSizes.screenPadding,
        AppSizes.md,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        boxShadow: AppElevation.xl,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // The blocked-progress reason, animated in rather than popping the
            // bar taller. A footer that jumps as you type makes a form feel
            // unstable.
            AnimatedSize(
              duration: AppMotion.base,
              curve: AppMotion.standard,
              child: showHint
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: AppSizes.sm),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              hint!,
                              textAlign: TextAlign.center,
                              style: PostingText.caption,
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            // The brand navy, like every other primary action in the app: one
            // primary colour, used consistently, is worth more than a local
            // contrast trick.
            PrimaryButton(
              label: label,
              isLoading: isLoading,
              onPressed: onPressed,
            ),
          ],
        ),
      ),
    );
  }
}

/// The move between two posting steps: forward slides in from the right and
/// pushes the old step a little to the left, Back does the reverse - the same
/// direction the progress rail fills. A cross-fade covers the seam.
///
/// A [MaterialPageRoute], so it keeps everything that route does (the back
/// gesture where the platform has one, state restoration); only the drawing
/// of the transition changes, and that is skipped under reduce-motion.
class PostingRoute<T> extends MaterialPageRoute<T> {
  PostingRoute({required super.builder, super.settings});

  @override
  Duration get transitionDuration => AppMotion.page;

  @override
  Duration get reverseTransitionDuration => AppMotion.slow;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (AppMotion.reduced(context)) return child;

    final Animation<double> incoming = CurveTween(
      curve: AppMotion.emphasized,
    ).animate(animation);
    final Animation<double> outgoing = CurveTween(
      curve: AppMotion.standard,
    ).animate(secondaryAnimation);

    return SlideTransition(
      position: Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-0.18, 0),
      ).animate(outgoing),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0, end: 1).animate(incoming),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.22, 0),
            end: Offset.zero,
          ).animate(incoming),
          child: child,
        ),
      ),
    );
  }
}
