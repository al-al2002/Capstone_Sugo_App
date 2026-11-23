import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/services/notification_router.dart';
import 'package:sugo_app/features/client/widgets/declined_alert_dialog.dart';

/// The pop-up a client sees, with SUGO open, when the technician they chose
/// declines (2026-11-23). It replaced a four-second snackbar.
void main() {
  /// Opens the pop-up from a button and records what it returned.
  Future<List<bool>> open(
    WidgetTester tester, {
    String? name,
    String? next,
    Size size = const Size(400, 800),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final List<bool> results = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Builder(
            builder: (BuildContext context) => Scaffold(
              body: TextButton(
                onPressed: () async => results.add(
                  await showDeclinedAlert(context, name: name, next: next),
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
    return results;
  }

  testWidgets('names the technician and offers the shortlist', (
    WidgetTester tester,
  ) async {
    final List<bool> results = await open(
      tester,
      name: 'Ryan',
      next: 'shortlist',
    );

    expect(find.text("Ryan can't take this one"), findsOneWidget);
    expect(find.text('Your shortlist is still there'), findsOneWidget);
    expect(find.textContaining('You do not need to post again'), findsOneWidget);

    await tester.tap(find.text('Choose another technician'));
    await tester.pumpAndSettle();
    expect(results, <bool>[true]);
    expect(find.byType(DeclinedAlertDialog), findsNothing);
  });

  testWidgets('a fresh match that found more says so', (
    WidgetTester tester,
  ) async {
    await open(tester, name: 'Mae', next: 'more');

    expect(find.text('More technicians found'), findsOneWidget);
    expect(find.text('Choose another technician'), findsOneWidget);
  });

  testWidgets('nobody else free: opens the request, and Later closes', (
    WidgetTester tester,
  ) async {
    final List<bool> results = await open(tester, name: 'Jo', next: 'none');

    expect(find.text('Nobody else is free yet'), findsOneWidget);
    expect(find.text('Open my request'), findsOneWidget);
    expect(find.text('Choose another technician'), findsNothing);

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(results, <bool>[false]);
  });

  testWidgets('an older server (no name, no next) still reads as a sentence', (
    WidgetTester tester,
  ) async {
    await open(tester);

    expect(find.text("Your technician can't take this one"), findsOneWidget);
    expect(find.text('Your request is open again'), findsOneWidget);
    expect(find.text('Choose another technician'), findsOneWidget);
  });

  testWidgets('fits a small phone with large text', (
    WidgetTester tester,
  ) async {
    await open(
      tester,
      name: 'Christopher',
      next: 'shortlist',
      size: const Size(320, 568),
      textScale: 1.3,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Choose another technician'), findsOneWidget);
  });

  test('the push data carries name and next to the app', () {
    final NotificationTap tap = NotificationTap.fromData(<String, dynamic>{
      'type': 'declined',
      'job_id': 'job-1',
      'name': 'Ryan',
      'next': 'more',
    });
    expect(tap.type, 'declined');
    expect(tap.jobId, 'job-1');
    expect(tap.name, 'Ryan');
    expect(tap.next, 'more');
    expect(DeclinedNext.fromWire(tap.next), DeclinedNext.more);

    // Missing or unknown wire values fall back, never throw.
    expect(DeclinedNext.fromWire(null), DeclinedNext.unknown);
    expect(DeclinedNext.fromWire('later'), DeclinedNext.unknown);
    expect(NotificationTap.fromData(<String, dynamic>{}).next, isNull);
  });
}
