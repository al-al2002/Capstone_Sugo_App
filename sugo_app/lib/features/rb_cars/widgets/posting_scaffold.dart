import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_elevation.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/sugo_icon_button.dart';
import '../../../core/widgets/sugo_step_rail.dart';
import '../theme/posting_text.dart';

/// The frame every step of the posting flow is drawn in.
///
/// Five screens previously carried their own copy of the progress rail, their
/// own `AppBar`, and their own trailing button inside the scroll view. That is
/// why the rail said "3" on one screen after the flow grew - it was three
/// separate `List.generate(3, ...)` calls. There is now one.
///
/// Two structural choices, both taken from the mockup:
///
/// * **The CTA is pinned, not scrolled.** It sits in a bar below the content
///   rather than as the last child of the list, so "Continue" is reachable
///   without scrolling to the bottom of a long step.
/// * **Back is a round button, not an AppBar leading.** The title then sits on
///   the same line at the left margin. Since the Dispatch redesign it is the
///   shared hairline [SugoIconButton] - it was a 36px chip on a shadow, under
///   the 48dp touch floor.
///
/// ## What the renovation changed
///
/// **The step is named, not just counted.** The header now carries a
/// [SugoStepLabel] - "Step 3 of 5" beside the step's own name - above the
/// shared [SugoStepRail]. A bar alone says how much is left; it does not say
/// what is being asked, and on a five-step form both questions are live.
///
/// **A subtitle slot.** Each step can now explain itself in one line under the
/// title, which is what let the step bodies drop their leading paragraph of
/// instructions and start with the actual control.
///
/// **The footer floats.** It carries [AppElevation.xl] and sits on the surface
/// colour, so the content underneath visibly scrolls *beneath* it rather than
/// ending at a seam - one of the few shadows the Dispatch design keeps,
/// because the bar genuinely sits over the list.
class PostingScaffold extends StatelessWidget {
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
  static const int stepCount = 5;

  final String title;

  /// One line under the title, saying what this step is for.
  final String? subtitle;

  /// Short name for the progress label, e.g. "Where and when". Falls back to
  /// [title], which is usually a question and too long for the rail.
  final String? stepName;

  final List<Widget> children;

  final String ctaLabel;

  /// Null disables the button - the step is not answered yet.
  final VoidCallback? onCta;
  final bool ctaLoading;

  /// Shown under a disabled CTA, saying what is still missing. A greyed button
  /// with no explanation is the most common dead end in a form.
  final String? ctaHint;

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _Header(
              step: step,
              title: title,
              subtitle: subtitle,
              stepName: stepName ?? title,
              onBack: onBack ?? () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.screenPadding,
                  AppSizes.lg,
                  AppSizes.screenPadding,
                  AppSizes.xl,
                ),
                children: children,
              ),
            ),
            _CtaBar(
              label: ctaLabel,
              onPressed: onCta,
              isLoading: ctaLoading,
              hint: ctaHint,
            ),
          ],
        ),
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
  });

  final int step;
  final String title;
  final String? subtitle;
  final String stepName;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPadding,
        AppSizes.md,
        AppSizes.screenPadding,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _BackChip(onTap: onBack),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: PostingText.title),
                    if (subtitle != null) ...<Widget>[
                      const SizedBox(height: 3),
                      Text(subtitle!, style: AppTextStyles.subtitle),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          SugoStepLabel(
            currentIndex: step - 1,
            stepCount: PostingScaffold.stepCount,
            label: stepName,
          ),
          const SizedBox(height: AppSizes.sm),
          SugoStepRail(
            currentIndex: step - 1,
            stepCount: PostingScaffold.stepCount,
            // Both the filled and the current segment are the brand blue.
            //
            // The shared rail defaults `completeColor` to green, which is
            // right for registration - there, a finished step is a
            // requirement satisfied. Here the steps are just places in a form,
            // so a colour change partway along the rail would imply a
            // distinction that does not exist.
            activeColor: AppColors.primary,
            completeColor: AppColors.primary,
          ),
          const SizedBox(height: AppSizes.md),
        ],
      ),
    );
  }
}

class _BackChip extends StatelessWidget {
  const _BackChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The same chevron as every app bar's back, on the shared hairline disc
    // with a 48dp touch area.
    return SugoIconButton(
      icon: Icons.arrow_back_ios_new_rounded,
      tooltip: 'Back',
      size: 40,
      onPressed: onTap,
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
            // bar taller. A footer that changes height as you type is the kind
            // of movement that makes a form feel unstable.
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
            // The brand blue, like every other primary action in the app.
            //
            // This button used to be orange. The argument for it was that the
            // flow is the one place where the next action *is* the screen, so
            // the accent separated it from the blue everything else wears -
            // but that reasoning only holds if the rest of the flow is blue,
            // and the renovation had since painted the step rail and the step
            // label orange to match it. At that point the accent was no longer
            // marking the action; it was just the colour of this flow, which
            // made the posting screens look like a different product from the
            // dashboard that launches them.
            //
            // One primary colour, used consistently, is worth more than a
            // local contrast trick. The accent is still doing real work
            // elsewhere - unanswered questions, the Elite tier, unread badges -
            // where it marks a genuine exception rather than a whole flow.
            //
            // Flat since the Dispatch redesign: it used to glow in its own
            // colour, and the navy fill alone already marks the one action.
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
