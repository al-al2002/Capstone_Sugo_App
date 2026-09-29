import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/community/screens/community_feed_view.dart';

/// The Community tab, on a small screen, in the states it actually reaches.
///
/// There is no Supabase in a widget test, so `feed()` fails and the view falls
/// to its error state. That is a real state the app reaches - an offline phone
/// hits exactly this - and it is the one most likely to be laid out wrongly,
/// because it is the one nobody looks at while building.
void main() {
  Future<void> pumpFeed(WidgetTester tester, {required bool isClient}) async {
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SafeArea(child: CommunityFeedView(isClient: isClient)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('client feed lays out without a render error', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester, isClient: true);
    expect(tester.takeException(), isNull);
    expect(find.text('Community'), findsOneWidget);
  });

  testWidgets('technician feed lays out without a render error', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester, isClient: false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('only the client is offered a way to ask', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester, isClient: true);
    expect(find.text('Ask'), findsOneWidget);

    await pumpFeed(tester, isClient: false);
    expect(
      find.text('Ask'),
      findsNothing,
      reason: 'a technician cannot post a question, so must not be offered one',
    );
  });

  testWidgets('opening the composer over the feed lays out cleanly', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester, isClient: true);

    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();

    expect(find.text('Ask the community'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
