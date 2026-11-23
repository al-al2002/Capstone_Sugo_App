import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/constants/app_assets.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/rb_cars/widgets/send_request_animation.dart';

/// "Send request" flies the request away to the technician (2026-11-23),
/// while it is really being sent. Regenerate the golden after intentional
/// changes:
///
///   flutter test --update-goldens test/features/rb_cars/send_request_animation_test.dart
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

  Future<void> frames(WidgetTester tester, int count) async {
    for (int i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('flies while sending; the tick only after it went through', (
    WidgetTester tester,
  ) async {
    await pumpHost(tester);
    final Completer<bool> server = Completer<bool>();

    final Future<bool> result = runWithSendAnimation(
      host,
      server.future,
      name: 'Lyra',
    );
    await tester.pump();
    await frames(tester, 3);
    expect(find.text('Sending your request...'), findsOneWidget);
    expect(find.text('Passing it to Lyra now.'), findsOneWidget);

    // Landed, but the server is slow: still sending, no tick.
    await frames(tester, 15);
    expect(find.text('Request sent to Lyra'), findsNothing);

    server.complete(true);
    await tester.pump();
    await frames(tester, 4);
    expect(find.text('Request sent to Lyra'), findsOneWidget);

    await frames(tester, 15);
    expect(find.text('Request sent to Lyra'), findsNothing, reason: 'closed');
    expect(await result, isTrue);
  });

  testWidgets('a refused request closes at once - no tick', (
    WidgetTester tester,
  ) async {
    await pumpHost(tester);
    final Completer<bool> server = Completer<bool>();
    final Future<bool> result = runWithSendAnimation(
      host,
      server.future,
      name: 'Lyra',
    );
    await frames(tester, 3);

    server.complete(false);
    await tester.pump();
    await frames(tester, 5);

    expect(await result, isFalse);
    expect(find.text('Sending your request...'), findsNothing);
    expect(find.text('Request sent to Lyra'), findsNothing);
  });

  testWidgets('a failed request closes and passes the error on', (
    WidgetTester tester,
  ) async {
    await pumpHost(tester);
    final Completer<bool> server = Completer<bool>();
    Object? caught;
    final Future<void> run = runWithSendAnimation(
      host,
      server.future,
      name: 'Lyra',
    ).then<void>((_) {}, onError: (Object e) => caught = e);
    await frames(tester, 3);

    server.completeError(StateError('offline'));
    await run;
    await frames(tester, 5);

    expect(caught, isA<StateError>());
    expect(find.text('Sending your request...'), findsNothing);
  });

  testWidgets('mid-flight, for design review', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(780, 1200);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await pumpHost(tester);
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage(AppAssets.brandEmblem),
        tester.binding.rootElement!,
      );
    });
    final Completer<bool> server = Completer<bool>();
    runWithSendAnimation(host, server.future, name: 'Lyra');
    await tester.pump();
    // Half way up the S-curve, the route behind it.
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../goldens/send_request_animation.png'),
    );

    server.complete(true);
    await frames(tester, 30);
  });
}
