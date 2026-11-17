import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/rb_cars/models/match_result.dart';
import 'package:sugo_app/features/technician/widgets/accept_job_dialog.dart';
import 'package:sugo_app/features/technician/widgets/incoming_offer_card.dart';
import 'package:sugo_app/features/technician/widgets/job_request_details_sheet.dart';

/// The technician's offer (2026-11-17): the labor fee on the dashboard card,
/// and in "View task" the full price plus the weather and traffic the
/// matcher saw - in place of the client's budget range.
void main() {
  MatchResult offer({Map<String, dynamic> job = const <String, dynamic>{}}) =>
      MatchResult.fromJson(<String, dynamic>{
        'id': 'm1',
        'job_id': 'j1',
        'technician_id': 't1',
        'rank': 1,
        'status': 'offered',
        'score_breakdown': <String, dynamic>{
          'context': <String, dynamic>{
            'distance_km': 16.2,
            'traffic': <String, dynamic>{'label': 'Moderate traffic'},
            'weather': <String, dynamic>{
              'label': 'Moderate rain',
              'temp_c': 26.6,
            },
          },
          'job': <String, dynamic>{
            'id': 'j1',
            'device_type': 'laptop',
            'problem_symptom': 'laptop_input_dead',
            'service_path': 'home_service',
            ...job,
          },
        },
      });

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets('the dashboard card shows the labor fee, not "Any budget"', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        IncomingOfferCard(
          match: offer(),
          onAccept: () {},
          onDecline: () {},
          onViewDetails: () {},
          onMessage: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Labor ₱'), findsOneWidget);
    expect(find.text('Any budget'), findsNothing);
  });

  // The user's ask (2026-11-17): Accept on the dashboard card shows the same
  // weather-and-traffic pop-up as "Accept this job" in View task.
  testWidgets('Accept on the card shows the weather and traffic first', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 900);
    addTearDown(tester.view.reset);

    int accepted = 0;
    await tester.pumpWidget(
      host(
        IncomingOfferCard(
          match: offer(),
          onAccept: () => accepted++,
          onDecline: () {},
          onViewDetails: () {},
          onMessage: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();

    expect(find.text('Ready to take this job?'), findsOneWidget);
    expect(find.text('Moderate rain'), findsOneWidget);
    expect(find.text('27°C'), findsOneWidget);
    expect(find.text('Moderate traffic'), findsOneWidget);
    expect(find.textContaining('waterproof bag'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // "Not yet" closes it and accepts nothing.
    await tester.ensureVisible(find.text('Not yet'));
    await tester.tap(find.text('Not yet'));
    await tester.pumpAndSettle();
    expect(find.text('Ready to take this job?'), findsNothing);
    expect(accepted, 0);

    // "Accept job" is what sends it.
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Accept job'));
    await tester.tap(find.text('Accept job'));
    await tester.pumpAndSettle();
    expect(accepted, 1);
  });

  testWidgets('View task shows the price, weather and traffic', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 2400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      host(
        Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showJobRequestDetails(
              context,
              match: offer(),
              onAccept: () {},
              onDecline: () {},
              onMessage: () {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Labor fee'), findsOneWidget);
    // 16.2 km bills as 17 km: ₱50 + ₱15 × 14 = ₱260.
    expect(find.text('Travel fee (16.2 km)'), findsOneWidget);
    expect(find.text('₱260'), findsOneWidget);
    expect(find.text('Estimated total'), findsOneWidget);
    expect(find.text('Any budget'), findsNothing);
    // Weather and traffic are not repeated here - they are in the accept
    // step (2026-11-17).
    expect(find.text('Moderate traffic'), findsNothing);

    // "Accept this job" opens "Ready to take this job?" with the conditions.
    await tester.ensureVisible(find.text('Accept this job'));
    await tester.tap(find.text('Accept this job'));
    await tester.pumpAndSettle();

    expect(find.text('Ready to take this job?'), findsOneWidget);
    expect(find.text('Moderate rain'), findsOneWidget);
    expect(find.text('27°C'), findsOneWidget);
    expect(find.text('Moderate traffic'), findsOneWidget);
    expect(find.textContaining('waterproof bag'), findsOneWidget);
    expect(find.text('Accept job'), findsOneWidget);
    expect(find.text('Not yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the accept step says plainly when a service was down', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 1400);
    addTearDown(tester.view.reset);

    final MatchResult noData = MatchResult.fromJson(<String, dynamic>{
      'id': 'm2',
      'job_id': 'j2',
      'technician_id': 't1',
      'rank': 1,
      'status': 'offered',
      'score_breakdown': <String, dynamic>{
        'context': <String, dynamic>{'distance_km': 3.0},
        'job': <String, dynamic>{
          'id': 'j2',
          'device_type': 'phone',
          'problem_symptom': 'phone_screen_cracked',
          'service_path': 'home_service',
        },
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (BuildContext context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: Scaffold(
              body: Builder(
                builder: (BuildContext inner) => TextButton(
                  onPressed: () => showAcceptJobDialog(inner, match: noData),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Not available'), findsNWidgets(2));
    // No tip is invented without data.
    expect(find.textContaining('waterproof'), findsNothing);
    expect(find.textContaining('Good conditions'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a shop repair offer uses the fee the server saved', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 2400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      host(
        Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showJobRequestDetails(
              context,
              match: offer(
                job: <String, dynamic>{
                  'service_path': 'pickup',
                  'delivery_option': 'delivery',
                  'distance_km': 4.2,
                  'delivery_fee': 80,
                },
              ),
              onAccept: () {},
              onDecline: () {},
              onMessage: () {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Pickup and delivery fee (4.2 km)'), findsOneWidget);
    expect(find.text('₱80'), findsOneWidget);
  });

  // 2026-11-17: two trips, shown as two - the user's example.
  testWidgets('a pickup and delivery offer shows both trips', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showJobRequestDetails(
              context,
              match: offer(
                job: <String, dynamic>{
                  'service_path': 'pickup',
                  'delivery_option': 'delivery',
                  'distance_km': 16.2,
                  'delivery_fee': 520,
                },
              ),
              onAccept: () {},
              onDecline: () {},
              onMessage: () {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Pickup trip (16.2 km)'), findsOneWidget);
    expect(find.text('Delivery trip'), findsOneWidget);
    expect(find.text('₱260'), findsNWidgets(2));
  });
}
