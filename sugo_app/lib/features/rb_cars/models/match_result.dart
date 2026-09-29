import 'job.dart';
import 'job_enums.dart';
import 'json_utils.dart';
import 'score_breakdown.dart';
import 'technician.dart';

/// One row of `job_matches`: a ranked offer the engine produced for a job.
///
/// ## Where the technician details come from
///
/// RLS on `technicians` is `id = auth.uid()`, so a client can never select
/// another person's technician row. The matching edge function therefore
/// embeds a snapshot of the technician inside `score_breakdown.technician`
/// when it writes the match. The client reads the snapshot through its own
/// `job_matches` row, which it is allowed to see. As a side effect the card
/// shows the technician exactly as they were when the match was scored.
class MatchResult {
  const MatchResult({
    required this.id,
    required this.jobId,
    required this.technicianId,
    required this.rank,
    required this.status,
    required this.breakdown,
    this.technician,
    this.job,
    this.suitabilityScore = 0,
    this.acceptanceScore = 0,
    this.finalScore = 0,
    this.createdAt,
  });

  factory MatchResult.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? raw =
        json['score_breakdown'] as Map<String, dynamic>?;

    final Map<String, dynamic>? snapshot =
        raw?['technician'] as Map<String, dynamic>?;

    final Map<String, dynamic>? jobSnapshot =
        raw?['job'] as Map<String, dynamic>?;

    return MatchResult(
      id: json['id'] as String,
      jobId: json['job_id'] as String,
      technicianId: json['technician_id'] as String,
      rank: asInt(json['rank']),
      suitabilityScore: asDouble(json['suitability_score']),
      acceptanceScore: asDouble(json['acceptance_score']),
      finalScore: asDouble(json['final_score']),
      status: MatchStatus.fromWire(json['status'] as String?),
      breakdown: ScoreBreakdown.fromJson(raw),
      technician: snapshot == null ? null : Technician.fromJson(snapshot),
      job: jobSnapshot == null ? null : JobSnapshot.fromJson(jobSnapshot),
      createdAt: asDate(json['created_at']),
    );
  }

  final String id;
  final String jobId;
  final String technicianId;

  /// 1, 2 or 3 - enforced by a check constraint.
  final int rank;

  final double suitabilityScore;
  final double acceptanceScore;
  final double finalScore;
  final MatchStatus status;
  final ScoreBreakdown breakdown;

  /// Snapshot taken at match time; null only for very old rows.
  final Technician? technician;

  /// The job this offer is for, as the technician is allowed to see it.
  /// Null on rows written before the snapshot was added.
  final JobSnapshot? job;

  final DateTime? createdAt;

  /// 0-100 for the score ring on the match card.
  int get scorePercent => (finalScore.clamp(0, 1) * 100).round();

  bool get isTopPick => rank == 1;

  bool get isDeclined => status == MatchStatus.declined;

  bool get isAccepted => status == MatchStatus.accepted;

  /// On the client's shortlist, not yet requested from the technician.
  bool get isShortlisted => status == MatchStatus.shortlisted;

  /// Still choosable by the client: either on the shortlist, or already
  /// requested and awaiting the technician's answer.
  bool get isOpen =>
      status == MatchStatus.shortlisted || status == MatchStatus.offered;

  /// The client has requested this technician and is waiting on them.
  bool get isAwaitingTechnician => status == MatchStatus.offered;

  /// Neutral on purpose. "Best technician" is a claim about a person the
  /// ranking cannot make - it only knows who fits this request best right now.
  String get rankLabel => switch (rank) {
    1 => 'Recommended',
    2 => 'Alternative',
    _ => 'Another match',
  };

  /// Stage 1 as a percentage: can they do this repair?
  ///
  /// From the stage inside the breakdown rather than the column, because the
  /// breakdown is what the rules re-weighted; the two agree on every row the
  /// matcher writes.
  int get suitabilityPercent => _percent(
    breakdown.stage1.factors.isEmpty
        ? suitabilityScore
        : breakdown.stage1.score,
  );

  /// Stage 2 as a percentage: how likely are they to accept?
  int get acceptancePercent => _percent(
    breakdown.stage2.factors.isEmpty ? acceptanceScore : breakdown.stage2.score,
  );

  /// The recommendation score: what the list is ranked by. On a version 1
  /// row this is the old 60/40 blend, which played the same role.
  int get recommendationPercent => scorePercent;

  static int _percent(double value) => (value.clamp(0, 1) * 100).round();

  String get explainability => breakdown.explainabilityLine();
}

/// One technician the engine scored, whether or not they became an offer.
///
/// ## Why this is not a `job_matches` row
///
/// `job_matches.rank` is `check (rank between 1 and 3)`, so the table
/// physically cannot hold a fourth candidate. Everyone past third place exists
/// only in the matching function's response, and only until the screen that
/// asked for it is closed. Nothing here is persisted, which is also why the
/// list disappears on a reload rather than going stale.
class ConsideredTechnician {
  const ConsideredTechnician({
    required this.technicianId,
    required this.rank,
    required this.offered,
    this.available = false,
    this.fullName,
    this.avatarUrl,
    this.distanceKm,
    this.etaMinutes,
    this.suitability = 0,
    this.acceptance = 0,
    this.finalScore = 0,
    this.explainability = const <String>[],
  });

  factory ConsideredTechnician.fromJson(Map<String, dynamic> json) {
    return ConsideredTechnician(
      technicianId: json['technician_id'] as String? ?? '',
      rank: asInt(json['rank']),
      offered: json['offered'] as bool? ?? false,
      available: json['available'] as bool? ?? false,
      fullName: json['full_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      distanceKm: asNullableDouble(json['distance_km']),
      etaMinutes: asNullableDouble(json['eta_minutes']),
      suitability: asDouble(json['suitability']),
      acceptance: asDouble(json['acceptance']),
      finalScore: asDouble(json['final_score']),
      explainability: asStringList(json['explainability']),
    );
  }

  final String technicianId;

  /// Position in the full ranking, 1-based. Not `job_matches.rank`.
  final int rank;

  /// True for the first three - the ones actually written as offers.
  final bool offered;

  /// False while they are on vacation. They are ranked lower and labelled,
  /// never filtered out.
  final bool available;

  final String? fullName;
  final String? avatarUrl;
  final double? distanceKm;
  final double? etaMinutes;
  final double suitability;
  final double acceptance;
  final double finalScore;
  final List<String> explainability;

  String get name =>
      (fullName ?? '').trim().isEmpty ? 'Technician' : fullName!.trim();

  /// "on vacation", or null when they can be booked - which needs no label.
  String? get statusLabel => available ? null : 'on vacation';

  String get distanceLabel {
    final double? km = distanceKm;
    if (km == null) return 'Distance unknown';
    return km < 1
        ? '${(km * 1000).round()} m away'
        : '${km.toStringAsFixed(1)} km away';
  }
}

/// What one run of RB-CARS produced.
///
/// [matches] is what was written to `job_matches` and survives a reload.
/// [considered] is the full ranking, and [message] is the engine's own
/// explanation when it produced nothing - previously discarded, which left the
/// client staring at a hardcoded guess about why their list was empty.
class MatchingRun {
  const MatchingRun({
    this.matches = const <MatchResult>[],
    this.considered = const <ConsideredTechnician>[],
    this.message,
    this.evaluated = 0,
  });

  final List<MatchResult> matches;
  final List<ConsideredTechnician> considered;

  /// Set only when the engine produced no offers, and it says exactly why.
  final String? message;

  /// How many technicians made it past the hard gates and were scored.
  final int evaluated;
}
