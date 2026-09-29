import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../theme/app_motion.dart';
import '../theme/app_text_styles.dart';

/// Labelled text field used by every auth form: a bold label above a filled,
/// rounded input with a leading icon and an optional visibility toggle.
///
/// ## What the renovation added: three states the field can be in
///
/// The field used to have one appearance plus whatever `TextFormField` does on
/// error, which meant the only feedback a user ever got was a red line *after*
/// submitting. Now it says something at each stage:
///
/// * **Focused** - the label and the leading icon take the brand colour, and
///   the border thickens. This is the cheapest possible "you are here" on a
///   form of five fields, and it matters most on a phone where the keyboard
///   covers half the screen and the focused field may be the only one visible.
///
/// * **Valid** - a green tick appears once the field has been edited and its
///   validator passes. Confirming correctness as it happens is what stops the
///   Submit button being the first moment anyone learns whether their email
///   parses.
///
/// * **Invalid** - the message renders with an icon in the error tone, and the
///   border follows. Validation runs on interaction rather than on submit, so
///   an error appears while the field is still in front of the user.
///
/// The tick is suppressed while the field has focus. A checkmark appearing
/// mid-word, as soon as the input happens to parse, reads as the form
/// hurrying the user along - it belongs at the moment they move on.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    this.icon,
    this.validator,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.obscure = false,
    this.enabled = true,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.inputFormatters,
    this.onSubmitted,
    this.helper,
    this.showValidTick = true,
    this.maxLines = 1,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final IconData? icon;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;

  /// When true the field starts obscured and shows an eye toggle.
  final bool obscure;
  final bool enabled;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;

  /// A hint under the field explaining the rule *before* it is broken, e.g.
  /// "At least 8 characters". Hidden while an error is showing, because two
  /// lines of guidance under one input is one too many.
  final String? helper;

  /// Set false where a tick would be meaningless - an optional field, or one
  /// whose validator only checks that something was typed.
  final bool showValidTick;

  final int maxLines;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _obscured = widget.obscure;
  final FocusNode _focus = FocusNode();

  bool _focused = false;

  /// True once the user has typed in this field. Until then the field stays
  /// neutral - marking an untouched field invalid the moment the screen opens
  /// is the most common way a form feels hostile.
  bool _touched = false;

  String? _error;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    widget.controller.removeListener(_onTextChanged);
    _focus.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!mounted) return;
    setState(() {
      _focused = _focus.hasFocus;
      // Re-checked on blur as well as on keystroke, so a field left empty is
      // flagged when the user moves on rather than only at submit.
      if (!_focus.hasFocus && widget.controller.text.isNotEmpty) {
        _touched = true;
      }
    });
    _revalidate();
  }

  void _onTextChanged() {
    if (!mounted) return;
    if (!_touched) setState(() => _touched = true);
    _revalidate();
  }

  void _revalidate() {
    final String? next = widget.validator?.call(widget.controller.text);
    if (next != _error && mounted) setState(() => _error = next);
  }

  bool get _isValid =>
      _touched &&
      _error == null &&
      widget.controller.text.trim().isNotEmpty &&
      widget.validator != null;

  bool get _showError => _touched && _error != null;

  /// Green only once the field is both valid and no longer focused.
  bool get _showTick => widget.showValidTick && _isValid && !_focused;

  Color get _accent {
    if (_showError) return AppColors.error;
    if (_showTick) return AppColors.success;
    if (_focused) return AppColors.secondary;
    return AppColors.hint;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AnimatedDefaultTextStyle(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          style: AppTextStyles.label.copyWith(
            color: _showError
                ? AppColors.error
                : _focused
                ? AppColors.secondary
                : AppColors.textPrimary,
          ),
          child: Text(widget.label),
        ),
        const SizedBox(height: AppSizes.sm),
        TextFormField(
          controller: widget.controller,
          focusNode: _focus,
          // The real validator, so `FormField` owns error rendering.
          //
          // An earlier version of this widget drew its own error row and fed
          // the validator a blank sentinel to avoid a duplicate. That broke
          // the case that matters most: a field the user has never touched has
          // nothing to report on its own, so pressing Submit on an empty form
          // produced no messages anywhere - the form simply refused to go,
          // silently, which is the worst outcome a form can have.
          //
          // `Form.validate()` sets `errorText` on every field regardless of
          // whether it has been interacted with, so letting Flutter render the
          // message is what makes submit-time errors work. The states this
          // widget adds - focus, success - sit on top of that rather than
          // replacing it.
          validator: widget.validator,
          // Live as well as on submit, so a mistake surfaces while the field
          // is still in front of the user rather than at the end.
          autovalidateMode: AutovalidateMode.onUserInteraction,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          obscureText: _obscured,
          enabled: widget.enabled,
          maxLines: widget.obscure ? 1 : widget.maxLines,
          textCapitalization: widget.textCapitalization,
          autofillHints: widget.autofillHints,
          inputFormatters: widget.inputFormatters,
          onFieldSubmitted: widget.onSubmitted,
          style: AppTextStyles.field,
          cursorColor: AppColors.secondary,
          decoration: InputDecoration(
            hintText: widget.hint,
            // Styled rather than suppressed. The default is a thin 12px line
            // in the error colour; this matches the weight of the helper text
            // it replaces, so the space under a field does not change
            // character when it goes from advice to correction.
            errorStyle: const TextStyle(
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: AppColors.error,
            ),
            // A focused field lifts off the page tint onto white, which is
            // what makes the active row obvious at a glance on a long form.
            fillColor: _focused ? AppColors.surface : AppColors.fieldFill,
            prefixIcon: widget.icon == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(
                      left: AppSizes.lg,
                      right: AppSizes.md,
                    ),
                    child: AnimatedContainer(
                      duration: AppMotion.fast,
                      curve: AppMotion.standard,
                      child: Icon(widget.icon, size: 20, color: _accent),
                    ),
                  ),
            prefixIconConstraints: const BoxConstraints(minWidth: 0),
            suffixIcon: _suffix(),
            enabledBorder: _border(
              _showError
                  ? AppColors.error
                  : _showTick
                  ? AppColors.success
                  : AppColors.border,
            ),
            focusedBorder: _border(
              // Blue, not navy: the redesign gives "you are here" to the
              // secondary colour so focus never looks like a primary button.
              _showError ? AppColors.error : AppColors.secondary,
              width: 1.6,
            ),
          ),
        ),

        // The helper line, shown only while there is no error to show -
        // Flutter renders the error itself, in the same slot, and two lines of
        // guidance under one input is one too many.
        AnimatedSize(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          alignment: Alignment.topLeft,
          child: (widget.helper != null && !_showError)
              ? Padding(
                  padding: const EdgeInsets.only(top: 6, left: 2),
                  child: Text(
                    widget.helper!,
                    style: AppTextStyles.micro.copyWith(color: AppColors.hint),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget? _suffix() {
    if (widget.obscure) {
      return IconButton(
        onPressed: () => setState(() => _obscured = !_obscured),
        icon: Icon(
          _obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          size: 20,
        ),
        tooltip: _obscured ? 'Show password' : 'Hide password',
      );
    }

    if (_showTick) {
      return const Padding(
        padding: EdgeInsets.only(right: AppSizes.md),
        child: Icon(
          Icons.check_circle_rounded,
          size: 19,
          color: AppColors.success,
        ),
      );
    }

    if (_showError) {
      return const Padding(
        padding: EdgeInsets.only(right: AppSizes.md),
        child: Icon(Icons.error_rounded, size: 19, color: AppColors.error),
      );
    }

    return null;
  }

  OutlineInputBorder _border(Color color, {double width = 1.2}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.fieldRadius),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}
