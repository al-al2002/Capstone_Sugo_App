import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/core/widgets/sugo_fold_card.dart';

/// A section that folds to one line and opens on a tap (2026-11-17): the
/// booking page's secondary sections, kept but out of the way.
void main() {
  Widget host({bool reduced = false, double scale = 1}) => MaterialApp(
    theme: AppTheme.light,
    home: Builder(
      builder: (BuildContext context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduced,
          textScaler: TextScaler.linear(scale),
        ),
        child: const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: SugoFoldCard(
              icon: Icons.payments_outlined,
              title: 'Price',
              summary: 'Estimated total ₱1,020',
              child: Text('Paid directly to your technician.'),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('folded: the title and the one line, not the content', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host());
    expect(find.text('Price'), findsOneWidget);
    expect(find.text('Estimated total ₱1,020'), findsOneWidget);
    expect(find.text('Paid directly to your technician.'), findsNothing);
  });

  testWidgets('a tap opens it, another folds it again', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('Price'));
    await tester.pumpAndSettle();
    expect(find.text('Paid directly to your technician.'), findsOneWidget);
    // The summary stays, so the number is still there when it is open.
    expect(find.text('Estimated total ₱1,020'), findsOneWidget);

    await tester.tap(find.text('Price'));
    await tester.pumpAndSettle();
    expect(find.text('Paid directly to your technician.'), findsNothing);
  });

  testWidgets('reduced motion opens it at once, without a layout error', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(reduced: true));
    await tester.tap(find.text('Price'));
    await tester.pump();
    expect(find.text('Paid directly to your technician.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the header is a 48 dp target, and fits large text', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(scale: 1.5));
    final Size size = tester.getSize(
      find.ancestor(of: find.text('Price'), matching: find.byType(InkWell)),
    );
    expect(size.height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });
}
