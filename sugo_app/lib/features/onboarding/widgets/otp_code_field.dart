import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';

/// What the field is currently saying about the code in it.
enum _OtpPhase { idle, checking, correct, wrong }

/// Six boxes, one digit each, that verify themselves.
///
/// ## Why it verifies rather than reporting
///
/// The obvious split is "this widget collects, the caller submits". It reads
/// well and it is wrong here: the boxes have to *show* the answer - green with
/// a tick, or red with a shake - so they need the result anyway. Handing the
/// caller a string and waiting to be told would mean the caller driving an
/// animation it cannot see.
///
/// So [onCompleted] is a question, not a notification. It is asked the moment
/// the sixth digit lands, and the boolean it returns is what the boxes animate.
///
/// ## What the two animations are for
///
/// They are not decoration. A six-digit code is typed by someone who cannot
/// see the answer, so the field is the only thing that can tell them whether
/// to wait or to retype - and it has to say so faster than they can read. A
/// colour change plus motion registers before any sentence does; the sentence
/// underneath is the confirmation, not the signal.
///
/// The shake is a damped sine rather than `elasticIn`, which overshoots on the
/// way *in* and reads as the field arriving rather than objecting. Four
/// oscillations decaying to nothing over 400ms is the gesture people already
/// know from a refused password.
class OtpCodeField extends StatefulWidget {
  const OtpCodeField({
    super.key,
    required this.onCompleted,
    this.length = 6,
    this.enabled = true,
  });

  /// Asked once all [length] digits are present. True means the code was
  /// accepted, and the caller is responsible for moving on; false leaves the
  /// boxes to clear themselves and hand focus back.
  final Future<bool> Function(String code) onCompleted;

  final int length;
  final bool enabled;

  @override
  State<OtpCodeField> createState() => _OtpCodeFieldState();
}

