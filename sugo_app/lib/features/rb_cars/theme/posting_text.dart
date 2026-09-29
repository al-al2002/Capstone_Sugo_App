import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Typography for the five posting steps.
///
/// The flow reads as a form rather than as a page, so its headings are the
/// scale's 20 rather than the 28 display size - a larger headline above a
/// three-line question pushed the device grid off the first screen.
///
/// Since the Dispatch redesign these are the app's own scale, named for the
/// flow: they used to be 19, 13.5 and 11.5, three sizes found nowhere else.
class PostingText {
  const PostingText._();

  /// The question at the top of a step - "What needs a fix?".
  static const TextStyle title = AppTextStyles.headline;

  /// The sentence under the question explaining why it is being asked.
  static const TextStyle subtitle = AppTextStyles.caption;

  /// The bold word above a field - "Symptom", "Budget range".
  static const TextStyle label = TextStyle(
    fontFamily: AppTextStyles.fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  /// Small print under a field.
  static const TextStyle caption = AppTextStyles.micro;
}
