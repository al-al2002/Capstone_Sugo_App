import 'job_enums.dart';

/// "Flexible", "This week" or "Urgent" - the one question that answers two
/// columns.
///
/// ## Three buttons over a two-value column
///
/// `jobs.urgency` is checked against `('need_today','can_wait')` and the
/// migration is frozen, so a third urgency value is not available. But two
/// buttons could not express what clients actually mean: "can wait" covers both
/// *no rush at all* and *sometime this week*, and those two produce very
/// different bookings.
///
/// The missing information already has a column - `jobs.preferred_schedule` -
/// so the third option is stored as a deadline rather than as an urgency. Each
/// choice writes both:
///
/// | choice     | `urgency`    | `preferred_schedule` |
/// |------------|--------------|----------------------|
/// | Flexible   | `can_wait`   | null                 |
/// | This week  | `can_wait`   | 7 days out           |
/// | Urgent     | `need_today` | end of today         |
///
/// That keeps the scorer honest - it reads `urgency` exactly as it always did,
/// and the urgency-path table still flips on `need_today` alone - while the
/// client gets the middle option they were reaching for.
///
/// This is the same presentation-vocabulary trick [DeviceCategory] plays on
/// `jobs.device_type` and [ServiceRoute] plays on `jobs.service_path`.
enum SchedulePreference {
  flexible(
    'Flexible',
    'Whenever a good technician is free.',
    Urgency.canWait,
    null,
  ),
  thisWeek(
    'This week',
    'Booked within the next seven days.',
    Urgency.canWait,
    Duration(days: 7),
  ),
  urgent(
    'Urgent',
    'Today if at all possible.',
    Urgency.needToday,
    Duration.zero,
  );

  const SchedulePreference(this.label, this.blurb, this.urgency, this._within);

  final String label;
  final String blurb;

  /// What this choice writes to `jobs.urgency`.
  final Urgency urgency;

  /// How far out the deadline sits, or null for "no deadline".
  final Duration? _within;

  /// The timestamp this choice writes to `jobs.preferred_schedule`.
  ///
  /// [now] is a parameter rather than a `DateTime.now()` call inside so the
  /// mapping can be tested without the clock moving underneath it.
  ///
  /// Both deadlines land at the end of their day. A client who says "urgent" on
  /// Tuesday morning means "before Tuesday is over", not "before this minute
  /// next week", and a technician reading 23:59 is not misled into thinking a
  /// specific appointment was requested.
  DateTime? deadlineFrom(DateTime now) {
    if (_within == null) return null;
    final DateTime day = now.add(_within);
    return DateTime(day.year, day.month, day.day, 23, 59);
  }

  /// Reads a stored job back into the button that produced it.
  ///
  /// `need_today` is unambiguous. Without it, a deadline means the client asked
  /// for one, which is the middle option; no deadline means they did not.
  static SchedulePreference fromJob({
    required Urgency urgency,
    required DateTime? preferredSchedule,
  }) {
    if (urgency == Urgency.needToday) return SchedulePreference.urgent;
    return preferredSchedule == null
        ? SchedulePreference.flexible
        : SchedulePreference.thisWeek;
  }
}
