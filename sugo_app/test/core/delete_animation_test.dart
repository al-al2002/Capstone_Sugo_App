import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/core/widgets/sugo_delete_animation.dart';

/// The bin animation that plays while a request is deleted.
void main() {
  late BuildContext host;

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (BuildContext context) {
            host = context;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );
  }

  testWidgets('plays while the delete runs, ticks, then closes', (
    WidgetTester tester,
  ) async {
    await pumpHost(tester);
    final Completer<String> server = Completer<String>();

    final Future<String> result = runWithDeleteAnimation(host, server.future);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Deleting...'), findsOneWidget);

    // The server is slow: the drop has finished, but no tick until it answers.
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('Request deleted'), findsNothing);

    server.complete('ok');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Request deleted'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.text('Request deleted'), findsNothing, reason: 'closed');
    expect(await result, 'ok');
  });

  testWidgets('a failed delete closes at once and rethrows - no tick', (
    WidgetTester tester,
  ) async {
    await pumpHost(tester);
    final Completer<void> server = Completer<void>();

    Object? caught;
    final Future<void> run = runWithDeleteAnimation(
      host,
      server.future,
    ).catchError((Object e) => caught = e);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    server.completeError(StateError('refused'));
    await run;
    await tester.pumpAndSettle();

    expect(caught, isA<StateError>());
    expect(find.text('Deleting...'), findsNothing);
    expect(find.text('Request deleted'), findsNothing);
  });

  testWidgets('the bin mid-drop, for design review', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(600, 600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await pumpHost(tester);
    final Completer<void> server = Completer<void>();
    runWithDeleteAnimation(host, server.future);
    await tester.pump();
    // Lid up, the request halfway in.
    await tester.pump(const Duration(milliseconds: 420));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/delete_animation.png'),
    );

    // Frame by frame: the drop has to finish on frames before the tick's
    // hold timer even starts, so one long pump would leave that timer behind.
    server.complete();
    for (int i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  });
}
