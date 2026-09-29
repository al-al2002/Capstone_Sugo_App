import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_app_bar.dart';
import '../models/job.dart';
import '../models/match_result.dart';
import '../models/score_breakdown.dart';
import '../widgets/score_breakdown_sheet.dart';

/// How this request was ranked, step by step - the demonstration view.
///
/// ## Who it is for
///
/// A defence panel, an admin, a developer. It prints the brief's pipeline in
/// order - request, context, selected rules, Stage 1, Stage 2, recommendation,
/// Top 3 - with the numbers the engine actually stored. Nothing here is
/// recomputed on the phone; it is a reading of `job_matches.score_breakdown`
/// and of the matching response.
///
/// ## Why a client does not stumble into it
///
/// It is opened by a long press on the "Based on your current situation"
/// summary, plus a visible link in debug builds. A client choosing a
/// technician gets the plain "Why this technician?" sheet instead; this page
/// would only make that choice harder.
///
/// ## What "every technician" means here
///
/// Stages 1 to 3 list everyone the engine scored when [considered] is
/// available - it comes from the matching response and is not stored. Opened
/// later from a saved job, only the three stored matches are known, and the
/// page says so rather than implying the pool was three people.
class MatchingWalkthroughScreen extends StatelessWidget {
  const MatchingWalkthroughScreen({
    super.key,
    required this.matches,
    this.considered = const <ConsideredTechnician>[],
    this.job,
  });

  final List<MatchResult> matches;
  final List<ConsideredTechnician> considered;
  final Job? job;

  @override
  Widget build(BuildContext context) {
    final ScoreBreakdown? top = matches.isEmpty ? null : matches.first.breakdown;
    final RecommendationStage? rec = top?.recommendation;

    final List<_Row> rows = considered.isNotEmpty
        ? <_Row>[
            for (final ConsideredTechnician c in considered)
              _Row(
                name: c.name,
                suitability: c.suitability,
                acceptance: c.acceptance,
                recommendation: c.finalScore,
                offered: c.offered,
              ),
          ]
        : <_Row>[
            for (final MatchResult m in matches)
              _Row(
                name: m.technician?.displayName ?? 'Technician',
                suitability: m.breakdown.stage1.score,
                acceptance: m.breakdown.stage2.score,
                recommendation: m.finalScore,
                offered: true,
              ),
          ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const SugoAppBar(title: 'How this was ranked'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSizes.screenPadding,
          AppSizes.md,
          AppSizes.screenPadding,
          AppSizes.xxl,
        ),
        children: <Widget>[
          Text(
            'The RB-CARS pipeline for this request, with the numbers the '
            'engine stored. For demonstration and review.',
            style: AppTextStyles.subtitle,
          ),
          const SizedBox(height: AppSizes.lg),

          _Step(
            number: 1,
            title: 'Service request',
            child: _Pairs(<(String, String)>[
              if (job != null) ('Repair', job!.title),
              if (job?.brand != null) ('Brand', job!.brand!),
              if (job != null) ('Budget', job!.budgetLabel),
              ('Urgency', _urgency(top?.context.urgency ?? job?.urgency.wire)),
              if (top?.context.servicePath != null)
                ('Service', top!.context.servicePath!.replaceAll('_', ' ')),
            ]),
          ),

          _Step(
            number: 2,
            title: 'Context-aware analysis',
            child: _Pairs(<(String, String)>[
              ('Weather', top?.context.weatherLabel ?? 'Unavailable - skipped'),
              ('Traffic', top?.context.trafficLabel ?? 'Unavailable - skipped'),
              (
                'Signals',
                rec == null || rec.signals.isEmpty
                    ? '—'
                    : rec.signals.map((String s) => s.replaceAll('_', ' ')).join(', '),
              ),
            ]),
          ),

          _Step(
            number: 3,
            title: 'Rule-based weight selection',
            child: rec == null
                ? const _Muted(
                    'Scored before matching rules existed (version 1). '
                    'Fixed weights were used.',
                  )
                : rec.rules.isEmpty
                ? const _Muted(
                    'No special conditions held, so the base weights were '
                    'used unchanged.',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (final AppliedRule rule in rec.rules)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSizes.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'IF ${rule.when.map((String s) => s.replaceAll('_', ' ')).join(' AND ')}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              Text(
                                rule.label,
                                style: AppTextStyles.titleSmall,
                              ),
                              const SizedBox(height: 2),
                              for (final RuleEffect e in rule.effects)
                                Text(
                                  '→ ${factorDisplayName(e.factor)} '
                                  '(${e.stage}) ×${e.multiplier}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.cyanDark,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),

          if (considered.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: AppSizes.md),
              child: _Muted(
                'Opened from a saved job: only the three stored matches are '
                'known. The full pool is listed right after a fresh match.',
              ),
            ),

          _Step(
            number: 4,
            title: 'Stage 1 - Suitability (can they do it?)',
            child: _Scores(rows: rows, pick: (_Row r) => r.suitability),
          ),
          _Step(
            number: 5,
            title: 'Stage 2 - Acceptance (are they likely to take it?)',
            child: _Scores(rows: rows, pick: (_Row r) => r.acceptance),
          ),
          _Step(
            number: 6,
            title: 'Recommendation engine',
            child: _Scores(rows: rows, pick: (_Row r) => r.recommendation),
          ),
          _Step(
            number: 7,
            title: 'Final Top 3',
            child: Column(
              children: <Widget>[
                for (final MatchResult m in matches)
                  _ScoreLine(
                    name:
                        '${m.rankLabel} - ${m.technician?.displayName ?? 'Technician'}',
                    value: m.finalScore,
                    highlight: m.isTopPick,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _urgency(String? wire) => switch (wire) {
    'need_today' => 'Urgent - needed today',
    'can_wait' => 'Can wait',
    _ => '—',
  };
}

class _Row {
  const _Row({
    required this.name,
    required this.suitability,
    required this.acceptance,
    required this.recommendation,
    required this.offered,
  });

  final String name;
  final double suitability;
  final double acceptance;
  final double recommendation;
  final bool offered;
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.title, required this.child});

  final int number;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.md),
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.panelRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$number',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.sm + 2),
              Expanded(child: Text(title, style: AppTextStyles.titleSmall)),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          child,
        ],
      ),
    );
  }
}

class _Pairs extends StatelessWidget {
  const _Pairs(this.pairs);

  final List<(String, String)> pairs;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (final (String, String) p in pairs)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 84,
                  child: Text(
                    p.$1,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    p.$2,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
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

class _Scores extends StatelessWidget {
  const _Scores({required this.rows, required this.pick});

  final List<_Row> rows;
  final double Function(_Row) pick;

  @override
  Widget build(BuildContext context) {
    // Each stage sorted by its own score, so the panel can see a technician
    // rise or fall between stages - which is the point of having three.
    final List<_Row> sorted = <_Row>[...rows]
      ..sort((_Row a, _Row b) => pick(b).compareTo(pick(a)));
    return Column(
      children: <Widget>[
        for (final _Row r in sorted)
          _ScoreLine(name: r.name, value: pick(r), highlight: r.offered),
      ],
    );
  }
}

class _ScoreLine extends StatelessWidget {
  const _ScoreLine({
    required this.name,
    required this.value,
    this.highlight = false,
  });

  final String name;
  final double value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final int percent = (value.clamp(0, 1) * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
                color: highlight ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            '$percent',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: highlight ? AppColors.cyanDark : AppColors.hint,
            ),
          ),
        ],
      ),
    );
  }
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: AppTextStyles.caption.copyWith(height: 1.4));
}
