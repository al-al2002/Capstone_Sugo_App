import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/primary_button.dart';
import '../../rb_cars/models/job.dart';
import '../../rb_cars/models/job_price.dart';
import '../../rb_cars/models/match_result.dart';
import '../../rb_cars/models/score_breakdown.dart';
import '../../rb_cars/widgets/urgent_countdown.dart';

/// "Ready to take this job?" - the last look before a technician accepts
/// (2026-11-17).
///
/// It used to be a plain `AlertDialog`: two grey boxes reading "light rain"
/// and "Not available", with Cancel and "Proceed to accept task" as text
/// buttons. It now answers the three things a technician weighs at that
/// moment, top to bottom:
///
///   1. **What it pays** - the estimated total, from the same price the
///      client was quoted;
///   2. **What it is like out there** - weather with an icon and tint that
///      follow the conditions, traffic with a congestion bar, and an honest
///      "not available" when a service was down;
///   3. **What to do about it** - one or two rule-based tips ("bring a
///      waterproof bag"), only when the data supports them.
///
/// Sections rise in one after another (a short stagger, still under reduced
/// motion). Returns true when they accept.
///
/// It opens from both "Accept this job" in View task and the dashboard card's
/// Accept. On an urgent offer it also shows the five-minute clock and closes
/// itself when the clock runs out. Otherwise the dialog would hide the clock,
/// and an "Accept job" sent after the server's sweep had passed the offer on
/// could only fail.
Future<bool?> showAcceptJobDialog(
  BuildContext context, {
  required MatchResult match,
}) {
  return showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => _AcceptJobDialog(match: match),
  );
}

class _AcceptJobDialog extends StatefulWidget {
  const _AcceptJobDialog({required this.match});

  final MatchResult match;

  @override
  State<_AcceptJobDialog> createState() => _AcceptJobDialogState();
}

