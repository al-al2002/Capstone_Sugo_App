import 'job_enums.dart';

/// The technician a client has requested, or had accept, on one job.
///
/// A row of the `client_job_technicians` view. Deliberately not folded into
/// [Job]: a job's own row genuinely does not know this. `assigned_technician_id`
/// stays null until somebody accepts, so between "request sent" and "accepted"
/// - which is exactly the window the client is most anxious about - the job
/// table has nothing to say about who they are waiting for.
///
/// Keeping it separate also keeps the distinction honest. A job with a
/// [JobTechnician] in [MatchStatus.offered] is *waiting*; one in
/// [MatchStatus.accepted] is *booked*. Those are different sentences on the
/// dashboard, and flattening both into a name field would lose that.
class JobTechnician {
  const JobTechnician({
    required this.jobId,
    required this.matchId,
    required this.technicianId,
    required this.status,
    this.fullName,
    this.avatarUrl,
    this.tier = TechnicianTier.standard,
    this.rating = 0,
    this.isVerified = false,
    this.matchedAt,
  });

  factory JobTechnician.fromJson(Map<String, dynamic> json) {
    // `technician` is a jsonb object built by `profile_display()`, because
    // `profiles` is readable only by its owner - a plain join would have left
    // the name null for everybody.
    final Map<String, dynamic> person =
        (json['technician'] as Map<String, dynamic>?) ?? <String, dynamic>{};

    return JobTechnician(
      jobId: json['job_id'] as String,
      matchId: json['match_id'] as String,
      technicianId: json['technician_id'] as String,
      status: MatchStatus.fromWire(json['match_status'] as String?),
      fullName: person['full_name'] as String?,
      avatarUrl: person['avatar_url'] as String?,
      tier: TechnicianTier.fromWire(json['technician_tier'] as String?),
      rating: (json['technician_rating'] as num?)?.toDouble() ?? 0,
      isVerified: json['technician_verified'] as bool? ?? false,
      matchedAt: DateTime.tryParse(
        json['matched_at'] as String? ?? '',
      )?.toLocal(),
    );
  }

  final String jobId;
  final String matchId;
  final String technicianId;
  final MatchStatus status;
  final String? fullName;
  final String? avatarUrl;
  final TechnicianTier tier;
  final double rating;
  final bool isVerified;

  /// When the match was created. Used to say how long the client has been
  /// waiting, which is the fact that makes "cancel" feel justified rather
  /// than impatient.
  final DateTime? matchedAt;

  String get displayName {
    final String? name = fullName?.trim();
    return (name == null || name.isEmpty) ? 'SUGO technician' : name;
  }

  String get firstName => displayName.split(RegExp(r'\s+')).first;

  /// Requested, but they have not answered yet.
  bool get isAwaiting => status == MatchStatus.offered;

  /// They accepted. The job is theirs.
  bool get isAccepted => status == MatchStatus.accepted;

  /// Only a request nobody has answered can be taken back. Once accepted the
  /// job is a commitment on both sides, and cancelling it is a different act
  /// with different consequences.
  bool get canWithdraw => isAwaiting;

  /// How long the request has been sitting unanswered.
  Duration? get waiting {
    final DateTime? since = matchedAt;
    if (since == null || !isAwaiting) return null;
    return DateTime.now().difference(since);
  }

  /// "Waiting 2h" - the sentence that turns an anxious silence into a fact.
  ///
  /// Null below an hour: a request that is five minutes old has not been
  /// ignored, and telling somebody they have "been waiting 5m" invites them to
  /// cancel a technician who is simply driving.
  String? get waitingLabel {
    final Duration? gap = waiting;
    if (gap == null || gap.inHours < 1) return null;
    if (gap.inHours < 24) return 'Waiting ${gap.inHours}h';
    final int days = gap.inDays;
    return 'Waiting $days ${days == 1 ? 'day' : 'days'}';
  }

  /// True once the wait is long enough that offering a way out is a kindness
  /// rather than a nudge to give up.
  bool get isSlow => (waiting?.inHours ?? 0) >= 2;
}
