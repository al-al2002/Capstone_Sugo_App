import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../models/schedule_preference.dart';
import '../theme/posting_text.dart';
import '../../../core/constants/app_colors.dart';

/// "Flexible / This week / Urgent", the control that replaced the two-option
/// urgency toggle and the separate date picker.
///
/// It writes two columns at once - see [SchedulePreference] for why - so this
/// one row is the whole of "when". The date picker it replaced asked clients to
/// name an hour before they knew who was available, and the overwhelming answer
/// was to skip it.
///
/// Filled in [AppColors.textPrimary] rather than coral when selected. Coral is
/// the flow's "this is chosen" colour everywhere else, but here all three
/// options are always visible and only one is ever on; a coral fill made the
/// row compete with the CTA directly below it.
class ScheduleSelector extends StatelessWidget {
  const ScheduleSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final SchedulePreference value;
  final ValueChanged<SchedulePreference> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: SchedulePreference.values
              .map((SchedulePreference option) {
                final bool selected = option == value;
                final bool isLast = option == SchedulePreference.values.last;

                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: isLast ? 0 : AppSizes.sm),
                    child: Semantics(
                      button: true,
                      selected: selected,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => onChanged(option),
                          borderRadius: BorderRadius.circular(
                            AppSizes.pillRadius,
                          ),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            curve: Curves.easeOut,
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSizes.md,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.textPrimary
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(
                                AppSizes.pillRadius,
                              ),
                              border: Border.all(
                                color: selected
                                    ? AppColors.textPrimary
                                    : AppColors.border,
                              ),
                            ),
                            child: Text(
                              option.label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: selected
                                    ? Colors.white
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              })
              .toList(growable: false),
        ),
        const SizedBox(height: AppSizes.sm),
        // The blurb sits under the row rather than inside each pill: three
        // sentences side by side at this width wrap to four lines each.
        Text(value.blurb, style: PostingText.caption),
      ],
    );
  }
}
