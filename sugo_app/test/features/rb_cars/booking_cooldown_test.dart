import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/rb_cars/models/job.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';
import 'package:sugo_app/features/rb_cars/models/match_result.dart';
import 'package:sugo_app/features/rb_cars/providers/match_provider.dart';
import 'package:sugo_app/features/rb_cars/services/rb_cars_service.dart';
import 'package:sugo_app/features/rb_cars/widgets/booking_pause.dart';

/// The book-and-cancel cooldown, app side (2026-11-17).
///
/// The rule itself is SQL (`booking_cooldown_until`) and is tested in PGlite
/// by `tool/sql_tests/trust_badge/booking_cooldown.mjs`. This file covers
/// what the app does with the answer: reading it, turning a refused booking
/// into a countdown rather than an error, and never letting the check get in
/// the way of loading the matches.
void main() {
  group('reading the pause from the server', () {
    test('an ISO time becomes a local DateTime', () {
      final DateTime? at = parseBookingPause('2026-11-17T04:02:00+00:00');
      expect(at, DateTime.utc(2026, 11, 17, 4, 2).toLocal());
      expect(at!.isUtc, isFalse);
    });

    test('anything else is "may book now"', () {
      expect(parseBookingPause(null), isNull);
      expect(parseBookingPause('not a time'), isNull);
      expect(parseBookingPause(42), isNull);
    });

    test('"Delete request" reports the pause it started', () {
      final JobResponseOutcome paused =
          JobResponseOutcome.fromJson(<String, dynamic>{
            'job_id': 'j1',
            'deleted': true,
            'booking_paused_until': '2026-11-17T04:02:00Z',
          });
      expect(paused.bookingPausedUntil, isNotNull);

      final JobResponseOutcome plain = JobResponseOutcome.fromJson(
        <String, dynamic>{'job_id': 'j1', 'deleted': true},
      );
      expect(plain.bookingPausedUntil, isNull);
    });

    test('the countdown label', () {
      expect(bookingPauseLabel(const Duration(seconds: 120)), '2:00');
      expect(bookingPauseLabel(const Duration(seconds: 61)), '1:01');
      // Rounded up: "0:00" while time is still left would read as a lie.
      expect(bookingPauseLabel(const Duration(milliseconds: 400)), '0:01');
      expect(bookingPauseLabel(const Duration(seconds: -3)), '0:00');
    });
  });

  group('the match provider', () {
    test(
      'a booking refused by the cooldown becomes a pause, not an error',
      () async {
        final DateTime until = DateTime.now().add(const Duration(seconds: 90));
        final MatchProvider matching = MatchProvider(
          jobId: 'job-1',
          service: _FakeService(refuseWithPauseUntil: until),
        );
        addTearDown(matching.dispose);

        expect(await matching.selectTechnician('match-1'), isFalse);
        expect(matching.bookingPausedUntil, until);
        expect(matching.error, isNull);
      },
    );

    test('loading the matches also learns a running pause', () async {
      final DateTime until = DateTime.now().add(const Duration(seconds: 90));
      final MatchProvider matching = MatchProvider(
        jobId: 'job-1',
        service: _FakeService(pausedUntil: until),
      );
      addTearDown(matching.dispose);

      await matching.load();
      expect(matching.bookingPausedUntil, until);
      expect(matching.error, isNull);
    });

    // The check is an anti-abuse extra. If it fails - an older database, a
    // network blip - the client must still see their matches.
    test('a failing pause check never blocks the matches', () async {
      final MatchProvider matching = MatchProvider(
        jobId: 'job-1',
        service: _FakeService(pauseCheckThrows: true),
      );
      addTearDown(matching.dispose);

      await matching.load();
      expect(matching.bookingPausedUntil, isNull);
      expect(matching.error, isNull);
    });

    test('a pause that has passed reads as "may book now"', () async {
      final MatchProvider matching = MatchProvider(
        jobId: 'job-1',
        service: _FakeService(
          pausedUntil: DateTime.now().subtract(const Duration(seconds: 1)),
        ),
      );
      addTearDown(matching.dispose);

      await matching.load();
      expect(matching.bookingPausedUntil, isNull);
    });

    test(
      'the countdown ending clears the pause and tells the screen',
      () async {
        final MatchProvider matching = MatchProvider(
          jobId: 'job-1',
          service: _FakeService(
            pausedUntil: DateTime.now().add(const Duration(seconds: 90)),
          ),
        );
        addTearDown(matching.dispose);
        await matching.load();

        int notified = 0;
        matching.addListener(() => notified++);
        matching.clearBookingPause();

        expect(matching.bookingPausedUntil, isNull);
        expect(notified, 1);
      },
    );
  });

  group('the banner', () {
    testWidgets('counts down once a second and says when it is over', (
      WidgetTester tester,
    ) async {
      DateTime now = DateTime(2026, 11, 17, 12);
      int done = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: BookingPauseBanner(
              until: now.add(const Duration(seconds: 90)),
              onDone: () => done++,
              clock: () => now,
            ),
          ),
        ),
      );
      expect(find.text('You can book again in 1:30'), findsOneWidget);
      expect(find.textContaining('cancelled 2 bookings'), findsOneWidget);

      now = now.add(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('You can book again in 0:59'), findsOneWidget);
      expect(done, 0);

      now = now.add(const Duration(seconds: 60));
      await tester.pump(const Duration(seconds: 1));
      expect(done, 1);

      // Once only, even if the widget lingers for another tick.
      await tester.pump(const Duration(seconds: 1));
      expect(done, 1);
    });

    testWidgets('fits a small phone at large text', (
      WidgetTester tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: BookingPauseBanner(
                  until: DateTime.now().add(const Duration(minutes: 2)),
                  onDone: () {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox()); // stop the ticker
    });
  });
}

class _FakeService implements RbCarsService {
  _FakeService({
    this.pausedUntil,
    this.refuseWithPauseUntil,
    this.pauseCheckThrows = false,
  });

  final DateTime? pausedUntil;
  final DateTime? refuseWithPauseUntil;
  final bool pauseCheckThrows;

  @override
  Future<DateTime?> bookingPausedUntil() async {
    if (pauseCheckThrows) throw StateError('booking_cooldown_until missing');
    return pausedUntil;
  }

  @override
  Future<JobResponseOutcome> selectTechnician(
    String matchId, {
    DeliveryOption? deliveryOption,
  }) async {
    final DateTime? until = refuseWithPauseUntil;
    if (until != null) {
      throw BookingPausedFailure('Booking is paused', until: until);
    }
    return const JobResponseOutcome();
  }

  @override
  Future<List<MatchResult>> fetchMatches(String jobId) async =>
      const <MatchResult>[];

  @override
  Future<Job?> jobById(String jobId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
