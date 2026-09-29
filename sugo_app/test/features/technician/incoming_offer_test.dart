import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/rb_cars/models/match_result.dart';
import 'package:sugo_app/features/technician/widgets/incoming_offer_card.dart';
import 'package:sugo_app/features/technician/widgets/job_request_details_sheet.dart';

/// What a technician can find out before answering a request.
///
/// The offer card is the only view they have of a job they have not accepted -
/// `jobs_technician_select_assigned` hides the row itself - so everything here
/// comes from the matcher's snapshot in `score_breakdown.job`. These tests pin
/// the two things that were missing: the machine's make, which the server has
/// always sent and the Dart model silently dropped, and a way to ask about the
/// budget instead of declining over it.
void main() {
  Map<String, dynamic> offerRow() => <String, dynamic>{
    'id': 'match-1',
    'job_id': 'job-1',
    'technician_id': 'tech-1',
    'rank': 1,
    'status': 'offered',
    'created_at': '2026-09-23T02:00:00Z',
    'score_breakdown': <String, dynamic>{
      'job': <String, dynamic>{
        'id': 'job-1',
        'device_type': 'laptop',
        'brand': 'Acer',
        'device_detail': 'Aspire 5 A515',
        'problem_symptom': 'no_power',
        'has_physical_damage': true,
        'service_path': 'pickup',
        'urgency': 'need_today',
        'budget_min': 800,
        'budget_max': 2500,
        'description': 'It stopped charging after a brownout.',
      },
      'context': <String, dynamic>{'distance_km': 3.4},
      'explainability': <String>['Works on Acer laptops'],
    },
  };

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    ),
  );

  group('the snapshot', () {
    test('carries the brand and the exact model', () {
      // The regression this guards: `JobSnapshot.fromJson` parsed neither,
      // although `match-technician/scoring/types.ts` has sent both since
      // 20260907000010. A technician deciding whether to take a job could not
      // see what machine it was - and brand is half of what decides whether
      // they have the parts.
      final MatchResult match = MatchResult.fromJson(offerRow());

      expect(match.job!.brand, 'Acer');
      expect(match.job!.deviceDetail, 'Aspire 5 A515');
    });

    test('a job posted without a make is not an error', () {
      final Map<String, dynamic> row = offerRow();
      (row['score_breakdown'] as Map<String, dynamic>)['job'] =
          <String, dynamic>{
            'id': 'job-2',
            'device_type': 'laptop',
            'problem_symptom': 'no_power',
            'has_physical_damage': false,
          };

      final MatchResult match = MatchResult.fromJson(row);

      expect(match.job!.brand, isNull);
      expect(match.job!.deviceDetail, isNull);
    });

    test('the budget reads as pesos, not a currency code', () {
      expect(MatchResult.fromJson(offerRow()).job!.budgetLabel, '₱800 – ₱2,500');
    });
  });

  group('the offer card', () {
    testWidgets('offers reading the task and asking about it', (
      WidgetTester tester,
    ) async {
      int viewed = 0;
      int messaged = 0;

      await tester.pumpWidget(
        host(
          IncomingOfferCard(
            match: MatchResult.fromJson(offerRow()),
            onAccept: () {},
            onDecline: () {},
            onViewDetails: () => viewed++,
            onMessage: () => messaged++,
          ),
        ),
      );

      await tester.tap(find.text('View task'));
      await tester.tap(find.text('Message'));
      await tester.pump();

      expect(viewed, 1);
      // The point of the whole change: this is reachable BEFORE Accept, so a
      // budget that will not cover the part is a question rather than a
      // silent decline.
      expect(messaged, 1);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
    });

    testWidgets('nothing is tappable while a response is in flight', (
      WidgetTester tester,
    ) async {
      int taps = 0;

      await tester.pumpWidget(
        host(
          IncomingOfferCard(
            match: MatchResult.fromJson(offerRow()),
            isBusy: true,
            onAccept: () => taps++,
            onDecline: () => taps++,
            onViewDetails: () => taps++,
            onMessage: () => taps++,
          ),
        ),
      );

      await tester.tap(find.text('View task'), warnIfMissed: false);
      await tester.tap(find.text('Accept'), warnIfMissed: false);
      await tester.pump();

      expect(taps, 0);
    });
  });

  group('the task sheet', () {
    testWidgets('shows the machine, the fault and the budget range', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showJobRequestDetails(
                    context,
                    match: MatchResult.fromJson(offerRow()),
                    onAccept: () {},
                    onDecline: () {},
                    onMessage: () {},
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Everything the request asked for, in the technician's words.
      expect(find.text('Acer'), findsOneWidget);
      expect(find.text('Aspire 5 A515'), findsOneWidget);
      expect(find.text('₱800 – ₱2,500'), findsOneWidget);
      expect(find.textContaining('Laptop'), findsWidgets);
      expect(
        find.text('Yes — the client reports visible damage'),
        findsOneWidget,
      );
      expect(find.text('3.4 km away'), findsOneWidget);

      // And no way to identify the person behind it: the address and the name
      // unlock on acceptance, not before.
      expect(find.textContaining('Client address'), findsNothing);
    });

    testWidgets('a snapshot-less offer says so instead of showing dashes', (
      WidgetTester tester,
    ) async {
      final Map<String, dynamic> row = offerRow();
      row['score_breakdown'] = <String, dynamic>{};

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showJobRequestDetails(
                    context,
                    match: MatchResult.fromJson(row),
                    onAccept: () {},
                    onDecline: () {},
                    onMessage: () {},
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('not available'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
