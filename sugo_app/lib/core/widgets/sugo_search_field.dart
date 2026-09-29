import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../theme/app_text_styles.dart';

/// The search bar, in two modes.
///
/// * **Button mode** ([SugoSearchField.button]) - on the home screen. It looks
///   like a field but is a button that opens the search screen. Typing on the
///   dashboard itself would mean results pushing the rest of the dashboard
///   down, keyboard open, on the one screen that should stay calm.
/// * **Live mode** - on the search screen, focused on arrival, with a clear
///   button once there is something to clear.
///
/// The two share their exact geometry, so the transition from one to the
/// other reads as the same bar gaining focus rather than a new screen.
class SugoSearchField extends StatelessWidget {
  const SugoSearchField({
    super.key,
    required TextEditingController this.controller,
    this.hint = 'What service do you need?',
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.focusNode,
  }) : onTap = null;

  const SugoSearchField.button({
    super.key,
    required VoidCallback this.onTap,
    this.hint = 'What service do you need?',
  }) : controller = null,
       onChanged = null,
       onSubmitted = null,
       autofocus = false,
       focusNode = null;

  final TextEditingController? controller;
  final VoidCallback? onTap;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final FocusNode? focusNode;

  /// The touch floor, and no more: the search bar is an entry point, not the
  /// thing the screen is about, so it takes the least height it can.
  static const double _height = AppSizes.touchTarget;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(AppSizes.radius);

    if (onTap != null) {
      return Semantics(
        button: true,
        label: 'Search. $hint',
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Ink(
              height: _height,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: radius,
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: <Widget>[
                  const SizedBox(width: AppSizes.md + 2),
                  const Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: Text(
                      hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.hint.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  // No trailing "filters" tile. It was there for balance, but
                  // a control that opens a search screen rather than a filter
                  // sheet is a promise the app does not keep - and on a 320dp
                  // phone it cost 54px, which truncated the hint itself.
                  const SizedBox(width: AppSizes.md),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: _height,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller!,
        builder: (BuildContext context, TextEditingValue value, Widget? _) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: autofocus,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            textInputAction: TextInputAction.search,
            style: AppTextStyles.field.copyWith(fontSize: 15),
            decoration: InputDecoration(
              hintText: hint,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              prefixIcon: const Padding(
                padding: EdgeInsets.only(
                  left: AppSizes.md + 2,
                  right: AppSizes.md,
                ),
                child: Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 0),
              suffixIcon: value.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        controller!.clear();
                        onChanged?.call('');
                      },
                      icon: const Icon(Icons.cancel_rounded, size: 20),
                      color: AppColors.hint,
                    ),
              border: OutlineInputBorder(
                borderRadius: radius,
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: radius,
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: radius,
                borderSide: const BorderSide(
                  color: AppColors.secondary,
                  width: 1.6,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
