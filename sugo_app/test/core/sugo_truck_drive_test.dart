import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/widgets/sugo_truck_drive.dart';

/// The tracking screens' truck (2026-09-29): it drives only while the trip's
/// position is live, and never under reduced motion.
void main() {
  Widget host(Widget child, {bool reduced = false}) => MaterialApp(
    builder: (BuildContext context, Widget? app) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
      child: app!,
    ),
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );

  testWidgets('drives while the position is live', (WidgetTester tester) async {
    await tester.pumpWidget(host(const SugoTruckDrive()));
    expect(tester.binding.hasScheduledFrame, isTrue);
    expect(find.byIcon(Icons.local_shipping_rounded), findsOneWidget);
    expect(find.bySemanticsLabel('On the way'), findsOneWidget);
    // Stop the loop before the test ends.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('parks when the position has gone quiet', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(const SugoTruckDrive(moving: false)));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('is still under reduced motion', (WidgetTester tester) async {
    await tester.pumpWidget(host(const SugoTruckDrive(), reduced: true));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('shows where the road ends', (WidgetTester tester) async {
    await tester.pumpWidget(
      host(
        const SugoTruckDrive(moving: false, destinationIcon: Icons.home_rounded),
      ),
    );
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
  });
}
