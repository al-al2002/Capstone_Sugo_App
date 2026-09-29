import 'json_utils.dart';
import 'technician_profile_details.dart';

/// Both people on one job, as the `job_parties` view resolves them.
///
/// ## Why this is not on `Job`
///
/// A `jobs` row carries ids and nothing else about the people, and `profiles`
/// is readable only by its owner - so neither the client nor the technician
/// could put a name to the other from the job alone. That is why the bookings
/// list used to print "Technician assigned" and "Client assigned".
///
/// The view resolves both through `profile_display()`, which returns only the
/// public subset: id, name, picture. Keeping it a separate model mirrors that
/// boundary - a `Job` is the job, this is who is on it.
class JobParty {
  const JobParty({
    required this.jobId,
    required this.clientId,
    this.clientName,
    this.clientAvatarUrl,
    this.technicianId,
    this.technicianName,
    this.technicianAvatarUrl,
    this.technicianIsRequest = false,
    this.myRating,
  });

  factory JobParty.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> client =
        json['client'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final Map<String, dynamic> technician =
        json['technician'] as Map<String, dynamic>? ??
        const <String, dynamic>{};

    return JobParty(
      jobId: json['job_id'] as String,
      clientId: json['client_id'] as String? ?? '',
      clientName: client['full_name'] as String?,
      clientAvatarUrl: client['avatar_url'] as String?,
      technicianId: json['technician_id'] as String?,
      technicianName: technician['full_name'] as String?,
      technicianAvatarUrl: technician['avatar_url'] as String?,
      technicianIsRequest: json['technician_is_request'] as bool? ?? false,
      myRating: asNullableInt(json['my_rating']),
    );
  }

  final String jobId;
  final String clientId;
  final String? clientName;
  final String? clientAvatarUrl;

  /// The assigned technician, or - before anyone accepts - the one the client
  /// requested. Null when nobody has been chosen yet.
  final String? technicianId;
  final String? technicianName;
  final String? technicianAvatarUrl;

  /// True while the technician has only been *requested*. The name is still
  /// shown - it is who the client is waiting for - but labelled as a request,
  /// never as a booking.
  final bool technicianIsRequest;

  /// The caller's own stars for the other person on this job: what a client
  /// gave the technician, or what a technician gave the client. Null until
  /// they rate. This is what replaces the grey "Rate" prompt with real stars.
  final int? myRating;

  bool get hasTechnician => technicianId != null;

  String get clientLabel => _name(clientName, 'SUGO client');
  String get technicianLabel => _name(technicianName, 'SUGO technician');

  static String _name(String? raw, String fallback) {
    final String? name = raw?.trim();
    return (name == null || name.isEmpty) ? fallback : name;
  }
}

/// A client's public profile, from `client_profile()`.
///
/// Deliberately the subset a technician needs before accepting a job, and
/// nothing a client would not expect to be public: never a phone number, an
/// email, or any job's location. See migration 20260921000010.
class ClientProfileDetails {
  const ClientProfileDetails({
    required this.id,
    this.fullName,
    this.avatarUrl,
    this.memberSince,
    this.idVerified = false,
    this.jobsPosted = 0,
    this.jobsCompleted = 0,
    this.jobsCancelled = 0,
    this.rating = 0,
    this.ratingCount = 0,
    this.starBreakdown = const <int, int>{},
    this.communityQuestions = 0,
    this.reviews = const <TechnicianReview>[],
  });

  factory ClientProfileDetails.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> breakdown =
        json['star_breakdown'] as Map<String, dynamic>? ??
        const <String, dynamic>{};

    return ClientProfileDetails(
      id: json['id'] as String? ?? '',
      fullName: json['full_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      memberSince: asDate(json['member_since']),
      idVerified: json['id_verified'] as bool? ?? false,
      jobsPosted: asInt(json['jobs_posted']),
      jobsCompleted: asInt(json['jobs_completed']),
      jobsCancelled: asInt(json['jobs_cancelled']),
      rating: asDouble(json['rating']),
      ratingCount: asInt(json['rating_count']),
      starBreakdown: <int, int>{
        for (int star = 1; star <= 5; star++) star: asInt(breakdown['$star']),
      },
      communityQuestions: asInt(json['community_questions']),
      // The RPC emits these with exactly the keys `technician_profile` uses,
      // so the same model - and the same `ReviewCard` - serves both directions
      // of rating. "A review" has one shape here, whoever wrote it.
      reviews: (json['reviews'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(TechnicianReview.fromJson)
          .toList(growable: false),
    );
  }

  final String id;
  final String? fullName;
  final String? avatarUrl;
  final DateTime? memberSince;

  /// Whether their government ID was approved - the single strongest trust
  /// signal a technician can have about a stranger's address.
  final bool idVerified;

  final int jobsPosted;
  final int jobsCompleted;
  final int jobsCancelled;

  /// Average of the stars technicians gave this client.
  final double rating;
  final int ratingCount;
  final Map<int, int> starBreakdown;
  final int communityQuestions;
  final List<TechnicianReview> reviews;

  String get displayName {
    final String? name = fullName?.trim();
    return (name == null || name.isEmpty) ? 'SUGO client' : name;
  }

  /// Share of this client's finished jobs that ended in completion rather than
  /// cancellation. Null when nothing has finished - "0%" would slander a
  /// brand-new client.
  int? get completionRate {
    final int finished = jobsCompleted + jobsCancelled;
    if (finished == 0) return null;
    return (jobsCompleted * 100 / finished).round();
  }
}
