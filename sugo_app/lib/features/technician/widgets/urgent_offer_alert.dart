import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../rb_cars/models/job.dart';
import '../../rb_cars/models/job_price.dart';
import '../../rb_cars/models/match_result.dart';
import '../../rb_cars/widgets/urgent_countdown.dart';
import 'accept_job_dialog.dart';

/// What the technician chose on the urgent alert.
enum UrgentOfferChoice { accept, decline, details }

/// The full-screen alert for an urgent request (2026-11-17).
///
/// The in-app half of the "hard notify" the user asked for. A push is what
/// reaches a phone in a pocket (on the `sugo_urgent` channel: sound,
/// vibration, heads-up); this is what reaches a technician who already has
/// SUGO open, where the system shows no notification at all. It takes the
/// whole screen, buzzes, and shows the five minutes running out, with the
/// two answers as the only buttons.
///
/// It closes by itself when the time is up - by then the request has gone to
/// another technician - and returns null.
Future<UrgentOfferChoice?> showUrgentOfferAlert(
  BuildContext context,
  MatchResult match,
) {
  // The buzz: three firm pulses and the system alert sound. Not a loop - a
  // phone that keeps vibrating in a hand is alarming rather than urgent.
  unawaited(_buzz());
  return showGeneralDialog<UrgentOfferChoice>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Urgent job request',
    barrierColor: AppColors.navy.withValues(alpha: 0.86),
    transitionDuration: AppMotion.reduced(context)
        ? Duration.zero
        : AppMotion.slow,
    pageBuilder: (BuildContext ctx, Animation<double> _, Animation<double> _) =>
        _UrgentOfferAlert(match: match),
    transitionBuilder:
        (
          BuildContext ctx,
          Animation<double> a,
          Animation<double> _,
          Widget child,
        ) => FadeTransition(
          opacity: a,
          child: ScaleTransition(
            scale: Tween<double>(
              begin: 0.92,
              end: 1,
            ).animate(CurveTween(curve: AppMotion.emphasized).animate(a)),
            child: child,
          ),
        ),
  );
}

Future<void> _buzz() async {
  for (int i = 0; i < 3; i++) {
    await HapticFeedback.heavyImpact();
    await SystemSound.play(SystemSoundType.alert);
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }
}

class _UrgentOfferAlert extends StatelessWidget {
  const _UrgentOfferAlert({required this.match});

  final MatchResult match;

  /// "Accept job" asks "Ready to take this job?" first (2026-11-17).
  ///
  /// The user's reason: technicians were tapping the big green button on
  /// reflex and accepting without seeing the weather or traffic on the way.
  /// The weather-and-traffic dialog now opens on top of this alert. "Not
  /// yet" returns here with the clock still running, so Decline and View
  /// task are still one tap away. Only "Accept job" in the dialog answers
  /// the alert.
  Future<void> _confirmAccept(BuildContext context) async {
    final bool? proceed = await showAcceptJobDialog(context, match: match);
    if (proceed != true || !context.mounted) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    Navigator.of(context).pop(UrgentOfferChoice.accept);
  }

