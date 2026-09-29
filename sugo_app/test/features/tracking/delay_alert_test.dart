import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sugo_app/core/services/local_prefs.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/tracking/models/job_tracking.dart';
import 'package:sugo_app/features/tracking/services/delay_alerts.dart';
import 'package:sugo_app/features/tracking/widgets/delay_alert_dialog.dart';

/// The "running late" pop-up: once per trip, and honest about the cause.
void main() {
  final DateTime promise = DateTime.utc(2026, 9, 29, 10, 30);

  JobTracking trip({
    String jobId = 'job-1',
    TrackingStage stage = TrackingStage.headingToPickup,
    double? delay = 15,
    String? reason = 'traffic',
    DateTime? expected,
  }) => JobTracking(
    id: 'track-1',
    jobId: jobId,
    technicianId: 'tech-1',
    stage: stage,
    latitude: 7.07,
    longitude: 125.61,
    expectedArrivalAt: expected ?? promise,
    delayMinutes: delay,
    delayReason: reason,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LocalPrefs.instance.debugReset();
    DelayAlerts.debugReset();
  });

  group('when it is shown', () {
    test('once per trip, however many updates say it is late', () async {
      expect(await DelayAlerts.claim(trip()), isTrue);
      expect(await DelayAlerts.claim(trip()), isFalse);
      expect(await DelayAlerts.claim(trip(delay: 25)), isFalse);
    });

    test('not again after the app is reopened', () async {
      expect(await DelayAlerts.claim(trip()), isTrue);
      // A fresh launch forgets memory but not the device.
      DelayAlerts.debugReset();
      expect(await DelayAlerts.claim(trip()), isFalse);
    });

    test('a new leg is a new promise, and can be late in its own right', () {
      return expectLater(() async {
        await DelayAlerts.claim(trip());
        return DelayAlerts.claim(
          trip(expected: promise.add(const Duration(hours: 3))),
        );
      }(), completion(isTrue));
    });

    test('not for a trip that is on time, or has no estimate yet', () async {
      expect(await DelayAlerts.claim(trip(delay: 4)), isFalse);
      expect(await DelayAlerts.claim(trip(delay: null)), isFalse);
      expect(
        DelayAlerts.isAlertable(
          JobTracking(
            id: 't',
            jobId: 'job-2',
            technicianId: 'tech-1',
            stage: TrackingStage.headingToPickup,
            delayMinutes: 20,
          ),
        ),
        isFalse,
        reason: 'no promise, so nothing to be late against',
      );
    });

    test('not once the technician has arrived', () async {
      expect(
        await DelayAlerts.claim(trip(stage: TrackingStage.inRepair)),
        isFalse,
      );
    });
  });

  group('what it says', () {
    Future<void> open(
      WidgetTester tester,
      JobTracking tracking, {
      bool offerTracking = false,
      void Function(bool)? onResult,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    final bool result = await maybeShowDelayAlert(
                      context,
                      tracking,
                      offerTracking: offerTracking,
                    );
                    onResult?.call(result);
                  },
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
    }

    testWidgets('the delay and the cause the data supports', (
      WidgetTester tester,
    ) async {
      await open(tester, trip(reason: 'weather'));

      expect(find.text('Running late'), findsOneWidget);
      expect(
        find.text('About 15 minutes behind because of bad weather.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.thunderstorm_rounded), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
      expect(find.text('See live map'), findsNothing);
    });

    testWidgets('no invented excuse when the cause is unknown', (
      WidgetTester tester,
    ) async {
      await open(tester, trip(reason: null));

      expect(
        find.text('About 15 minutes behind the original estimate.'),
        findsOneWidget,
      );
      expect(find.textContaining('traffic'), findsNothing);
      expect(find.textContaining('weather'), findsNothing);
    });

    testWidgets('can open the live map when asked to offer it', (
      WidgetTester tester,
    ) async {
      bool? result;
      await open(
        tester,
        trip(),
        offerTracking: true,
        onResult: (bool value) => result = value,
      );

      expect(find.byIcon(Icons.traffic_rounded), findsOneWidget);
      await tester.tap(find.text('See live map'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
      expect(find.text('Running late'), findsNothing);
    });
  });
}
