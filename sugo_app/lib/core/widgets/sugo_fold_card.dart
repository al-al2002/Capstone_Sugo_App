import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../theme/app_motion.dart';
import '../theme/app_text_styles.dart';
import 'sugo_card.dart';

/// A card that folds down to one line - its title and a summary - and opens
/// to its full content on a tap (2026-11-17).
///
/// ## Why
///
/// A booking's page stacked every section open: progress, price, details,
/// photos. On a pickup or drop-off job that is a long scroll before the one
/// thing that matters today. The user asked for it "minimal, but don't remove
/// the widgets": so nothing is removed - each secondary section says the one
/// line worth knowing while folded ("Estimated total ₱1,020"), and the whole
/// section is one tap away.
///
/// The content is not built while folded, so a folded card costs a row.
/// Opening plays once (no loop); reduced motion opens it at once.
class SugoFoldCard extends StatefulWidget {
  const SugoFoldCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.summary,
    this.initiallyOpen = false,
  });

  final IconData icon;
  final String title;

  /// The one line shown while folded, and kept under the title when open.
  final String? summary;

  final Widget child;
  final bool initiallyOpen;

  @override
  State<SugoFoldCard> createState() => _SugoFoldCardState();
}

class _SugoFoldCardState extends State<SugoFoldCard> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final bool reduced = AppMotion.reduced(context);
    final Widget body = _open
        ? Padding(
            padding: const EdgeInsets.only(top: AppSizes.md),
            child: widget.child,
          )
        : const SizedBox(width: double.infinity);

    return SugoCard(
      pressable: false,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            button: true,
            expanded: _open,
            label:
                '${widget.title}${widget.summary == null ? '' : ', ${widget.summary}'}',
            excludeSemantics: true,
            child: InkWell(
              onTap: () => setState(() => _open = !_open),
              borderRadius: BorderRadius.circular(AppSizes.radius),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppSizes.touchTarget,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.lg,
                    vertical: AppSizes.md,
                  ),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.primarySofter,
                          borderRadius: BorderRadius.circular(AppSizes.sm + 2),
                        ),
                        child: Icon(
                          widget.icon,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: AppSizes.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(widget.title, style: AppTextStyles.titleSmall),
                            if (widget.summary != null)
                              Text(
                                widget.summary!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.caption,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSizes.sm),
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: reduced ? Duration.zero : AppMotion.base,
                        curve: AppMotion.standard,
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSizes.lg,
              0,
              AppSizes.lg,
              _open ? AppSizes.lg : 0,
            ),
            // No AnimatedSize at zero duration: it trips a layout assertion,
            // and reduced motion has nothing to animate.
            child: reduced
                ? body
                : AnimatedSize(
                    duration: AppMotion.base,
                    curve: AppMotion.standard,
                    alignment: Alignment.topCenter,
                    child: body,
                  ),
          ),
        ],
      ),
    );
  }
}
