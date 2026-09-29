import 'package:intl/intl.dart';

/// One period a technician has marked as away: a row of
/// `technician_time_off`.
///
/// ## Dates, not moments
///
/// Both ends are calendar days and both are inclusive - 22 to 27 September is
/// six days off, and the technician is back on the 28th. They are held as
/// local midnight and compared by day only, never by instant: a vacation that
/// "ends at 2026-09-27T00:00" would be over before the last day began.
///
/// The server decides "today" in Asia/Manila (`manila_today()`), which is the
/// device's own zone for everyone this app serves. The helpers here only
/// shape what the technician sees; whether a client can book is decided by
/// the database, never by this class.
class TimeOff {
  const TimeOff({
    required this.id,
    required this.startsOn,
    required this.endsOn,
    this.note,
  });

  factory TimeOff.fromJson(Map<String, dynamic> json) {
    final String note = (json['note'] as String? ?? '').trim();
    return TimeOff(
      id: json['id'] as String,
      startsOn: parseDay(json['starts_on'] as String),
      endsOn: parseDay(json['ends_on'] as String),
      note: note.isEmpty ? null : note,
    );
  }

  /// Longest single period, matching the database's
  /// `technician_time_off_length` constraint. Checked here too so the
  /// technician hears it before saving rather than as a database error.
  static const int maxDays = 90;

  /// The note is private and capped at 200 characters in the database.
  static const int maxNoteLength = 200;

  final String id;
  final DateTime startsOn;
  final DateTime endsOn;

  /// Private to the technician. Never shown to a client.
  final String? note;

  /// Days off, counting both ends.
  int get days => endsOn.difference(startsOn).inDays + 1;

  bool isCurrent(DateTime now) {
    final DateTime today = dayOf(now);
    return !today.isBefore(startsOn) && !today.isAfter(endsOn);
  }

  bool isUpcoming(DateTime now) => dayOf(now).isBefore(startsOn);

  /// The first day they are working again.
  DateTime get backOn => endsOn.add(const Duration(days: 1));

  /// `Sep 22 – 27`, or `Sep 29 – Oct 3` across a month, or `Sep 22` for one day.
  String get rangeLabel => formatRange(startsOn, endsOn);

  static String formatRange(DateTime start, DateTime end) {
    if (start == end) return DateFormat('MMM d').format(start);
    if (start.year == end.year && start.month == end.month) {
      return '${DateFormat('MMM d').format(start)} – ${end.day}';
    }
    return '${DateFormat('MMM d').format(start)} – ${DateFormat('MMM d').format(end)}';
  }

  /// Midnight at the start of [moment]'s calendar day.
  static DateTime dayOf(DateTime moment) =>
      DateTime(moment.year, moment.month, moment.day);

  /// `2026-09-27` -> local midnight on that day. `DateTime.parse` on a bare
  /// date already reads it as local, which is what a calendar day means.
  static DateTime parseDay(String wire) => dayOf(DateTime.parse(wire));

  /// Local midnight -> `2026-09-27`, the form a Postgres `date` expects.
  static String toWire(DateTime day) => DateFormat('yyyy-MM-dd').format(day);
}
