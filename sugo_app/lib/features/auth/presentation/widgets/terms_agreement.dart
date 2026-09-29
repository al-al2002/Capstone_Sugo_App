import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_text_styles.dart';

/// Checkbox with inline, tappable Terms of Service and Privacy Policy links.
///
/// Stateful only so the tap recognizers can be disposed with the widget.
class TermsAgreement extends StatefulWidget {
  const TermsAgreement({
    super.key,
    required this.value,
    required this.onChanged,
    this.onTapTerms,
    this.onTapPrivacy,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onTapTerms;
  final VoidCallback? onTapPrivacy;

  @override
  State<TermsAgreement> createState() => _TermsAgreementState();
}

class _TermsAgreementState extends State<TermsAgreement> {
  final TapGestureRecognizer _termsRecognizer = TapGestureRecognizer();
  final TapGestureRecognizer _privacyRecognizer = TapGestureRecognizer();

  @override
  void dispose() {
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _termsRecognizer.onTap = widget.onTapTerms;
    _privacyRecognizer.onTap = widget.onTapPrivacy;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: 24,
          width: 24,
          child: Checkbox(
            value: widget.value,
            onChanged: (bool? checked) => widget.onChanged(checked ?? false),
          ),
        ),
        const SizedBox(width: AppSizes.sm),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text.rich(
              TextSpan(
                style: AppTextStyles.caption,
                children: <InlineSpan>[
                  const TextSpan(text: AppStrings.agreePrefix),
                  TextSpan(
                    text: AppStrings.terms,
                    style: AppTextStyles.link,
                    recognizer: _termsRecognizer,
                  ),
                  const TextSpan(text: AppStrings.agreeMiddle),
                  TextSpan(
                    text: AppStrings.privacy,
                    style: AppTextStyles.link,
                    recognizer: _privacyRecognizer,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
