import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../theme/posting_text.dart';
import '../../../core/constants/app_colors.dart';

/// What a [PostingLabel]'s badge is saying about the field under it.
enum FieldState {
  /// Carried forward from an earlier step - the client does not have to
  /// re-answer it, and the badge says so rather than leaving them wondering
  /// why a field is already filled.
  saved('saved'),

  /// Asked here for the first time.
  isNew('new');

  const FieldState(this.label);

  final String label;
}

/// The bold word above a field, with the optional sage badge from the mockup.
///
/// Extracted because the badge is load-bearing on the device step: three of
/// its four fields are pre-filled from earlier answers, and without a marker
/// the screen looks like a form someone else already filled in.
class PostingLabel extends StatelessWidget {
  const PostingLabel(this.text, {super.key, this.state});

  final String text;
  final FieldState? state;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        // Flexible, not bare: "Is there visible physical damage?" is wider than
        // the column, and a Row would overflow rather than wrap it.
        Flexible(child: Text(text, style: PostingText.label)),
        if (state != null) ...<Widget>[
          const SizedBox(width: AppSizes.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(AppSizes.pillRadius),
            ),
            child: Text(
              state!.label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.primaryDark,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A field-shaped box showing an answer the client cannot change here.
///
/// Used for the device category on step 3: it was chosen on step 1, changing
/// it would invalidate the symptom and the whole classification, so it is
/// shown as a filled field rather than as an editable one.
class PostingReadOnlyField extends StatelessWidget {
  const PostingReadOnlyField({super.key, required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.lg,
        vertical: AppSizes.lg,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.fieldRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        value,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}