class _AcceptJobDialogState extends State<_AcceptJobDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AppMotion.reduced(context)) {
      _entrance.value = 1;
    } else {
      _entrance.forward();
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  /// Section [index] of [count] fades and rises in its own slice of the
  /// entrance.
  Widget _stagger(int index, int count, Widget child) {
    final double start = index / (count + 1);
    final Animation<double> curve = CurvedAnimation(
      parent: _entrance,
      curve: Interval(
        start,
        (start + 0.5).clamp(0, 1),
        curve: AppMotion.standard,
      ),
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.12),
          end: Offset.zero,
        ).animate(curve),
        child: child,
      ),
    );
  }

  /// The urgent clock ran out: the offer has gone to the next technician, so
  /// close with no answer (null), and nothing is accepted. Only while this
  /// dialog is still the top route, so it never pops something else.
  void _closeWhenTimeIsUp() {
    if (ModalRoute.of(context)?.isCurrent ?? false) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final MatchContext conditions = widget.match.breakdown.context;
    final JobSnapshot? job = widget.match.job;
    final DateTime? deadline = widget.match.urgentDeadline;
    final JobPrice? price = job == null
        ? null
        : JobPrice.forSnapshot(job, distanceKm: conditions.distanceKm);
    final List<_Tip> tips = _tipsFor(conditions);

    final List<Widget> sections = <Widget>[
      _Header(job: job),
      if (deadline != null)
        Center(
          child: UrgentCountdown(
            deadline: deadline,
            onExpired: _closeWhenTimeIsUp,
          ),
        ),
      if (price != null) _EarningsBand(price: price),
      _ConditionCards(conditions: conditions),
      if (tips.isNotEmpty) _Tips(tips: tips),
    ];

    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSizes.lg,
        vertical: AppSizes.xl,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.sheetRadius + 4),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSizes.lg,
            AppSizes.xl,
            AppSizes.lg,
            AppSizes.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < sections.length; i++) ...<Widget>[
                _stagger(i, sections.length, sections[i]),
                const SizedBox(height: AppSizes.lg),
              ],
              _stagger(
                sections.length,
                sections.length,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    PrimaryButton(
                      label: 'Accept job',
                      icon: Icons.check_rounded,
                      onPressed: () => Navigator.of(context).pop(true),
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
                      child: const Text('Not yet'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ header

class _Header extends StatelessWidget {
  const _Header({required this.job});

  final JobSnapshot? job;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        // A handshake on a brand gradient, landing with a small overshoot.
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.5, end: 1),
          duration: AppMotion.reduced(context) ? Duration.zero : AppMotion.slow,
          curve: AppMotion.playful,
          builder: (BuildContext context, double scale, Widget? child) =>
              Transform.scale(scale: scale, child: child),
          child: Container(
            width: 68,
            height: 68,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[AppColors.primary, AppColors.secondary],
              ),
            ),
            child: const Icon(
              Icons.handshake_rounded,
              size: 32,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: AppSizes.md),
        Text(
          'Ready to take this job?',
          textAlign: TextAlign.center,
          style: AppTextStyles.headline,
        ),
        if (job != null) ...<Widget>[
          const SizedBox(height: AppSizes.xs),
          Text(
            '${job!.deviceType.label} · ${job!.symptomLabel}',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption,
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- earnings

/// "You'll earn about ₱860" - the estimate, with how it is made up.
class _EarningsBand extends StatelessWidget {
  const _EarningsBand({required this.price});

  final JobPrice price;

  @override
  Widget build(BuildContext context) {
    final String amount = price.headline;
    final String? breakdown = price.labor == null
        ? null
        : <String>[
            'Labor ${price.labor!.fee}',
            if (price.hasUrgentFee) 'urgent ${price.urgentFeeText}',
            if (price.distanceFeePhrase case final String fee) fee,
          ].join(' + ');

    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.successSoft,
        borderRadius: BorderRadius.circular(AppSizes.radius),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.payments_rounded,
            color: AppColors.success,
            size: 22,
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  price.total == null ? 'Labor fee' : "You'll earn about",
                  style: AppTextStyles.micro.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.success,
                  ),
                ),
                Text(
                  amount,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (breakdown != null && price.total != null)
                  Text(breakdown, style: AppTextStyles.micro),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- conditions

class _ConditionCards extends StatelessWidget {
  const _ConditionCards({required this.conditions});

  final MatchContext conditions;

  @override
  Widget build(BuildContext context) {
    final Widget weather = _WeatherCard(conditions: conditions);
    final Widget traffic = _TrafficCard(conditions: conditions);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'At the job site',
          style: AppTextStyles.micro.copyWith(
            fontWeight: FontWeight.w800,
            color: AppColors.textSecondary,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: AppSizes.sm),
        // Side by side when there is room; stacked on a narrow phone or at
        // large text, so neither card is squeezed.
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) =>
              box.maxWidth < 300
              ? Column(
                  children: <Widget>[
                    weather,
                    const SizedBox(height: AppSizes.sm),
                    traffic,
                  ],
                )
              : IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(child: weather),
                      const SizedBox(width: AppSizes.sm),
                      Expanded(child: traffic),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

/// A condition card: icon tile, label, value, and an optional footer.
class _ConditionCard extends StatelessWidget {
  const _ConditionCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
    required this.ink,
    this.footer,
    this.unavailable = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tint;
  final Color ink;
  final Widget? footer;
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSizes.md),
        decoration: BoxDecoration(
          color: unavailable ? AppColors.background : tint,
          borderRadius: BorderRadius.circular(AppSizes.radius),
          border: Border.all(
            color: unavailable ? AppColors.border : ink.withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSizes.sm + 2),
              ),
              child: Icon(
                icon,
                size: 20,
                color: unavailable ? AppColors.hint : ink,
              ),
            ),
            const SizedBox(height: AppSizes.sm),
            Text(label, style: AppTextStyles.micro),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: unavailable
                    ? AppColors.textSecondary
                    : AppColors.textPrimary,
              ),
            ),
            if (footer != null) ...<Widget>[
              const SizedBox(height: AppSizes.sm),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({required this.conditions});

  final MatchContext conditions;

  @override
  Widget build(BuildContext context) {
    final String? label = conditions.weatherLabel;
    if (label == null) {
      return const _ConditionCard(
        icon: Icons.cloud_off_rounded,
        label: 'Weather',
        value: 'Not available',
        tint: AppColors.background,
        ink: AppColors.hint,
        unavailable: true,
      );
    }

    final _Sky sky = _Sky.of(label, conditions.weatherSeverity);
    final double? temp = conditions.tempC;

    return _ConditionCard(
      icon: sky.icon,
      label: 'Weather',
      value: _capitalise(label),
      tint: sky.tint,
      ink: sky.ink,
      footer: temp == null
          ? null
          : Text(
              '${temp.round()}°C',
              style: AppTextStyles.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: sky.ink,
              ),
            ),
    );
  }
}

class _TrafficCard extends StatelessWidget {
  const _TrafficCard({required this.conditions});

  final MatchContext conditions;

  @override
  Widget build(BuildContext context) {
    final String? label = conditions.trafficLabel;
    if (label == null) {
      return const _ConditionCard(
        icon: Icons.traffic_rounded,
        label: 'Traffic',
        value: 'Not available',
        tint: AppColors.background,
        ink: AppColors.hint,
        unavailable: true,
      );
    }

    final double congestion = (conditions.congestion ?? 0).clamp(0, 1);
    final Color ink = congestion >= 0.6
        ? AppColors.error
        : congestion >= 0.3
        ? AppColors.warning
        : AppColors.success;
    final Color tint = congestion >= 0.6
        ? AppColors.errorSoft
        : congestion >= 0.3
        ? AppColors.warningSoft
        : AppColors.successSoft;

    return _ConditionCard(
      icon: Icons.traffic_rounded,
      label: 'Traffic',
      value: _capitalise(label),
      tint: tint,
      ink: ink,
      // How jammed the roads are, as a bar that fills to the congestion.
      footer: conditions.congestion == null
          ? null
          : TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: congestion),
              duration: AppMotion.reduced(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 700),
              curve: AppMotion.standard,
              builder: (BuildContext context, double value, Widget? _) =>
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                    child: LinearProgressIndicator(
                      value: value,
                      minHeight: 6,
                      backgroundColor: AppColors.surface,
                      color: ink,
                    ),
                  ),
            ),
    );
  }
}

