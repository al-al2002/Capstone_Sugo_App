import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/rb_cars/models/technician.dart';
import 'package:sugo_app/features/rb_cars/widgets/booking_request_sheet.dart';

/// The send-request sheet (2026-11-17): it must settle (its pulse is finite),
/// answer true only on Send, and fit a small phone at large text.
void main() {
  final Technician technician = Technician.fromJson(<String, dynamic>{
    'id': 't1',
    'full_name': 'Maria Santos',
    'rating': 4.8,
    'total_jobs': 32,
  });

  Future<bool?> open(
    WidgetTester tester, {
    bool busy = false,
    double textScale = 1,
  }) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (BuildContext context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(
              body: Builder(
                builder: (BuildContext inner) => TextButton(
                  onPressed: () async {
                    result = await showBookingRequestSheet(
                      context: inner,
                      technician: technician,
                      name: 'Maria',
                      busy: busy,
                      contentBuilder: (_) => const Text('Labor fee ₱600'),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // Settles because the pulse runs three times and stops.
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('names the technician and sends on the main button', (
    WidgetTester tester,
  ) async {
    await open(tester);
    expect(find.text('Send your request to Maria?'), findsOneWidget);
    expect(find.text('4.8 · 32 jobs done'), findsOneWidget);
    expect(find.text('Labor fee ₱600'), findsOneWidget);

    await tester.tap(find.text('Send request'));
    await tester.pumpAndSettle();
    expect(find.text('Send your request to Maria?'), findsNothing);
  });

  testWidgets('a busy technician changes the words, not the flow', (
    WidgetTester tester,
  ) async {
    await open(tester, busy: true);
    expect(find.text('Maria is on another job'), findsOneWidget);
    expect(find.text('Send and wait'), findsOneWidget);
    expect(find.text('Choose someone else'), findsOneWidget);
  });

  testWidgets('a long problem reads as one line of normal text', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 900);
    addTearDown(tester.view.reset);
    bool opened = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (BuildContext inner) => TextButton(
              onPressed: () {
                opened = true;
                showBookingRequestSheet(
                  context: inner,
                  technician: technician,
                  name: 'Maria',
                  busy: false,
                  contentBuilder: (_) =>
                      const Text('Keyboard or trackpad not working'),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
    expect(find.text('Keyboard or trackpad not working'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits a small phone at large text', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
    await open(tester, textScale: 1.3);
    expect(tester.takeException(), isNull);
  });
}
