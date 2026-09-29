import '../../../core/widgets/sugo_route_line.dart';
import '../../rb_cars/models/job_enums.dart';

/// The client's booking, drawn as a trip on a `SugoRouteLine`.
///
/// Four stops, each one a fact the database records:
///
/// | Stop    | Reached when                                           |
/// |---------|--------------------------------------------------------|
/// | Posted  | the `jobs` row exists                                  |
/// | Matched | RB-CARS has written the shortlist (`status = matched`) |
/// | Booked  | a technician accepted (`status = confirmed`)           |
/// | Fixed   | the job is `completed`                                 |
///
/// Between two stops the van sits half way along the leg, which means
/// "something is happening that will lead to the next stop" - the engine
/// ranking, a technician deciding, a repair under way. It never sits at 30%
/// or 70%: the data has no such number, so the drawing does not either.
class BookingRoute {
  const BookingRoute._();

  static const List<String> stops = <String>[
    'Posted',
    'Matched',
    'Booked',
    'Fixed',
  ];

  /// Posted; the engine is still ranking technicians.
  static const SugoRoutePosition finding = SugoRoutePosition.leaving(0);

  /// The shortlist is ready and it is the client's turn to choose.
  static const SugoRoutePosition choosing = SugoRoutePosition.at(1);

  /// One technician has been asked and has not answered.
  static const SugoRoutePosition awaiting = SugoRoutePosition.leaving(1);

  /// Accepted; the visit or pickup has not started.
  static const SugoRoutePosition booked = SugoRoutePosition.at(2);

  /// On the way, collected, or being repaired.
  static const SugoRoutePosition underway = SugoRoutePosition.leaving(2);

  /// Completed.
  static const SugoRoutePosition fixed = SugoRoutePosition.at(3);

  /// The position for a job read straight from `jobs.status`, for screens
  /// that have no tracking row to refine it with.
  ///
  /// [offerPending] is true when the client has picked a technician who has
  /// not answered yet - the one fact `matched` alone does not carry. Null for
  /// a cancelled job: it is not on the way anywhere, and drawing it at some
  /// stop would claim progress it never made.
  static SugoRoutePosition? forStatus(
    JobStatus status, {
    bool offerPending = false,
  }) {
    return switch (status) {
      JobStatus.pending => finding,
      JobStatus.matched => offerPending ? awaiting : choosing,
      JobStatus.confirmed => booked,
      JobStatus.inProgress => underway,
      JobStatus.completed => fixed,
      JobStatus.cancelled => null,
    };
  }
}