/// The weather's icon and colours, from its label and severity.
class _Sky {
  const _Sky(this.icon, this.tint, this.ink);

  final IconData icon;
  final Color tint;
  final Color ink;

  static _Sky of(String label, double? severity) {
    final String l = label.toLowerCase();
    if (l.contains('thunder') || l.contains('storm')) {
      return const _Sky(
        Icons.thunderstorm_rounded,
        AppColors.warningSoft,
        AppColors.warning,
      );
    }
    if (l.contains('rain') || l.contains('drizzle') || l.contains('shower')) {
      return (severity ?? 0) >= 0.5
          ? const _Sky(
              Icons.water_drop_rounded,
              AppColors.warningSoft,
              AppColors.warning,
            )
          : const _Sky(
              Icons.water_drop_rounded,
              AppColors.secondarySoft,
              AppColors.secondaryDark,
            );
    }
    if (l.contains('clear') || l.contains('sun')) {
      return const _Sky(
        Icons.wb_sunny_rounded,
        AppColors.accentSofter,
        AppColors.accentDark,
      );
    }
    return const _Sky(
      Icons.cloud_rounded,
      AppColors.primarySofter,
      AppColors.primaryDark,
    );
  }
}

// -------------------------------------------------------------------- tips

class _Tip {
  const _Tip(this.icon, this.text);

  final IconData icon;
  final String text;
}

/// One or two tips, each only when the data behind it is there.
List<_Tip> _tipsFor(MatchContext conditions) {
  final String weather = (conditions.weatherLabel ?? '').toLowerCase();
  final String traffic = (conditions.trafficLabel ?? '').toLowerCase();
  final double congestion = conditions.congestion ?? 0;

  final bool wet =
      weather.contains('rain') ||
      weather.contains('drizzle') ||
      weather.contains('shower') ||
      weather.contains('storm');
  final bool jammed = congestion >= 0.5 || traffic.contains('heavy');

  return <_Tip>[
    if (wet)
      const _Tip(
        Icons.umbrella_rounded,
        'Wet out there - bring a waterproof bag for the unit and your tools.',
      ),
    if (jammed)
      const _Tip(
        Icons.schedule_rounded,
        'Heavy traffic - allow extra travel time and tell the client.',
      ),
    if (!wet && !jammed && conditions.weatherLabel != null)
      const _Tip(
        Icons.directions_car_rounded,
        'Good conditions - a fine time to head out.',
      ),
  ];
}

class _Tips extends StatelessWidget {
  const _Tips({required this.tips});

  final List<_Tip> tips;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (final _Tip tip in tips)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSizes.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(tip.icon, size: 16, color: AppColors.primaryDark),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: Text(
                    tip.text,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

String _capitalise(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
