import '../../rb_cars/models/job.dart';
import '../../rb_cars/models/job_enums.dart';

/// The three figures in a client's profile header: Bookings, Completed,
/// In progress.
///
/// ## What counts (2026-11-23)
///
/// Only real service jobs - **Home Service** and **Shop Repair**. A question
/// posted to the technician community is not a booking: nobody is sent, and
/// it never moves through Booked or Fixed. Cancelled requests are left out
/// too.
///
/// * **In progress** - open service jobs: waiting for the client to choose,
///   waiting for a technician to accept, booked, or being repaired.
/// * **Completed** - fixed and closed.
/// * **Bookings** - the two together, so the three figures always add up.
///
/// Until this, "In progress" was every job minus the completed ones, so it
/// counted community questions and cancelled requests as well; the user
/// asked for it to count only Home Service and Shop Repair.
class ClientBookingStats {
  const ClientBookingStats({required this.completed, required this.active});

  factory ClientBookingStats.from(Iterable<Job> jobs) {
    int completed = 0;
    int active = 0;
    for (final Job job in jobs) {
      if (!isServiceJob(job)) continue;
      switch (job.status) {
        case JobStatus.completed:
          completed++;
        case JobStatus.pending ||
            JobStatus.matched ||
            JobStatus.confirmed ||
            JobStatus.inProgress:
          active++;
        case JobStatus.cancelled:
          break;
      }
    }
    return ClientBookingStats(completed: completed, active: active);
  }

  /// Fixed and closed.
  final int completed;

  /// Open: choosing, waiting, booked, or being repaired.
  final int active;

  int get total => completed + active;

  /// Home Service or Shop Repair - the jobs a technician is sent on.
  static bool isServiceJob(Job job) =>
      job.servicePath == ServicePath.homeService ||
      job.servicePath == ServicePath.pickup;
}
