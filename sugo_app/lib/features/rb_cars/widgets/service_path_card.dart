import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../models/job_enums.dart';
import '../models/problem_catalog.dart';
import '../theme/posting_text.dart';
import '../../../core/constants/app_colors.dart';

/// The suggestion the classification rules produced, with its reasoning.
///
/// The client is never forced into it. Showing why we suggested a path, and
/// letting them override it, is what keeps the guided flow from feeling like a
/// black box - and an override is recorded, so a path the rules keep getting
/// wrong is visible in the data.
///
/// ## Where the reason went
///
/// It used to sit in a banner above the three cards. It now sits *inside* the
/// suggested card, under its blurb. The banner said "we suggest shop pickup"
/// directly above a card that also said "Shop pickup" and carried a Suggested
/// pill - three statements of one fact, and the only new information in the
/// group was the sentence explaining why. Moving that sentence into the card
/// attaches the reason to the thing it is a reason for.
class ServicePathSuggestion extends StatelessWidget {
  const ServicePathSuggestion({
    super.key,
    required this.result,
    required this.selected,
    required this.onChanged,
  });

  final ClassificationResult result;
  final ServicePath selected;
  final ValueChanged<ServicePath> onChanged;

  bool get _isOverridden => selected != result.servicePath;

  @override
  Widget build(BuildContext context) {
    final bool lowConfidence =
        result.confidence == ClassificationConfidence.low;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ...ServicePath.values.map(
          (ServicePath path) => _PathOption(
            path: path,
            selected: path == selected,
            isSuggestion: path == result.servicePath,
            lowConfidence: lowConfidence,
            reason: path == result.servicePath ? result.reason : null,
            onTap: () => onChanged(path),
          ),
        ),

        if (_isOverridden) ...<Widget>[
          const SizedBox(height: AppSizes.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(
                Icons.info_outline_rounded,
                size: 14,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'You changed this from our suggestion. That is fine - we '
                  'will match against ${selected.label.toLowerCase()} instead.',
                  style: PostingText.caption,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PathOption extends StatelessWidget {
  const _PathOption({
    required this.path,
    required this.selected,
    required this.isSuggestion,
    required this.lowConfidence,
    required this.reason,
    required this.onTap,
  });

  final ServicePath path;
  final bool selected;
  final bool isSuggestion;

  /// True when the rules could not tell what is wrong. Only changes the pill's
  /// wording - a guess presented as a recommendation is the thing to avoid.
  final bool lowConfidence;

  /// The rule base's explanation, present only on the suggested card.
  final String? reason;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.md),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppSizes.tileRadius),
            child: AnimatedContainer(
              duration: AppMotion.base,
              curve: AppMotion.standard,
              padding: const EdgeInsets.all(AppSizes.lg),
              decoration: BoxDecoration(
                color: selected ? AppColors.primarySofter : AppColors.surface,
                borderRadius: BorderRadius.circular(AppSizes.tileRadius),
                // Selection is SUGO blue at 2px on a tint, with the radio dot
                // below; no lifted shadow since the Dispatch redesign.
                border: Border.all(
                  color: selected ? AppColors.secondary : AppColors.border,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      // The radio dot. A card that is merely tinted leaves the
                      // reader checking border widths to see what is selected;
                      // an explicit control answers it outright.
                      _SelectionDot(selected: selected),
                      const SizedBox(width: AppSizes.md),
                      Expanded(
                        child: Text(
                          path.label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: selected
                                ? AppColors.primaryDark
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (isSuggestion) ...<Widget>[
                        const SizedBox(width: AppSizes.sm),
                        _Pill(
                          label: lowConfidence ? 'Needs a look' : 'Suggested',
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Indented past the dot, so the text block aligns with the
                  // label rather than with the control.
                  Padding(
                    padding: const EdgeInsets.only(left: 32),
                    child: Text(
                      path.blurb,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  if (reason != null) ...<Widget>[
                    const SizedBox(height: AppSizes.md),
                    // The rule base's reasoning, on its own tinted panel.
                    // Boxing it marks it as a different kind of statement from
                    // the blurb above: that says what the option *is*, this
                    // says why we picked it.
                    Container(
                      margin: const EdgeInsets.only(left: 32),
                      padding: const EdgeInsets.all(AppSizes.sm + 2),
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(AppSizes.sm + 2),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Icon(
                            Icons.alt_route_rounded,
                            size: 13,
                            color: AppColors.primaryDark,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              reason!,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primaryDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// The radio dot on a service-path option.
class _SelectionDot extends StatelessWidget {
  const _SelectionDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.base,
      curve: AppMotion.standard,
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppColors.primary : Colors.transparent,
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.hint,
          width: 1.8,
        ),
      ),
      child: AnimatedScale(
        scale: selected ? 1 : 0,
        duration: AppMotion.base,
        curve: AppMotion.playful,
        child: const Icon(Icons.check_rounded, size: 13, color: Colors.white),
      ),
    );
  }
}
