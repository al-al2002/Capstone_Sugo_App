import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/constants/app_assets.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/rb_cars/widgets/technician_matching_loader.dart';

/// Renders the matching screen for design review. Regenerate after intentional
/// changes:
///
///   flutter test --update-goldens
///
/// Three phases side by side, because what the screen claims depends on what
/// it has observed:
///
/// * **saving** - the job is not saved yet: the first step is working, the
///   rest are untouched.
/// * **matching** - saved (first step ticked for real), the highlight walking
///   the server steps, passed ones with an outlined tick only.
/// * **done** - the result is back: every step filled, the bar full.
///
/// `pumpAndSettle` is never used - the emblem animates forever - so frames are
/// reached by pumping a known duration.
///
/// Goldens are platform-specific; regenerate if they fail on another machine.
void main() {
  testWidgets('matching screen in its three phases', (
    WidgetTester tester,
  ) async {
    // 390 x 844 logical per pane: a common phone.
    tester.view.physicalSize = const Size(2340, 1688);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final MatchingSession matching = MatchingSession()
      ..matchingSince = Duration.zero;
    final MatchingSession done = MatchingSession()
      ..matchingSince = Duration.zero
      ..doneAt = Duration.zero
      ..progressAtDone = 0.4;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Row(
            children: <Widget>[
              const Expanded(
                child: TechnicianMatchingLoader(phase: MatchingPhase.saving),
              ),
              Expanded(
                child: TechnicianMatchingLoader(session: matching),
              ),
              Expanded(
                child: TechnicianMatchingLoader(
                  phase: MatchingPhase.done,
                  session: done,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Image decoding is genuinely async, so it has to run outside the
    // fake-async zone or the plane captures blank.
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage(AppAssets.brandEmblem),
        tester.binding.rootElement!,
      );
    });

    // 1.5 s in: the matching pane's highlight is on the third step, and the
    // done pane's cascade and bar have both finished.
    for (int i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../goldens/matching_loader.png'),
    );

    // Leaves no pending tickers for the test framework to complain about.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a short screen scrolls instead of overflowing', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(640, 900);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 450),
            textScaler: TextScaler.linear(1.3),
          ),
          child: const Scaffold(body: TechnicianMatchingLoader()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('done calls onFinished once, after the finish has played', (
    WidgetTester tester,
  ) async {
    int finished = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TechnicianMatchingLoader(
          phase: MatchingPhase.done,
          onFinished: () => finished++,
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 300));
    expect(finished, 0, reason: 'The cascade is still playing.');

    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(finished, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
