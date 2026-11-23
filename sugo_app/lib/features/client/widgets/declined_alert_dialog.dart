import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_motion.dart';

/// What the client can do after a decline - the push's `next`
/// (`_shared/decline_notice.ts`).
enum DeclinedNext {
  /// Others from the same match are still there.
  shortlist,

  /// The shortlist ran out, and a fresh match found more.
  more,

  /// Nobody else is free right now.
  none,

  /// A server deployed before `next` existed.
  unknown;

  static DeclinedNext fromWire(String? value) => switch (value) {
    'shortlist' => DeclinedNext.shortlist,
    'more' => DeclinedNext.more,
    'none' => DeclinedNext.none,
    _ => DeclinedNext.unknown,
  };
}

/// Shows the "can't take this one" pop-up. Returns true when the client
/// asked to choose another technician (or, when nobody is free, to open the
/// request).
Future<bool> showDeclinedAlert(
  BuildContext context, {
  String? name,
  String? next,
}) async {
  final bool? go = await showDialog<bool>(
    context: context,
    builder: (_) =>
        DeclinedAlertDialog(name: name, next: DeclinedNext.fromWire(next)),
  );
  return go ?? false;
}

/// The pop-up a client sees when the technician they chose declines
/// (2026-11-23).
///
/// ## Why a pop-up and not a snackbar
///
/// Until now SUGO said it in a snackbar when the app was open ("Your
/// technician can't take this one. Choose another."). It was gone in four
/// seconds, and nothing on screen asked the client to act - yet their
/// request is now waiting on THEM, not on a technician. A pop-up holds until
/// it is read and puts the way forward on one button.
///
/// When SUGO is closed, Android shows the push in the tray instead, and
/// tapping it opens the same place the button does.
///
/// ## The words follow what actually happened
///
/// The server says what is left (`next`): the rest of the shortlist, a fresh
/// match that found more, or nobody. An older server sends no `next`, and the
/// pop-up falls back to a sentence true in every case.
class DeclinedAlertDialog extends StatelessWidget {
  const DeclinedAlertDialog({super.key, this.name, required this.next});

  /// The technician's first name, or null.
  final String? name;
  final DeclinedNext next;

  String get _who {
    final String? n = name?.trim();
    return n == null || n.isEmpty ? 'Your technician' : n;
  }

  String get _chip => switch (next) {
    DeclinedNext.shortlist => 'Your shortlist is still there',
    DeclinedNext.more => 'More technicians found',
    DeclinedNext.none => 'Nobody else is free yet',
    DeclinedNext.unknown => 'Your request is open again',
  };

  String get _body => switch (next) {
    DeclinedNext.shortlist =>
      'Pick someone else from the technicians SUGO already found for you. '
          'You do not need to post again.',
    DeclinedNext.more =>
      'SUGO looked again and found more technicians for you. Pick one to '
          'send your request.',
    DeclinedNext.none =>
      'No other technician is free right now. Open your request to try '
          'again in a little while.',
    DeclinedNext.unknown =>
      'Your request is open again. Choose another technician to send it to.',
  };

  String get _action => next == DeclinedNext.none
      ? 'Open my request'
      : 'Choose another technician';

  @override
  Widget build(BuildContext context) {
    final bool reduced = AppMotion.reduced(context);

    final Widget body = Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSizes.xl,
        vertical: AppSizes.xl,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.sheetRadius + 4),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const _Hero(),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.lg,
                  AppSizes.lg,
                  AppSizes.lg,
                  AppSizes.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      "$_who can't take this one",
                      textAlign: TextAlign.center,
                      style: AppTextStyles.title,
                    ),
                    const SizedBox(height: AppSizes.sm),
                    Center(child: _Chip(text: _chip)),
                    const SizedBox(height: AppSizes.md),
                    Text(
                      _body,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body,
                    ),
                    const SizedBox(height: AppSizes.lg),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: Icon(
                        next == DeclinedNext.none
                            ? Icons.receipt_long_rounded
                            : Icons.groups_rounded,
                        size: 18,
                      ),
                      label: Text(_action),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(
                          AppSizes.buttonHeight,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSizes.xs),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        minimumSize: const Size.fromHeight(
                          AppSizes.touchTarget,
                        ),
                      ),
                      child: const Text('Later'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // The same small spring in as the "running late" pop-up: news, not an
    // alarm.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.88, end: 1),
      duration: reduced ? Duration.zero : AppMotion.slow,
      curve: AppMotion.playful,
      builder: (BuildContext context, double scale, Widget? child) =>
          Transform.scale(scale: scale, child: child),
      child: body,
    );
  }
}

/// A calm band with the technician's place left empty: the icon shakes its
/// head once (three swings) and settles.
class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final Widget icon = Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.secondary, width: 3),
      ),
      child: const Icon(
        Icons.person_off_rounded,
        size: 38,
        color: AppColors.primary,
      ),
    );

    return Container(
      height: 132,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[AppColors.secondarySoft, AppColors.surface],
        ),
      ),
      child: ExcludeSemantics(
        child: AppMotion.reduced(context)
            ? icon
            : SugoWiggle(angle: 0.18, alignment: Alignment.center, child: icon),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.secondarySoft,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppTextStyles.micro.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
