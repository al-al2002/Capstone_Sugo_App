import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/rb_cars/models/match_result.dart';
import 'package:sugo_app/features/rb_cars/models/score_breakdown.dart';
import 'package:sugo_app/features/rb_cars/screens/matching_walkthrough_screen.dart';
import 'package:sugo_app/features/rb_cars/widgets/context_summary.dart';
import 'package:sugo_app/features/rb_cars/widgets/match_score_card.dart';
import 'package:sugo_app/features/rb_cars/widgets/recommendation_reasons_sheet.dart';

/// The recommendation layer as the client sees it: the version 2 contract,
/// the version 1 fallback, the context chips, the card, the "Why" sheet and
/// the demo walkthrough.
///
/// The card golden is for design review. Regenerate after intentional changes:
///
///   flutter test --update-goldens test/features/rb_cars/recommendation_ui_test.dart
void main() {
  Map<String, dynamic> factor(
    String key,
    double value,
    double weight, {
    double? base,
  }) => <String, dynamic>{
    'key': key,
    'label': key,
    'value': value,
    'weight': weight,
    'contribution': value * weight,
    'base_weight': ?base,
  };

  /// A version 2 row: urgent, raining, one rule fired, reasons with a caveat.
  MatchResult v2({
    int rank = 1,
    String name = 'Ryan Santos',
    double distance = 2.1,
    bool withCaveat = true,
  }) {
    return MatchResult.fromJson(<String, dynamic>{
      'id': 'm$rank',
      'job_id': 'j1',
      'technician_id': 't$rank',
      'rank': rank,
      'status': 'shortlisted',
      'suitability_score': 0.92,
      'acceptance_score': 0.88,
      'final_score': 0.95 - rank * 0.03,
      'score_breakdown': <String, dynamic>{
        'version': 2,
        'stage1': <String, dynamic>{
          'score': 0.92,
          'factors': <dynamic>[factor('specialization', 1, 0.32)],
        },
        'stage2': <String, dynamic>{
          'score': 0.88,
          'factors': <dynamic>[
            factor('proximity', 0.92, 0.27, base: 0.18),
            factor('availability', 1, 0.24, base: 0.18),
          ],
        },
        'recommendation': <String, dynamic>{
          'score': 0.95 - rank * 0.03,
          'factors': <dynamic>[
            factor('suitability', 0.92, 0.45),
            factor('acceptance', 0.88, 0.24, base: 0.2),
            factor('context_fit', 0.9, 0.22, base: 0.15),
          ],
          'signals': <String>['urgent', 'rain', 'on_site', 'technology'],
          'rules': <dynamic>[
            <String, dynamic>{
              'id': 'urgent_visit_in_rain',
              'label': 'Urgent visit in the rain',
              'rationale': 'A short trip matters more in a downpour.',
              'when': <String>['urgent', 'rain', 'on_site'],
              'effects': <dynamic>[
                <String, dynamic>{
                  'stage': 'acceptance',
                  'factor': 'proximity',
                  'multiplier': 1.6,
                },
              ],
            },
          ],
          'reasons': <dynamic>[
            <String, dynamic>{
              'code': 'assessed_device',
              'text': "Passed SUGO's assessment on laptops",
              'kind': 'positive',
            },
            <String, dynamic>{
              'code': 'near',
              'text': '$distance km from your location',
              'kind': 'positive',
            },
            <String, dynamic>{
              'code': 'free_now',
              'text': 'Free to take an urgent job today',
              'kind': 'positive',
            },
            if (withCaveat)
              <String, dynamic>{
                'code': 'over_budget',
                'text': 'Typical rate (about ₱1,650) is above your ₱1,500 budget',
                'kind': 'caveat',
              },
          ],
        },
        'final_score': 0.95 - rank * 0.03,
        'context': <String, dynamic>{
          'distance_km': distance,
          'workload': 0,
          'urgency': 'need_today',
          'service_path': 'home_service',
          'traffic': <String, dynamic>{'label': 'heavy traffic', 'congestion': 0.7},
          'weather': <String, dynamic>{'label': 'moderate rain', 'severity': 0.55},
        },
        'explainability': <String>['covers laptop', '2.1km away'],
        'technician': <String, dynamic>{
          'id': 't$rank',
          'full_name': name,
          'is_verified': true,
          'is_available': true,
          'rating': 4.9,
          'total_jobs': 124,
          'specialization': <String>['laptop'],
        },
      },
    });
  }

  group('score_breakdown version 2', () {
    test('parses rules, signals, reasons and re-weighted factors', () {
      final ScoreBreakdown b = v2().breakdown;
      final RecommendationStage rec = b.recommendation!;

      expect(rec.signals, contains('rain'));
      expect(rec.rules.single.label, 'Urgent visit in the rain');
      expect(rec.rules.single.effects.single.multiplier, 1.6);
      expect(b.reasons.where((RecommendationReason r) => r.isCaveat), hasLength(1));
      expect(b.stage2.factors.first.reweighted, isTrue);
      expect(b.stage1.factors.first.reweighted, isFalse);
    });

    test('the card summary uses the two strongest positive reasons only', () {
      expect(
        v2().breakdown.summary,
        "Passed SUGO's assessment on laptops · 2.1 km from your location",
      );
    });

    test('a version 1 row still explains itself from its old phrases', () {
      final ScoreBreakdown old = ScoreBreakdown.fromJson(<String, dynamic>{
        'version': 1,
        'explainability': <String>['5 similar repairs', '2.1km away'],
      });
      expect(old.recommendation, isNull);
      expect(
        old.reasons.map((RecommendationReason r) => r.text),
        <String>['5 similar repairs', '2.1km away'],
      );
      expect(old.reasons.every((RecommendationReason r) => !r.isCaveat), isTrue);
    });

    test('rank labels are neutral - nobody is called the best', () {
      expect(v2(rank: 1).rankLabel, 'Recommended');
      expect(v2(rank: 2).rankLabel, 'Alternative');
      expect(v2(rank: 3).rankLabel, 'Another match');
    });
  });

  group('context chips', () {
    test('rain, heavy traffic and urgency are emphasised; the rest are not', () {
      final List<ContextChipData> chips = contextChipsFor(<MatchResult>[
        v2(),
        v2(rank: 2, distance: 4.6),
      ], null);

      final Map<String, bool> byLabel = <String, bool>{
        for (final ContextChipData c in chips) c.label: c.emphasised,
      };
      expect(byLabel['Moderate rain'], isTrue);
      expect(byLabel['Heavy traffic'], isTrue);
      expect(byLabel['Urgent'], isTrue);
      expect(byLabel['2.1–4.6 km'], isFalse);
    });

    test('a missing weather reading draws no weather chip, not a guess', () {
      final MatchResult noWeather = MatchResult.fromJson(<String, dynamic>{
        'id': 'm',
        'job_id': 'j',
        'technician_id': 't',
        'rank': 1,
        'status': 'shortlisted',
        'score_breakdown': <String, dynamic>{
          'context': <String, dynamic>{'urgency': 'can_wait'},
        },
      });
      final List<ContextChipData> chips = contextChipsFor(
        <MatchResult>[noWeather],
        null,
      );
      expect(chips.map((ContextChipData c) => c.label), <String>['Can wait']);
    });
  });

  Widget host(Widget child, {double width = 390, double scale = 1}) {
    return MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 1000),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }

  group('recommendation card', () {
    testWidgets('shows the label, both scores, the reason and the Why link', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          MatchScoreCard(
            match: v2(),
            onTap: () {},
            onWhyTap: () {},
            onSelect: () {},
            selectLabel: 'Book Ryan',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recommended for you · 92%'), findsOneWidget);
      expect(find.text('Match'), findsOneWidget);
      expect(find.text('Acceptance'), findsOneWidget);
      expect(find.text('Why this technician?'), findsOneWidget);
      expect(find.text('View profile'), findsOneWidget);
      expect(find.text('Book Ryan'), findsOneWidget);
      expect(find.text('Available today'), findsOneWidget);
      // A likelihood, never a promise.
      expect(find.textContaining('will accept'), findsNothing);

      await expectLater(
        find.byType(MatchScoreCard),
        matchesGoldenFile('../../goldens/recommendation_card.png'),
      );
    });

    testWidgets('fits a 320dp phone at 1.3x text without overflow', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          MatchScoreCard(
            match: v2(name: 'Maria Concepcion Villanueva-Santos'),
            onTap: () {},
            onWhyTap: () {},
            onSelect: () {},
            selectLabel: 'Book Maria',
          ),
          width: 320,
          scale: 1.3,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Why sheet lists reasons, then the caveats under Good to know', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(RecommendationReasonsSheet(match: v2())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Free to take an urgent job today'), findsOneWidget);
    expect(find.text('Good to know'), findsOneWidget);
    expect(find.textContaining('above your ₱1,500 budget'), findsOneWidget);
    expect(find.text('See how the score was worked out'), findsOneWidget);
  });

  testWidgets('Why sheet with no caveats has no Good to know heading', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(RecommendationReasonsSheet(match: v2(withCaveat: false))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Good to know'), findsNothing);
  });

  testWidgets('walkthrough prints every step, the rule and the Top 3', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MatchingWalkthroughScreen(
          matches: <MatchResult>[v2(), v2(rank: 2, name: 'Mark Dela Cruz')],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rule-based weight selection'), findsOneWidget);
    expect(find.text('Urgent visit in the rain'), findsOneWidget);
    expect(find.textContaining('IF urgent AND rain AND on site'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Final Top 3'), 300);
    expect(find.text('Recommended - Ryan Santos'), findsOneWidget);
    expect(find.text('Alternative - Mark Dela Cruz'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
