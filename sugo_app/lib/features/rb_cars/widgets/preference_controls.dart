import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../theme/posting_text.dart';
import 'posting_field.dart';

/// The words every preference control uses for "not set".
const String kNoPreference = 'No preference';

/// One "pick a threshold or leave it" field on the preferences step.
///
/// A dropdown whose first item is always [kNoPreference] (null). The brief
/// asks for fixed options rather than free values, and a dropdown says that
/// at a glance: there is no box to type a 4.2 into.
///
/// Options may carry a [blurb] - the trust ladder needs one, because "Skill
/// verified" means nothing until it says *verified on what*. The menu shows
/// it under the label; the closed field shows the label alone, so it stays
/// one line.
class PreferenceDropdown<T extends Object> extends StatelessWidget {
  const PreferenceDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.optionLabel,
    required this.onChanged,
    required this.icon,
    this.optionBlurb,
    this.optionLeading,
    this.caption,
  });

  final String label;
  final T? value;
  final List<T> options;
  final String Function(T option) optionLabel;
  final String Function(T option)? optionBlurb;

  /// A small glyph before an option, e.g. a star before "4.5+".
  final Widget Function(T option)? optionLeading;

  final ValueChanged<T?> onChanged;
  final IconData icon;

  /// Small print under the field. Shown whether or not a value is set, so the
  /// consequence is read before choosing rather than discovered after.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final bool isSet = value != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        PostingLabel(label),
        const SizedBox(height: AppSizes.sm),
        DropdownButtonFormField<T?>(
          // Keyed on the value so "Reset all" - which changes the value from
          // outside - redraws the field. `initialValue` alone is read once.
          key: ValueKey<Object?>(value),
          initialValue: value,
          isExpanded: true,
          // Two-line options (label + blurb) need their natural height; the
          // 48dp default would clip the blurb.
          itemHeight: null,
          menuMaxHeight: 420,
          borderRadius: BorderRadius.circular(AppSizes.fieldRadius),
          decoration: InputDecoration(
            prefixIcon: Icon(
              icon,
              size: 20,
              color: isSet ? AppColors.primary : AppColors.hint,
            ),
          ),
          hint: const _NoPreferenceText(),
          selectedItemBuilder: (BuildContext context) => <Widget>[
            const _NoPreferenceText(),
            ...options.map(
              (T option) => Row(
                children: <Widget>[
                  if (optionLeading != null) ...<Widget>[
                    optionLeading!(option),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      optionLabel(option),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          items: <DropdownMenuItem<T?>>[
            DropdownMenuItem<T?>(value: null, child: const _NoPreferenceText()),
            ...options.map(
              (T option) => DropdownMenuItem<T?>(
                value: option,
                child: _OptionRow(
                  label: optionLabel(option),
                  blurb: optionBlurb?.call(option),
                  leading: optionLeading?.call(option),
                ),
              ),
            ),
          ],
          onChanged: onChanged,
        ),
        if (caption != null) ...<Widget>[
          const SizedBox(height: AppSizes.xs),
          Text(caption!, style: PostingText.caption),
        ],
      ],
    );
  }
}

class _NoPreferenceText extends StatelessWidget {
  const _NoPreferenceText();

  @override
  Widget build(BuildContext context) {
    return const Text(
      kNoPreference,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.label, this.blurb, this.leading});

  final String label;
  final String? blurb;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: blurb == null ? 0 : AppSizes.sm),
      child: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[leading!, const SizedBox(width: 6)],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (blurb != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(blurb!, style: PostingText.caption),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The one idea the client has to understand before setting anything.
///
/// A soft navy wash like the "SUGO will match you" promise on the review
/// step: an explanation, not something to press.
class PreferencesExplainer extends StatelessWidget {
  const PreferencesExplainer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.primarySofter,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(color: AppColors.primarySoft),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.tune_rounded, size: 18, color: AppColors.primaryDark),
          SizedBox(width: AppSizes.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Hard limits, not rankings',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDark,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'A technician who misses one of these is left out. Who '
                  'ranks first among the rest is still decided by SUGO.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
