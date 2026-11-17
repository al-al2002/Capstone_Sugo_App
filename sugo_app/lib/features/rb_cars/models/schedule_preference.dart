import 'job_enums.dart';

/// "Flexible" or "Urgent" - the one question that answers two columns.
///
/// ## Two buttons (2026-11-17)
///
/// There used to be a third, "This week", stored as a seven-day deadline in
/// `jobs.preferred_schedule` because `jobs.urgency` only holds
/// `('need_today','can_wait')`. At the user's request it was removed: a client
/// either needs it today or does not. Each choice writes both columns:
///
/// | choice     | `urgency`    | `preferred_schedule` |
/// |------------|--------------|----------------------|
/// | Flexible   | `can_wait`   | null                 |
/// | Urgent     | `need_today` | end of today         |
///
/// Urgent now also means something on the price and the clock: a 20% urgent
/// fee on the labor (`JobPrice`), and the chosen technician has five minutes
/// to accept before the request passes to the next one
/// (`urgent-offer-sweep`).
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
  // "This week" was removed on 2026-11-17 at the user's request: two choices,
  // Flexible and Urgent. A job saved with a seven-day deadline reads back as
  // Flexible (see [fromJob]).
  urgent(
    'Urgent',
    'Today. +20% urgent fee, and the technician has 5 minutes to accept.',
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
  /// `need_today` is Urgent; anything else is Flexible - including a job saved
  /// with a "this week" deadline before that option was removed.
  static SchedulePreference fromJob({
    required Urgency urgency,
    required DateTime? preferredSchedule,
  }) {
    return urgency == Urgency.needToday
        ? SchedulePreference.urgent
        : SchedulePreference.flexible;
  }
}
