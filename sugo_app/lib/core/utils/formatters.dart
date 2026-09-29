import 'package:intl/intl.dart';

/// Dates, times and money, written the same way on every screen.
///
/// Before this each screen formatted its own - `9/12/2026 · 2:30 PM` on the
/// booking detail, `2:30 PM, 12 Sep` on the list, `h:mm a` in chat - so one
/// booking read three different ways depending on where you looked. These are
/// the only formats the redesign uses.
class Fmt {
  const Fmt._();

  /// "Just now", "5 min ago", "3 h ago", "Yesterday", "Mon", "Sep 12".
  ///
  /// Relative for the last week because that is how people think about recent
  /// events ("the message from an hour ago"); a calendar date after that,
  /// because "23 days ago" makes the reader do arithmetic.
  static String relative(DateTime at, {DateTime? now}) {
    final DateTime ref = now ?? DateTime.now();
    final Duration gap = ref.difference(at);
    if (gap.isNegative || gap.inSeconds < 45) return 'Just now';
    if (gap.inMinutes < 60) return '${gap.inMinutes} min ago';
    final DateTime today = DateTime(ref.year, ref.month, ref.day);
    final DateTime day = DateTime(at.year, at.month, at.day);
    final int days = today.difference(day).inDays;
    if (days == 0) return '${gap.inHours} h ago';
    if (days == 1) return 'Yesterday';
    if (days < 7) return DateFormat('EEE').format(at);
    return at.year == ref.year
        ? DateFormat('MMM d').format(at)
        : DateFormat('MMM d, yyyy').format(at);
  }

  /// "Sep 22".
  static String date(DateTime at) => DateFormat('MMM d').format(at);

  /// "Mon, Sep 22".
  static String dayDate(DateTime at) => DateFormat('EEE, MMM d').format(at);

  /// "September 22, 2026" - for a receipt or a confirmation, where the full
  /// date is the point.
  static String longDate(DateTime at) => DateFormat('MMMM d, yyyy').format(at);

  /// "10:30 AM".
  static String time(DateTime at) => DateFormat('h:mm a').format(at);

  /// "Mon, Sep 22 · 10:30 AM".
  static String dateTime(DateTime at) => '${dayDate(at)} · ${time(at)}';

  /// "Sep 22 · 10:30 AM" - the same fact on one line inside a card, where the
  /// weekday is the first thing worth dropping.
  static String shortDateTime(DateTime at) => '${date(at)} · ${time(at)}';

  /// "₱1,250". Whole pesos: service prices are quoted in whole pesos, and
  /// "₱1,250.00" adds two digits nobody reads.
  static String peso(num amount) =>
      '₱${NumberFormat.decimalPattern('en_PH').format(amount.round())}';

  /// "₱700 – ₱1,400".
  static String pesoRange(num low, num high) =>
      low == high ? peso(low) : '${peso(low)} – ${peso(high)}';

  /// "Today", "Yesterday", or "Mon, Sep 22" - a list section header.
  static String dayHeading(DateTime at, {DateTime? now}) {
    final DateTime ref = now ?? DateTime.now();
    final DateTime today = DateTime(ref.year, ref.month, ref.day);
    final DateTime day = DateTime(at.year, at.month, at.day);
    final int days = today.difference(day).inDays;
    if (days == 0) return 'Today';
    if (days == 1) return 'Yesterday';
    return dayDate(at);
  }
}
