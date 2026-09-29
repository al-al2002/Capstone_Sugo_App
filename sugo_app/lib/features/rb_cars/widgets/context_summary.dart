import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../models/job.dart';
import '../models/match_result.dart';
import '../models/score_breakdown.dart';

/// "Based on your current situation" - the context-aware part, made visible.
///
/// A row of chips for what the engine actually saw when it ranked the list -
/// the weather, the traffic, the urgency, the repair, the distances, the
/// budget - and, when the conditions were unusual, a line naming the matching
/// rules that re-weighted the ranking for them.
///
/// Everything comes from the job and from the top match's breakdown. A chip
/// whose data is missing is simply not drawn: if OpenWeatherMap was down there
/// is no weather chip, rather than a chip that guesses.
///
/// Orange marks the conditions that changed the ranking (rain, heavy traffic,
/// urgency). Everything else is neutral - orange on every chip would stop
/// meaning anything.
class ContextSummary extends StatelessWidget {
  const ContextSummary({super.key, required this.matches, this.job, this.onLongPress});

  final List<MatchResult> matches;
  final Job? job;

  /// Opens the ranking walkthrough. A long press, so it is there for a demo
  /// without being in a client's way.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final List<ContextChipData> chips = contextChipsFor(matches, job);
    final List<String> rules = matches.isEmpty
        ? const <String>[]
        : (matches.first.breakdown.recommendation?.rules ?? const <AppliedRule>[])
              .map((AppliedRule r) => r.label)
              .toList();

    if (chips.isEmpty && rules.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Sentence case since the Dispatch redesign - see
          // AppTextStyles.overline.
          const Text(
            'Based on your current situation',
            style: AppTextStyles.overline,
          ),
          const SizedBox(height: AppSizes.sm),
          Wrap(
            spacing: AppSizes.sm,
            runSpacing: AppSizes.sm,
            children: <Widget>[
              for (final ContextChipData chip in chips) ContextChip(data: chip),
            ],
          ),
          if (rules.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSizes.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.tune_rounded,
                    size: 15,
                    color: AppColors.cyanDark,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Ranking adjusted for: ${rules.join(' · ')}',
                    style: AppTextStyles.micro.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.cyanDark,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// What one chip says.
class ContextChipData {
  const ContextChipData({
    required this.icon,
    required this.label,
    this.emphasised = false,
  });

  final IconData icon;
  final String label;

  /// True for a condition that changed the ranking - drawn in orange.
  final bool emphasised;
}

/// The chips, in the brief's order: weather, traffic, urgency, repair,
/// distance, budget. Public so it can be tested without pumping a screen.
List<ContextChipData> contextChipsFor(List<MatchResult> matches, Job? job) {
  final List<ContextChipData> chips = <ContextChipData>[];
  if (matches.isEmpty) return chips;

  final ScoreBreakdown top = matches.first.breakdown;
  final MatchContext ctx = top.context;
  final Set<String> signals =
      (top.recommendation?.signals ?? const <String>[]).toSet();

  final String? weather = ctx.weatherLabel;
  if (weather != null && weather.isNotEmpty) {
    final bool rain = signals.contains('rain') ||
        (ctx.weatherSeverity ?? 0) >= 0.5;
    chips.add(
      ContextChipData(
        icon: rain ? Icons.water_drop_rounded : Icons.wb_sunny_outlined,
        label: _capitalise(weather),
        emphasised: rain,
      ),
    );
  }

  final String? traffic = ctx.trafficLabel;
  if (traffic != null && traffic.isNotEmpty) {
    final bool heavy = signals.contains('heavy_traffic') ||
        (ctx.congestion ?? 0) >= 0.6;
    chips.add(
      ContextChipData(
        icon: Icons.directions_car_filled_outlined,
        label: _capitalise(traffic),
        emphasised: heavy,
      ),
    );
  }

  final String? urgency = ctx.urgency ?? job?.urgency.wire;
  if (urgency == 'need_today') {
    chips.add(
      const ContextChipData(
        icon: Icons.bolt_rounded,
        label: 'Urgent',
        emphasised: true,
      ),
    );
  } else if (urgency == 'can_wait') {
    chips.add(
      const ContextChipData(icon: Icons.schedule_rounded, label: 'Can wait'),
    );
  }

  if (job != null) {
    chips.add(
      ContextChipData(
        icon: job.deviceType.icon,
        label: '${job.brand ?? job.deviceType.label} repair',
      ),
    );
  }

  final List<double> distances = <double>[
    for (final MatchResult m in matches)
      if (m.breakdown.context.distanceKm != null) m.breakdown.context.distanceKm!,
  ];
  if (distances.isNotEmpty) {
    distances.sort();
    final String low = _km(distances.first);
    final String high = _km(distances.last);
    chips.add(
      ContextChipData(
        icon: Icons.place_outlined,
        label: low == high ? '$low km' : '$low–$high km',
      ),
    );
  }

  final double? budget = job?.budgetMax;
  if (budget != null && budget > 0) {
    chips.add(
      ContextChipData(
        icon: Icons.payments_outlined,
        label: '${Fmt.peso(budget)} budget',
      ),
    );
  }

  return chips;
}

/// "2.1", "3" (not "3.0"), "12".
String _km(double km) {
  if (km >= 10) return km.round().toString();
  final String fixed = km.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}

String _capitalise(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';

/// One pill of context. Reusable anywhere a condition needs naming.
class ContextChip extends StatelessWidget {
  const ContextChip({super.key, required this.data});

  final ContextChipData data;

  @override
  Widget build(BuildContext context) {
    final bool hot = data.emphasised;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: 6),
      decoration: BoxDecoration(
        color: hot ? AppColors.accentSofter : AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        border: Border.all(
          color: hot ? AppColors.accentSoft : AppColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            data.icon,
            size: 14,
            color: hot ? AppColors.accentDark : AppColors.secondary,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              data.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.micro.copyWith(
                fontWeight: FontWeight.w700,
                color: hot ? AppColors.accentDark : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