  /// Time is up: close this alert, and the accept dialog too if it is open
  /// on top. This used to be `maybePop()`, which closes whatever is on top,
  /// so with the dialog open it would have closed only the dialog and left
  /// this alert on screen after the request had gone to someone else.
  void _closeWhenTimeIsUp(BuildContext context) {
    final ModalRoute<Object?>? alert = ModalRoute.of(context);
    if (alert == null || !alert.isActive) return;
    final NavigatorState navigator = Navigator.of(context);
    navigator.popUntil((Route<dynamic> route) => route == alert);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final JobSnapshot? job = match.job;
    final JobPrice? price = job == null
        ? null
        : JobPrice.forSnapshot(
            job,
            distanceKm: match.breakdown.context.distanceKm,
          );
    final DateTime deadline =
        match.urgentDeadline ?? DateTime.now().add(MatchResult.urgentWindow);
    final double? km = match.breakdown.context.distanceKm;

    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.screenPadding),
          child: Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSizes.cardRadius),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const _AlertHeader(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSizes.lg,
                      AppSizes.lg,
                      AppSizes.lg,
                      AppSizes.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          job?.title ?? 'Urgent repair',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.title,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          <String>[
                            if (job?.servicePath != null)
                              job!.servicePath!.label,
                            if (km != null) '${km.toStringAsFixed(1)} km away',
                          ].join('  ·  '),
                          textAlign: TextAlign.center,
                          style: AppTextStyles.caption,
                        ),
                        if (price != null) ...<Widget>[
                          const SizedBox(height: AppSizes.md),
                          _PriceStrip(price: price),
                        ],
                        const SizedBox(height: AppSizes.lg),
                        Center(
                          child: UrgentCountdown(
                            deadline: deadline,
                            // Gone to someone else: close quietly.
                            onExpired: () => _closeWhenTimeIsUp(context),
                          ),
                        ),
                        const SizedBox(height: AppSizes.sm),
                        const Text(
                          'Accept within 5 minutes or it goes to another '
                          'technician.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSizes.lg),
                        FilledButton.icon(
                          onPressed: () => _confirmAccept(context),
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Accept job'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.success,
                            minimumSize: const Size.fromHeight(
                              AppSizes.buttonHeight,
                            ),
                            textStyle: const TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSizes.sm),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(
                                  context,
                                ).pop(UrgentOfferChoice.details),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(
                                    AppSizes.touchTarget,
                                  ),
                                ),
                                child: const Text('View task'),
                              ),
                            ),
                            const SizedBox(width: AppSizes.sm),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(
                                  context,
                                ).pop(UrgentOfferChoice.decline),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.error,
                                  minimumSize: const Size.fromHeight(
                                    AppSizes.touchTarget,
                                  ),
                                ),
                                child: const Text('Decline'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The orange band at the top, with a bolt that pulses a few times.
class _AlertHeader extends StatelessWidget {
  const _AlertHeader();

  @override
  Widget build(BuildContext context) {
    final bool reduced = AppMotion.reduced(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.lg),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[AppColors.accent, AppColors.accentDark],
        ),
      ),
      child: Column(
        children: <Widget>[
          // Three pulses, then still: enough to say "now", not a siren.
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: reduced ? 0 : 3),
            duration: reduced ? Duration.zero : const Duration(seconds: 2),
            builder: (BuildContext _, double t, Widget? child) {
              final double pulse = (t % 1);
              return Transform.scale(
                scale: 1 + 0.12 * (1 - (2 * pulse - 1).abs()),
                child: child,
              );
            },
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.bolt_rounded,
                size: 34,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: AppSizes.sm),
          const Text(
            'URGENT JOB REQUEST',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'A client needs this fixed today',
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Labor ₱600 + urgent ₱120 + travel ₱65 = ₱785".
class _PriceStrip extends StatelessWidget {
  const _PriceStrip({required this.price});

  final JobPrice price;

  @override
  Widget build(BuildContext context) {
    final String parts = <String>[
      if (price.labor != null) 'Labor ${price.labor!.fee}',
      if (price.hasUrgentFee) 'urgent ${price.urgentFeeText}',
      if (price.distanceFeeLines
          case final List<({String label, int amount})> lines)
        lines.length == 2
            ? 'pickup ₱${lines[0].amount} + delivery ₱${lines[1].amount}'
            : 'travel ₱${lines.single.amount}',
    ].join(' + ');

    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.successSoft,
        borderRadius: BorderRadius.circular(AppSizes.radius),
      ),
      child: Column(
        children: <Widget>[
          Text(
            price.headline,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          if (parts.isNotEmpty)
            Text(
              parts,
              textAlign: TextAlign.center,
              style: AppTextStyles.micro,
            ),
        ],
      ),
    );
  }
}
