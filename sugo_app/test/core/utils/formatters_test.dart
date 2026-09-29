import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/utils/formatters.dart';

/// [Fmt] is the only place in the app that turns a `DateTime` or a number into
/// words, so these are the rules every screen inherits.
void main() {
  group('relative', () {
    final DateTime now = DateTime(2026, 9, 23, 14, 0);

    test('the last minute reads as now', () {
      expect(
        Fmt.relative(now.subtract(const Duration(seconds: 20)), now: now),
        'Just now',
      );
    });

    test('minutes, then hours, inside today', () {
      expect(
        Fmt.relative(now.subtract(const Duration(minutes: 12)), now: now),
        '12 min ago',
      );
      expect(
        Fmt.relative(now.subtract(const Duration(hours: 5)), now: now),
        '5 h ago',
      );
    });

    test('yesterday is named, not counted', () {
      expect(
        Fmt.relative(DateTime(2026, 9, 22, 23, 30), now: now),
        'Yesterday',
      );
    });

    test('within the week it is a weekday, past that a date', () {
      expect(Fmt.relative(DateTime(2026, 9, 20, 9), now: now), 'Sun');
      expect(Fmt.relative(DateTime(2026, 8, 30, 9), now: now), 'Aug 30');
    });

    test('another year keeps the year', () {
      expect(Fmt.relative(DateTime(2025, 12, 1, 9), now: now), 'Dec 1, 2025');
    });

    test('a clock skewed into the future does not print a negative age', () {
      expect(
        Fmt.relative(now.add(const Duration(minutes: 3)), now: now),
        'Just now',
      );
    });
  });

  group('peso', () {
    test('groups thousands and drops centavos', () {
      expect(Fmt.peso(2500), '₱2,500');
      expect(Fmt.peso(350), '₱350');
      expect(Fmt.peso(1249.6), '₱1,250');
    });

    test('a range collapses when both ends match', () {
      expect(Fmt.pesoRange(800, 2500), '₱800 – ₱2,500');
      expect(Fmt.pesoRange(500, 500), '₱500');
    });
  });

  group('day headings', () {
    final DateTime now = DateTime(2026, 9, 23, 10);

    test('today and yesterday are words', () {
      expect(Fmt.dayHeading(now, now: now), 'Today');
      expect(Fmt.dayHeading(DateTime(2026, 9, 22, 22), now: now), 'Yesterday');
    });

    test('anything older is a date', () {
      expect(Fmt.dayHeading(DateTime(2026, 9, 14), now: now), 'Mon, Sep 14');
    });
  });

  test('shortDateTime drops the weekday that dateTime keeps', () {
    final DateTime at = DateTime(2026, 12, 9, 8, 30);
    expect(Fmt.dateTime(at), 'Wed, Dec 9 · 8:30 AM');
    expect(Fmt.shortDateTime(at), 'Dec 9 · 8:30 AM');
  });
}
