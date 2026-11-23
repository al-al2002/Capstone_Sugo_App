import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/constants/app_assets.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/rb_cars/widgets/request_send_intro.dart';

/// The "letter to the technicians" opening of Find technician / Save & find
/// technicians (2026-11-23). Regenerate the golden after intentional changes:
///
///   flutter test --update-goldens test/features/rb_cars/request_send_intro_test.dart
void main() {
  Widget host({VoidCallback? onDone, bool reduced = false, Size? size}) {
    Widget intro = RequestSendIntro(
      title: 'Keyboard or trackpad not working',
      detail: 'Laptop / PC · ₱600',
      onDone: onDone,
    );
    if (reduced || size != null) {
      intro = MediaQuery(
        data: MediaQueryData(
          size: size ?? const Size(390, 844),
          disableAnimations: reduced,
          textScaler: TextScaler.linear(size == null ? 1 : 1.3),
        ),
        child: intro,
      );
    }
    return MaterialApp(theme: AppTheme.light, home: Scaffold(body: intro));
  }

  testWidgets('plays once, says what is happening, then hands over', (
    WidgetTester tester,
  ) async {
    int done = 0;
    await tester.pumpWidget(host(onDone: () => done++));

    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Packing up your request'), findsOneWidget);
    expect(find.text('Keyboard or trackpad not working'), findsOneWidget);
    expect(
      find.text('Nobody is booked yet - you choose from your top 3.'),
      findsOneWidget,
    );

    // Frame by frame through the hops.
    for (int i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Passing it to technicians near you'), findsOneWidget);
    expect(done, 0);

    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(done, 1, reason: 'onDone once the 2.8 s have played');

    await tester.pump(const Duration(seconds: 2));
    expect(done, 1, reason: 'and never again');
  });

  testWidgets('saving changes says so', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RequestSendIntro(title: 'Battery not charging', editing: true),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Packing up your changes'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('remove animations: skipped, handed over at once', (
    WidgetTester tester,
  ) async {
    int done = 0;
    await tester.pumpWidget(host(onDone: () => done++, reduced: true));
    await tester.pump();
    expect(done, 1);
  });

  testWidgets('fits a small phone at large text', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(640, 1000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(size: const Size(320, 500)));
    for (int i = 0; i < 28; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('mid-hop, for design review', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage(AppAssets.brandEmblem),
        tester.binding.rootElement!,
      );
    });
    // 2.0 s: sealed, two technicians reached, the dashed route behind it.
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../goldens/request_send_intro.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