class _OtpCodeFieldState extends State<OtpCodeField>
    with TickerProviderStateMixin {
  late final List<TextEditingController> _boxes =
      List<TextEditingController>.generate(
        widget.length,
        (_) => TextEditingController(),
      );
  late final List<FocusNode> _focus = List<FocusNode>.generate(
    widget.length,
    (_) => FocusNode(),
  );

  // Both controllers are assigned in [initState], never lazily.
  //
  // `_pop` used to be `late final ... = AnimationController(...)`, and the
  // only things that touched it were the success path: `_pop.forward()` after
  // a correct code, and `_popScale` in the `correct` branch of `_message()`.
  //
  // So anybody who left this step without ever entering a correct code - a
  // wrong code, a back press, a "save and exit" - never created it, which made
  // [dispose] the first access. Constructing a controller there calls
  // `createTicker`, which looks up `TickerMode` on an already-deactivated
  // element and throws "Looking up a deactivated widget's ancestor is unsafe"
  // mid-unmount, leaving the tree half torn down.
  //
  // `_shake` was safe - `build` reaches it on every path - but it is written
  // the same way here so the pattern is not half-applied.

  /// Drives the refusal shake. Runs forward once per wrong code.
  late final AnimationController _shake;

  /// Drives the tick's pop. `easeOutBack` overshoots slightly and settles,
  /// which is what makes it read as landing rather than fading in.
  late final AnimationController _pop;

  late final Animation<double> _popScale;

  _OtpPhase _phase = _OtpPhase.idle;

  String get _code => _boxes.map((TextEditingController c) => c.text).join();

  @override
  void initState() {
    super.initState();

    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _pop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _popScale = CurvedAnimation(parent: _pop, curve: Curves.easeOutBack);

    // The step has just arrived; the caret belongs in the first box without
    // the user hunting for it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.first.requestFocus();
    });
  }

  @override
  void dispose() {
    for (final TextEditingController c in _boxes) {
      c.dispose();
    }
    for (final FocusNode f in _focus) {
      f.dispose();
    }
    _shake.dispose();
    _pop.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------------- typing

  void _onChanged(int index, String value) {
    if (_phase == _OtpPhase.checking) return;

    // A paste lands the whole code in one box. Spreading it beats rejecting
    // it: the code arrives by email, and copying it is the obvious thing to do.
    if (value.length > 1) {
      _spread(value);
      return;
    }

    // Typing after a refusal clears the red rather than leaving the user
    // correcting a field that still looks broken.
    if (_phase == _OtpPhase.wrong) {
      setState(() => _phase = _OtpPhase.idle);
    }

    if (value.isNotEmpty && index < widget.length - 1) {
      _focus[index + 1].requestFocus();
    }

    _maybeSubmit();
  }

  void _spread(String raw) {
    final String digits = raw.replaceAll(RegExp(r'\D'), '');

    for (int i = 0; i < widget.length; i++) {
      _boxes[i].text = i < digits.length ? digits[i] : '';
    }

    final int next = math.min(digits.length, widget.length - 1);
    _focus[next].requestFocus();

    setState(() => _phase = _OtpPhase.idle);
    _maybeSubmit();
  }

  /// Backspace on an already-empty box.
  ///
  /// `onChanged` never fires for it - there is no change - so without this the
  /// caret stalls on an empty box and the key appears dead.
  KeyEventResult _onKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    if (_boxes[index].text.isNotEmpty || index == 0) {
      return KeyEventResult.ignored;
    }

    _boxes[index - 1].clear();
    _focus[index - 1].requestFocus();
    return KeyEventResult.handled;
  }

  // ------------------------------------------------------------- submitting

  Future<void> _maybeSubmit() async {
    final String code = _code;
    if (code.length != widget.length || _phase == _OtpPhase.checking) return;

    FocusScope.of(context).unfocus();
    setState(() => _phase = _OtpPhase.checking);

    final bool ok = await widget.onCompleted(code);
    if (!mounted) return;

    if (ok) {
      setState(() => _phase = _OtpPhase.correct);
      await _pop.forward(from: 0);
      // The caller advances the flow. Nothing else to do here - clearing the
      // boxes on success would flash an empty field on the way out.
      return;
    }

    setState(() => _phase = _OtpPhase.wrong);
    await _shake.forward(from: 0);

    // Long enough to read the message, short enough not to feel stuck.
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted || _phase != _OtpPhase.wrong) return;

    for (final TextEditingController c in _boxes) {
      c.clear();
    }
    setState(() => _phase = _OtpPhase.idle);
    _focus.first.requestFocus();
  }

  // ------------------------------------------------------------------ paint

  Color get _borderColor => switch (_phase) {
    _OtpPhase.correct => AppColors.success,
    _OtpPhase.wrong => AppColors.error,
    _OtpPhase.checking => AppColors.primary,
    _OtpPhase.idle => AppColors.border,
  };

  Color get _fillColor => switch (_phase) {
    _OtpPhase.correct => AppColors.successSoft,
    // The renovation promoted the error wash to a token, so a refused code
    // now fills as well as outlines. It previously fell back to the neutral
    // field colour with only a red border, which was the one state here that
    // did not match its own severity.
    _OtpPhase.wrong => AppColors.errorSoft,
    _ => AppColors.fieldFill,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AnimatedBuilder(
          animation: _shake,
          builder: (BuildContext context, Widget? child) {
            // Four oscillations, decaying linearly to zero. The decay is what
            // makes it settle rather than stop dead mid-swing.
            final double t = _shake.value;
            final double dx = math.sin(t * math.pi * 4) * 10 * (1 - t);
            return Transform.translate(offset: Offset(dx, 0), child: child);
          },
          child: Row(
            children: List<Widget>.generate(widget.length, (int i) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: i == widget.length - 1 ? 0 : AppSizes.sm,
                  ),
                  child: _box(i),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: AppSizes.md),
        _message(),
      ],
    );
  }

  Widget _box(int index) {
    return Focus(
      onKeyEvent: (FocusNode _, KeyEvent event) => _onKey(index, event),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        height: 56,
        decoration: BoxDecoration(
          color: _fillColor,
          borderRadius: BorderRadius.circular(AppSizes.fieldRadius),
          border: Border.all(color: _borderColor, width: 1.6),
        ),
        alignment: Alignment.center,
        child: TextField(
          controller: _boxes[index],
          focusNode: _focus[index],
          enabled: widget.enabled && _phase != _OtpPhase.correct,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          // Six separate boxes already say how many digits there are; a caret
          // hopping between them is noise.
          showCursor: false,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: switch (_phase) {
              _OtpPhase.correct => AppColors.success,
              _OtpPhase.wrong => AppColors.error,
              _ => AppColors.textPrimary,
            },
          ),
          decoration: const InputDecoration(
            counterText: '',
            border: InputBorder.none,
            focusedBorder: InputBorder.none,
            enabledBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            filled: false,
          ),
          onChanged: (String value) => _onChanged(index, value),
        ),
      ),
    );
  }

  Widget _message() {
    return switch (_phase) {
      _OtpPhase.checking => Row(
        children: <Widget>[
          const SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppSizes.sm),
          Text('Checking…', style: AppTextStyles.caption),
        ],
      ),

      _OtpPhase.correct => Row(
        children: <Widget>[
          ScaleTransition(
            scale: _popScale,
            child: const Icon(
              Icons.check_circle_rounded,
              size: 18,
              color: AppColors.success,
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          const Text(
            'Verified',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.success,
            ),
          ),
        ],
      ),

      _OtpPhase.wrong => const Row(
        children: <Widget>[
          Icon(Icons.error_outline_rounded, size: 18, color: AppColors.error),
          SizedBox(width: AppSizes.sm),
          Text(
            'Wrong code. Try again',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.error,
            ),
          ),
        ],
      ),

      _OtpPhase.idle => Text(
        'Check your spam folder if it has not arrived after a minute.',
        style: AppTextStyles.caption,
      ),
    };
  }
}
