import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/rb_cars/models/job.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';
import 'package:sugo_app/features/rb_cars/models/job_price.dart';
import 'package:sugo_app/features/rb_cars/models/match_result.dart';
import 'package:sugo_app/features/rb_cars/models/preference_match.dart';
import 'package:sugo_app/features/rb_cars/models/score_breakdown.dart';
import 'package:sugo_app/features/rb_cars/models/technician_preferences.dart';
import 'package:sugo_app/features/rb_cars/widgets/urgent_countdown.dart';
import 'package:sugo_app/features/technician/widgets/incoming_offer_card.dart';
import 'package:sugo_app/features/technician/widgets/urgent_offer_alert.dart';

/// Urgent jobs and the preference bars (2026-11-17).
void main() {
  Job job({
    Urgency urgency = Urgency.needToday,
    String symptom = 'laptop_overheating',
  }) => Job(
    id: 'j',
    clientId: 'c',
    deviceType: symptom.startsWith('cctv')
        ? DeviceType.network
        : DeviceType.laptop,
    problemSymptom: symptom,
    hasPhysicalDamage: false,
    status: JobStatus.matched,
    servicePath: ServicePath.homeService,
    urgency: urgency,
  );

  group('the urgent fee', () {
    test('20% of the labor, on top of labor and travel', () {
      // ₱600 labor, 4 km = ₱65 travel: 600 + 120 + 65.
      final JobPrice price = JobPrice.forJob(job(), homeDistanceKm: 4);
      expect(price.urgentFee, 120);
      expect(price.urgentFeeText, '₱120');
      expect(price.total, '₱785');
      expect(price.headline, '₱785');
    });

    test('no urgent fee on a flexible job', () {
      final JobPrice price = JobPrice.forJob(
        job(urgency: Urgency.canWait),
        homeDistanceKm: 4,
      );
      expect(price.hasUrgentFee, isFalse);
      expect(price.total, '₱665');
    });

    test('a per-camera labor fee says +20% instead of inventing a number', () {
      final JobPrice price = JobPrice.forJob(job(symptom: 'cctv_new_install'));
      expect(price.urgentFee, isNull);
      expect(price.urgentFeeText, '+20% of labor');
    });
  });

  group('the preference bars', () {
    const TechnicianPreferences prefs = TechnicianPreferences(
      maxDistance: MaxDistance.km5,
      minRating: MinRating.r45,
      minTrust: TrustBadge.skillVerified,
    );

    test('a technician who meets everything is full across', () {
      final List<PreferenceBar> bars = preferenceBars(
        prefs,
        distanceKm: 3.2,
        rating: 4.6,
        trustForJob: TrustBadge.skillVerified,
      );
      expect(bars.map((PreferenceBar b) => b.label), <String>[
        'Location',
        'Rating',
        'Trust badge',
      ]);
      expect(
        bars.every((PreferenceBar b) => b.met && b.percent == 100),
        isTrue,
      );
    });

    test('beyond the distance limit: the limit as a share of the distance', () {
      final PreferenceBar location = preferenceBars(
        prefs,
        distanceKm: 12,
      ).first;
      expect(location.met, isFalse);
      expect(location.percent, 42); // 5 / 12
      expect(location.detail, '12.0 km · beyond 5 km');
    });

    test('a lower trust rung fills part of the bar', () {
      final PreferenceBar trust = preferenceBars(
        prefs,
        distanceKm: 3,
        rating: 4.6,
        trustForJob: TrustBadge.idVerified,
      ).last;
      expect(trust.met, isFalse);
      expect(trust.percent, 50); // rung 1 of the 2 wanted
    });

    test('Skills shows the engine\'s own skill score', () {
      final PreferenceBar skills = preferenceBars(
        const TechnicianPreferences(
          specialization: PreferredSpecialization.computer,
        ),
        skillPercent: 72,
      ).single;
      expect(skills.label, 'Skills');
      expect(skills.percent, 72);
    });
  });

  group('the distance fallback', () {
    test('is read from the match and says both distances', () {
      final ScoreBreakdown b = ScoreBreakdown.fromJson(<String, dynamic>{
        'preference_fallback': <String, dynamic>{
          'wanted_km': 5,
          'nearest_km': 12.4,
        },
      });
      expect(
        b.preferenceFallback?.message,
        'No technician within 5 km - the nearest is 12.4 km away.',
      );
    });

    test('an ordinary match has none', () {
      expect(
        ScoreBreakdown.fromJson(<String, dynamic>{}).preferenceFallback,
        isNull,
      );
    });
  });

  MatchResult offer({
    String urgency = 'need_today',
    DateTime? offeredAt,
    double distanceKm = 4.0,
    bool damaged = false,
  }) => MatchResult.fromJson(<String, dynamic>{
    'id': 'm1',
    'job_id': 'j1',
    'technician_id': 't1',
    'rank': 1,
    'status': 'offered',
    'offered_at': (offeredAt ?? DateTime.now()).toUtc().toIso8601String(),
    'score_breakdown': <String, dynamic>{
      'context': <String, dynamic>{'distance_km': distanceKm},
      'job': <String, dynamic>{
        'id': 'j1',
        'device_type': 'laptop',
        'problem_symptom': 'laptop_overheating',
        'service_path': 'home_service',
        'urgency': urgency,
        'has_physical_damage': damaged,
      },
    },
  });

  group('the five-minute window', () {
    test('an urgent offer runs out five minutes after it was sent', () {
      final DateTime sent = DateTime(2026, 11, 17, 9);
      expect(
        offer(offeredAt: sent).urgentDeadline,
        sent.add(const Duration(minutes: 5)),
      );
    });

    test('a flexible offer has no clock', () {
      expect(offer(urgency: 'can_wait').urgentDeadline, isNull);
    });
  });

  testWidgets('the countdown ticks down and says when it is passing on', (
    WidgetTester tester,
  ) async {
    DateTime now = DateTime(2026, 11, 17, 9);
    int expired = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UrgentCountdown(
            deadline: now.add(const Duration(seconds: 65)),
            clock: () => now,
            onExpired: () => expired++,
          ),
        ),
      ),
    );
    expect(find.text('1:05'), findsOneWidget);

    now = now.add(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0:59'), findsOneWidget);

    now = now.add(const Duration(seconds: 60));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Passing on…'), findsOneWidget);
    expect(expired, 1);
  });

  testWidgets('an urgent request card says so, with its price and clock', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: IncomingOfferCard(
              match: offer(),
              onAccept: () {},
              onDecline: () {},
              onViewDetails: () {},
              onMessage: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('URGENT'), findsOneWidget);
    expect(find.byType(UrgentCountdown), findsOneWidget);
    expect(find.textContaining('Accept within 5 minutes'), findsOneWidget);
    expect(find.textContaining('Labor ₱600 + urgent ₱120'), findsOneWidget);

    // Unmount so the clock's timer stops.
    await tester.pumpWidget(const SizedBox());
  });

  group('the accept pop-up on an urgent card', () {
    Future<int Function()> openFrom(
      WidgetTester tester,
      MatchResult match,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 900);
      addTearDown(tester.view.reset);

      int accepted = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: IncomingOfferCard(
                match: match,
                onAccept: () => accepted++,
                onDecline: () {},
                onViewDetails: () {},
                onMessage: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Accept'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      return () => accepted;
    }

    // The dialog covers the card's clock, so it carries its own.
    testWidgets('keeps the five-minute clock in view', (
      WidgetTester tester,
    ) async {
      final int Function() accepted = await openFrom(tester, offer());

      expect(find.text('Ready to take this job?'), findsOneWidget);
      // One clock on the card, one in the dialog.
      expect(find.byType(UrgentCountdown), findsNWidgets(2));
      expect(accepted(), 0);

      await tester.pumpWidget(const SizedBox());
    });

    // Past the deadline the server's sweep has passed the offer on, so an
    // accept could only fail: the dialog closes itself instead.
    testWidgets('closes itself, accepting nothing, when time is up', (
      WidgetTester tester,
    ) async {
      final int Function() accepted = await openFrom(
        tester,
        offer(offeredAt: DateTime.now().subtract(const Duration(minutes: 6))),
      );

      expect(find.text('Ready to take this job?'), findsNothing);
      expect(accepted(), 0);

      await tester.pumpWidget(const SizedBox());
    });
  });

  // Regression (2026-11-17): on a narrow phone the "Top pick" chip squeezed
  // the details column, and "Labor ₱500 + urgent ₱100" overflowed by 21 px.
  // The label now wraps, and the whole price must still be readable.
  testWidgets('an urgent request card fits a narrow phone without overflow', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(300, 1400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: IncomingOfferCard(
              match: offer(distanceKm: 16.2, damaged: true),
              onAccept: () {},
              onDecline: () {},
              onViewDetails: () {},
              onMessage: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Top pick'), findsOneWidget);
    expect(find.text('Labor ₱600 + urgent ₱120'), findsOneWidget);
    expect(
      find.text('Client reported visible physical damage'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the full-screen alert: price, clock, and an answer', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 900);
    addTearDown(tester.view.reset);

    final List<UrgentOfferChoice?> chosen = <UrgentOfferChoice?>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  chosen.add(await showUrgentOfferAlert(context, offer())),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('URGENT JOB REQUEST'), findsOneWidget);
    expect(find.text('₱785'), findsOneWidget);
    expect(find.byType(UrgentCountdown), findsOneWidget);

    // "Accept job" opens the weather-and-traffic dialog first (2026-11-17),
    // so a reflex tap no longer accepts on its own.
    await tester.tap(find.text('Accept job'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Ready to take this job?'), findsOneWidget);
    expect(chosen, isEmpty);

    // "Not yet" goes back to the alert, still waiting for an answer.
    await tester.ensureVisible(find.text('Not yet'));
    await tester.tap(find.text('Not yet'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Ready to take this job?'), findsNothing);
    expect(find.text('URGENT JOB REQUEST'), findsOneWidget);
    expect(chosen, isEmpty);

    // Accept, then "Accept job" in the dialog: that is the answer.
    await tester.tap(find.text('Accept job'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.ensureVisible(find.text('Accept job').last);
    await tester.tap(find.text('Accept job').last);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(chosen.single, UrgentOfferChoice.accept);
  });

  // The trap fixed with the dialog: the alert used to close itself with
  // `maybePop()`, which would have closed only the dialog on top of it and
  // left the alert up after the request had gone. Both must close.
  //
  // The clocks read the real time, so this waits a few real seconds.
  testWidgets('time running out with the dialog open closes both', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 900);
    addTearDown(tester.view.reset);

    final List<UrgentOfferChoice?> chosen = <UrgentOfferChoice?>[];
    // Four seconds left on the five minutes.
    final MatchResult nearlyGone = offer(
      offeredAt: DateTime.now().subtract(
        MatchResult.urgentWindow - const Duration(seconds: 4),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  chosen.add(await showUrgentOfferAlert(context, nearlyGone)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    // Each clock ticks once a second from when it appeared. The trap needs
    // the ALERT's clock to notice the deadline first, so the phases are set
    // on purpose: the alert's clock ticks at 1.0 s, 2.0 s...; the dialog's,
    // opened at 0.9 s, ticks at 1.9 s, 2.9 s...
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.tap(find.text('Accept job'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1050)); // now 1.95 s
    expect(find.text('Ready to take this job?'), findsOneWidget);

    // Let the real deadline pass. The next tick is the alert's (2.0 s),
    // a whole 0.9 s before the dialog's.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 4500)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Ready to take this job?'), findsNothing);
    expect(find.text('URGENT JOB REQUEST'), findsNothing);
    expect(chosen, <UrgentOfferChoice?>[null]);
  });
}
