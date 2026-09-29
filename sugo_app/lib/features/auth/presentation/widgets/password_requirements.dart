import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/validators.dart';

/// The password rules, ticked off as they are met.
///
/// ## Why a checklist instead of an error message
///
/// The rules are the same either way - at least eight characters, at least one
/// letter and one digit, which is what [Validators.password] enforces - but an
/// error message only appears *after* somebody has failed. A checklist tells
/// them the rules while they are still typing, so the first attempt is the one
/// that works.
///
/// ## Why it does not score strength
///
/// A coloured "weak / medium / strong" bar implies SUGO will accept a "weak"
/// password, which it will not, and it invites the user to chase a score
/// rather than meet the rule. Each line here is a rule that the server
/// actually applies.
class PasswordRequirements extends StatelessWidget {
  const PasswordRequirements({super.key, required this.password});

  final String password;

  bool get _hasLength => password.length >= Validators.minPasswordLength;
  bool get _hasLetter => password.contains(RegExp(r'[A-Za-z]'));
  bool get _hasDigit => password.contains(RegExp(r'\d'));

  @override
  Widget build(BuildContext context) {
    final bool started = password.isNotEmpty;
    final bool allMet = _hasLength && _hasLetter && _hasDigit;

    return AnimatedSize(
      duration: AppMotion.base,
      curve: AppMotion.standard,
      alignment: Alignment.topCenter,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.md,
          vertical: AppSizes.sm + 2,
        ),
        decoration: BoxDecoration(
          color: allMet ? AppColors.successSoft : AppColors.background,
          borderRadius: BorderRadius.circular(AppSizes.tileRadius),
          border: Border.all(
            color: allMet ? AppColors.successSoft : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              allMet ? 'Password looks good' : 'Your password needs',
              style: AppTextStyles.micro.copyWith(
                fontWeight: FontWeight.w800,
                color: allMet ? AppColors.success : AppColors.textSecondary,
              ),
            ),
            if (!allMet) ...<Widget>[
              const SizedBox(height: AppSizes.sm),
              _Rule(
                label: 'At least ${Validators.minPasswordLength} characters',
                met: _hasLength,
                started: started,
              ),
              _Rule(label: 'A letter', met: _hasLetter, started: started),
              _Rule(label: 'A number', met: _hasDigit, started: started),
            ],
          ],
        ),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({
    required this.label,
    required this.met,
    required this.started,
  });

  final String label;
  final bool met;

  /// Before anything is typed every rule is neutral, not "failed". Marking an
  /// untouched form red is the fastest way to make it feel hostile.
  final bool started;

  @override
  Widget build(BuildContext context) {
    final Color colour = met
        ? AppColors.success
        : started
        ? AppColors.textSecondary
        : AppColors.hint;

    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: <Widget>[
          AnimatedSwitcher(
            duration: AppMotion.fast,
            transitionBuilder: (Widget child, Animation<double> animation) =>
                ScaleTransition(scale: animation, child: child),
            child: Icon(
              met
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              key: ValueKey<bool>(met),
              size: 14,
              color: colour,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.micro.copyWith(
              color: colour,
              fontWeight: met ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
