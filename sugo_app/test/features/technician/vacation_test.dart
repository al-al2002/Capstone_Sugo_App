import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/rb_cars/models/match_result.dart';
import 'package:sugo_app/features/rb_cars/models/technician.dart';
import 'package:sugo_app/features/rb_cars/widgets/match_score_card.dart';
import 'package:sugo_app/features/rb_cars/widgets/technician_card.dart';
import 'package:sugo_app/features/technician/models/time_off.dart';
import 'package:sugo_app/features/technician/services/time_off_service.dart';
import 'package:sugo_app/features/technician/widgets/vacation_card.dart';
import 'package:sugo_app/features/technician/widgets/availability_hero_card.dart';

/// Vacation: the technician's own card, the model behind it, and how a
/// client's cards show someone who is away.
///
/// The rule under test on the client side is "shown, but not bookable": the
/// technician still appears, labelled, and the Book button is gone. Whether a
/// booking is actually refused is the server's job (`job-response`), checked
/// separately against the live database.
void main() {
  final DateTime today = TimeOff.dayOf(DateTime.now());
  String wire(DateTime d) => TimeOff.toWire(d);

  group('TimeOff', () {
    test('counts both ends and says when they are back', () {
      final TimeOff period = TimeOff.fromJson(<String, dynamic>{
        'id': 'a',
        'starts_on': '2026-09-22',
        'ends_on': '2026-09-27',
        'note': '  Family trip  ',
      });

      expect(period.days, 6);
      expect(period.backOn, DateTime(2026, 9, 28));
      expect(period.note, 'Family trip');
      expect(period.rangeLabel, 'Sep 22 – 27');
    });

    test('a blank note is no note', () {
      final TimeOff period = TimeOff.fromJson(<String, dynamic>{
        'id': 'a',
        'starts_on': '2026-09-22',
        'ends_on': '2026-09-22',
        'note': '   ',
      });
      expect(period.note, isNull);
      expect(period.days, 1);
      expect(period.rangeLabel, 'Sep 22');
    });

    test('labels a range across a month', () {
      expect(
        TimeOff.formatRange(DateTime(2026, 9, 29), DateTime(2026, 10, 3)),
        'Sep 29 – Oct 3',
      );
    });

    test('current means today is inside, by calendar day not by hour', () {
      final TimeOff period = TimeOff(
        id: 'a',
        startsOn: DateTime(2026, 9, 22),
        endsOn: DateTime(2026, 9, 27),
      );
      // Late on the last day still counts: dates are whole days.
      expect(period.isCurrent(DateTime(2026, 9, 27, 23, 59)), isTrue);
      expect(period.isCurrent(DateTime(2026, 9, 28, 0, 1)), isFalse);
      expect(period.isUpcoming(DateTime(2026, 9, 21, 23)), isTrue);
    });

    test('wire format round-trips', () {
      expect(TimeOff.toWire(DateTime(2026, 1, 5)), '2026-01-05');
      expect(TimeOff.parseDay('2026-01-05'), DateTime(2026, 1, 5));
    });
  });

  group('Technician.awayUntil', () {
    test('parsed from the match snapshot and labelled', () {
      final DateTime until = today.add(const Duration(days: 5));
      final Technician t = Technician.fromJson(<String, dynamic>{
        'id': 't1',
        'away_until': wire(until),
      });

      expect(t.isAway, isTrue);
      expect(
        t.awayLabel,
        'On vacation until ${DateFormat('MMM d').format(until)}',
      );
    });

    test('a vacation that has ended is not shown, even on an old snapshot', () {
      final Technician t = Technician.fromJson(<String, dynamic>{
        'id': 't1',
        'away_until': wire(today.subtract(const Duration(days: 1))),
      });
      expect(t.isAway, isFalse);
      expect(t.awayLabel, isNull);
    });

    test('the last day itself still counts as away', () {
      final Technician t = Technician.fromJson(<String, dynamic>{
        'id': 't1',
        'away_until': wire(today),
      });
      expect(t.isAway, isTrue);
    });

    test('copyWith sets the vacation without losing the rest', () {
      final Technician away = const Technician(
        id: 't1',
        fullName: 'Lance',
        totalJobs: 21,
      ).copyWith(awayUntil: today);
      expect(away.isAway, isTrue);
      expect(away.fullName, 'Lance');
      expect(away.totalJobs, 21);
    });
  });

  group('client cards', () {
    MatchResult match({String? awayUntil}) => MatchResult.fromJson(
      <String, dynamic>{
        'id': 'm1',
        'job_id': 'job-1',
        'technician_id': 't1',
        'rank': 1,
        'status': 'shortlisted',
        'final_score': 0.82,
        'score_breakdown': <String, dynamic>{
          'technician': <String, dynamic>{
            'id': 't1',
            'full_name': 'Lance Dela Cruz',
            'is_verified': true,
            'is_available': true,
            'rating': 4.6,
            'total_jobs': 21,
            'away_until': awayUntil,
          },
        },
      },
    );

    Widget host(Widget child, {double width = 360, double scale = 1}) {
      return MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 900),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: Center(child: SizedBox(width: width, child: child)),
          ),
        ),
      );
    }

    testWidgets('a technician on vacation is shown but has no Book button', (
      WidgetTester tester,
    ) async {
      final String until = wire(today.add(const Duration(days: 3)));
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: MatchScoreCard(
              match: match(awayUntil: until),
              onSelect: () {},
              selectLabel: 'Book Lance',
            ),
          ),
          width: 320,
          scale: 1.3,
        ),
      );

      expect(find.text('On vacation'), findsOneWidget);
      expect(find.textContaining('cannot be booked'), findsOneWidget);
      expect(find.text('Book Lance'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a working technician keeps the Book button', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: MatchScoreCard(
              match: match(),
              onSelect: () {},
              selectLabel: 'Book Lance',
            ),
          ),
        ),
      );

      expect(find.text('Book Lance'), findsOneWidget);
      expect(find.text('On vacation'), findsNothing);
    });

    testWidgets('the dashboard card fits the vacation line in its fixed height', (
      WidgetTester tester,
    ) async {
      final Technician away = Technician(
        id: 't1',
        fullName: 'Lance Dela Cruz',
        rating: 4.6,
        reviewCount: 21,
        totalJobs: 21,
        distanceKm: 3.4,
        awayUntil: today.add(const Duration(days: 3)),
      );

      await tester.pumpWidget(
        host(
          // The recommended row's height (`_cardHeight`), raised from 172 to
          // 182 by the 2026-09 type scale.
          SizedBox(height: 182, child: TechnicianCard.compact(technician: away)),
          width: 200,
        ),
      );

      expect(find.textContaining('On vacation until'), findsOneWidget);
      // It takes the distance line's place rather than adding a third line.
      expect(find.text('3.4 km away'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('availability hero card (replaced the online/offline toggle)', () {
    Widget host(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 900),
          textScaler: TextScaler.linear(1.3),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );

    testWidgets('working: "Taking jobs" and one way to set a vacation', (
      WidgetTester tester,
    ) async {
      int set = 0;
      await tester.pumpWidget(
        host(
          AvailabilityHeroCard(
            vacation: null,
            onSetVacation: () => set++,
            onEndVacation: () {},
            onEditDates: () {},
          ),
        ),
      );

      expect(find.text('Taking jobs'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('End vacation'), findsNothing);

      await tester.tap(find.text('Set vacation'));
      expect(set, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('away: days left counting today, the day back, two actions', (
      WidgetTester tester,
    ) async {
      int ended = 0;
      int edited = 0;
      await tester.pumpWidget(
        host(
          AvailabilityHeroCard(
            vacation: TimeOff(
              id: 'v',
              startsOn: DateTime(2026, 9, 20),
              endsOn: DateTime(2026, 9, 22),
            ),
            clock: () => DateTime(2026, 9, 22, 15),
            onSetVacation: () {},
            onEndVacation: () => ended++,
            onEditDates: () => edited++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ends today: "1 day left", back tomorrow.
      expect(find.text('1 day left · back Wed, Sep 23'), findsOneWidget);
      expect(find.text('On vacation'), findsOneWidget);

      await tester.tap(find.text('End vacation'));
      await tester.tap(find.text('Edit dates'));
      expect(ended, 1);
      expect(edited, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('VacationCard', () {
    final DateTime now = DateTime(2026, 9, 22, 10);

    Widget host(_FakeTimeOff service, {double width = 360, double scale = 1}) {
      return MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 900),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: VacationCard(service: service, clock: () => now),
            ),
          ),
        ),
      );
    }

    testWidgets('working, with nothing planned', (WidgetTester tester) async {
      await tester.pumpWidget(host(_FakeTimeOff(<TimeOff>[])));
      await tester.pumpAndSettle();

      expect(find.text('You are taking jobs'), findsOneWidget);
      expect(find.text('Add vacation'), findsOneWidget);
      expect(find.text('Planned'), findsNothing);
    });

    testWidgets('away now, with one more planned, fits a small phone', (
      WidgetTester tester,
    ) async {
      final _FakeTimeOff service = _FakeTimeOff(<TimeOff>[
        TimeOff(
          id: 'now',
          startsOn: DateTime(2026, 9, 20),
          endsOn: DateTime(2026, 9, 27),
          note: 'Family trip to Bohol with the kids',
        ),
        TimeOff(
          id: 'later',
          startsOn: DateTime(2026, 10, 29),
          endsOn: DateTime(2026, 11, 2),
        ),
      ]);

      await tester.pumpWidget(host(service, width: 320, scale: 1.3));
      await tester.pumpAndSettle();

      expect(find.text('On vacation until Sun, Sep 27'), findsOneWidget);
      expect(find.text('End vacation now'), findsOneWidget);
      expect(find.text('Planned'), findsOneWidget);
      expect(find.text('Oct 29 – Nov 2 · 5 days'), findsOneWidget);
      expect(find.text('Plan another vacation'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ending a vacation asks first, then calls the service', (
      WidgetTester tester,
    ) async {
      final _FakeTimeOff service = _FakeTimeOff(<TimeOff>[
        TimeOff(
          id: 'now',
          startsOn: DateTime(2026, 9, 20),
          endsOn: DateTime(2026, 9, 27),
        ),
      ]);

      await tester.pumpWidget(host(service));
      await tester.pumpAndSettle();

      await tester.tap(find.text('End vacation now'));
      await tester.pumpAndSettle();
      expect(find.text('End your vacation?'), findsOneWidget);

      await tester.tap(find.text('End it now'));
      await tester.pumpAndSettle();

      expect(service.ended, <String>['now']);
      expect(find.text('You are taking jobs'), findsOneWidget);
    });
  });
}

/// An in-memory calendar. `endNow` and `cancel` remove the period, which is
/// what the technician sees either way.
class _FakeTimeOff implements TimeOffService {
  _FakeTimeOff(List<TimeOff> periods) : _periods = List<TimeOff>.of(periods);

  final List<TimeOff> _periods;
  final List<String> ended = <String>[];

  @override
  Future<List<TimeOff>> upcoming() async => List<TimeOff>.of(_periods);

  @override
  Future<TimeOff> add({
    required DateTime startsOn,
    required DateTime endsOn,
    String? note,
  }) async {
    final TimeOff period = TimeOff(
      id: 'new-${_periods.length}',
      startsOn: startsOn,
      endsOn: endsOn,
      note: note,
    );
    _periods.add(period);
    return period;
  }

  @override
  Future<void> endNow(TimeOff period) async {
    ended.add(period.id);
    _periods.removeWhere((TimeOff p) => p.id == period.id);
  }

  @override
  Future<void> cancel(TimeOff period) async {
    _periods.removeWhere((TimeOff p) => p.id == period.id);
  }

  @override
  Future<void> changeEnd(TimeOff period, DateTime endsOn) async {
    final int i = _periods.indexWhere((TimeOff p) => p.id == period.id);
    if (i >= 0) {
      _periods[i] = TimeOff(
        id: period.id,
        startsOn: period.startsOn,
        endsOn: endsOn,
        note: period.note,
      );
    }
  }
}
