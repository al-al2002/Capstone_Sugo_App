import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/community/screens/ask_question_sheet.dart';

/// The composer has to lay out cleanly on a small screen with the keyboard up.
///
/// That is the only state it is ever used in - it opens from a tap, the field
/// autofocuses, and the keyboard takes roughly half the viewport - so it is the
/// state worth testing.
void main() {
  Future<void> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => AskQuestionSheet.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('lays out without a render error', (WidgetTester tester) async {
    // A small, common phone. The composer is tall, so this is where any
    // unbounded or unlaid-out box shows up first.
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await openSheet(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Ask the community'), findsOneWidget);
    expect(find.text('Post question'), findsOneWidget);
  });

  testWidgets('lays out with the keyboard up', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => AskQuestionSheet.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Roughly what a soft keyboard leaves of a 640dp screen.
    tester.view.viewInsets = FakeViewPadding(bottom: 300 * 3);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('the post button is blocked until both fields are filled', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await openSheet(tester);

    ElevatedButton button() => tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('Post question'),
        matching: find.byType(ElevatedButton),
      ),
    );

    expect(button().onPressed, isNull, reason: 'nothing typed yet');

    await tester.enterText(
      find.byType(TextField).first,
      'What laptop should a student buy?',
    );
    await tester.pump();
    expect(button().onPressed, isNull, reason: 'details still empty');

    await tester.enterText(
      find.byType(TextField).last,
      'Budget is around 30k pesos, mostly for schoolwork.',
    );
    await tester.pump();
    expect(button().onPressed, isNotNull);

    expect(tester.takeException(), isNull);
  });
}
