import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/widgets/sugo_tab_switcher.dart';

/// Bottom-bar tabs glide in from the side you tapped toward (2026-11-23).
void main() {
  Widget host(int index, {bool reduced = false}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Scaffold(
        body: SugoTabSwitcher(
          index: index,
          child: Center(child: Text('Tab $index')),
        ),
      ),
    ),
  );

  /// The horizontal offset the switcher is sliding [text] by right now.
  double slideOf(WidgetTester tester, String text) {
    final SlideTransition slide = tester.widget<SlideTransition>(
      find
          .ancestor(of: find.text(text), matching: find.byType(SlideTransition))
          .first,
    );
    return slide.position.value.dx;
  }

  testWidgets('going right: the new tab comes in from the right', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(0));
    await tester.pumpWidget(host(2));
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.text('Tab 0'), findsOneWidget, reason: 'still leaving');
    expect(slideOf(tester, 'Tab 2'), greaterThan(0));
    expect(slideOf(tester, 'Tab 0'), lessThan(0), reason: 'leaves leftward');

    await tester.pumpAndSettle();
    expect(find.text('Tab 0'), findsNothing);
    expect(slideOf(tester, 'Tab 2'), 0);
  });

  testWidgets('going left: it comes in from the left', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(3));
    await tester.pumpWidget(host(1));
    await tester.pump(const Duration(milliseconds: 60));

    expect(slideOf(tester, 'Tab 1'), lessThan(0));
    expect(slideOf(tester, 'Tab 3'), greaterThan(0));
    await tester.pumpAndSettle();
    expect(find.text('Tab 3'), findsNothing);
  });

  testWidgets('remove animations: the tab simply changes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(0, reduced: true));
    await tester.pumpWidget(host(1, reduced: true));
    await tester.pump();

    expect(find.text('Tab 0'), findsNothing);
    expect(find.text('Tab 1'), findsOneWidget);
  });
}
