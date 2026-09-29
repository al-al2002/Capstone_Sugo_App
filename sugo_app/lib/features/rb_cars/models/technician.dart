import 'package:intl/intl.dart';

import '../../onboarding/models/specialization_catalog.dart' as catalog;
import 'job_enums.dart';
import 'json_utils.dart';
import 'technician_specialization.dart';

/// A service provider: one row of `technicians` joined to its `profiles` row.
///
/// ## Why some values are derived, not stored
///
/// The `technicians` table holds skills, tier, verification, rating, job counts
/// and location. It deliberately does not hold a bio, an hourly rate or a
/// "years of experience" field. Those three are derived here from data we do
/// store, so the UI can render the reference layout without inventing columns:
///
/// * [memberSinceLabel] and [tenureLabel] come from `created_at`.
/// * [indicativeHourlyFee] comes from [tier] via [_tierRates] - the published
///   band for that tier, not a per-technician negotiated rate.
/// * [bio] is composed from specialization, badge and job history.
///
/// If the capstone later needs real values, each is a single `alter table
/// technicians add column ...` plus a change to one getter below.
class Technician {
  const Technician({
    required this.id,
    this.fullName,
    this.avatarUrl,
    this.phone,
    this.skillTags = const <String>[],
    this.specialization = const <String>[],
    this.tier = TechnicianTier.standard,
    this.isVerified = false,
    this.badge,
    this.rating = 0,
    this.totalJobs = 0,
    this.currentWorkload = 0,
    this.latitude,
    this.longitude,
    this.memberSince,
    this.distanceKm,
    this.registeredSpecializations = const <TechnicianSpecialization>[],
    this.reviewCount = 0,
    this.primaryDeviceType,
    this.primaryBrand,
    this.matchRank,
    this.isTopMatch = false,
    this.isNewFromServer,
    this.awayUntil,
  });

  /// Parses either a direct `technicians` row (with an embedded `profiles`
  /// object from a PostgREST join) or the technician snapshot the matching
  /// edge function writes into `job_matches.score_breakdown`.
  factory Technician.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> profile =
        json['profiles'] as Map<String, dynamic>? ?? const <String, dynamic>{};

    String? pick(String key) => (json[key] ?? profile[key]) as String?;

    return Technician(
      id: (json['id'] ?? json['technician_id']) as String? ?? '',
      fullName: pick('full_name'),
      avatarUrl: pick('avatar_url'),
      phone: pick('phone'),
      skillTags: asStringList(json['skill_tags']),
      specialization: asStringList(json['specialization']),
      tier: TechnicianTier.fromWire(json['tier'] as String?),
      isVerified: json['is_verified'] as bool? ?? false,
      // `is_available` is deliberately not read. It was the online/offline
      // switch, retired on 2026-09-22; availability is [awayUntil] now.
      badge: json['badge'] as String?,
      rating: asDouble(json['rating']),
      totalJobs: asInt(json['total_jobs']),
      currentWorkload: asInt(json['current_workload']),
      latitude: asNullableDouble(json['latitude']),
      longitude: asNullableDouble(json['longitude']),
      memberSince: asDate(json['member_since'] ?? json['created_at']),
      // Computed by the `technician-directory` function against the origin the
      // client sends. Absent when the client had no location to send, or when
      // the technician has not set theirs.
      distanceKm: asNullableDouble(json['distance_km']),
      // Everything below is emitted by the `recommended_technicians` and
      // `match_technicians_for_job` RPCs. The older sources - the directory
      // function and the match snapshot - do not send these keys, so each one
      // degrades to a default rather than throwing.
      registeredSpecializations: TechnicianSpecialization.listFrom(
        json['specializations'],
      ),
      reviewCount: asInt(json['review_count']),
      primaryDeviceType: json['primary_device_type'] as String?,
      primaryBrand: json['primary_brand'] as String?,
      matchRank: asNullableInt(json['match_rank']),
      isTopMatch: json['is_top_match'] as bool? ?? false,
      isNewFromServer: json['is_new'] as bool?,
      // Sent by the match snapshot (`score_breakdown.technician`). The
      // listings do not carry it; the directory service merges it in from
      // `technicians_away()` instead - see TechnicianDirectoryService.
      awayUntil: _parseDay(json['away_until']),
    );
  }

  /// `2026-09-27` -> local midnight on that day, or null.
  static DateTime? _parseDay(Object? value) {
    if (value is! String || value.isEmpty) return null;
    final DateTime? parsed = DateTime.tryParse(value);
    return parsed == null ? null : DateTime(parsed.year, parsed.month, parsed.day);
  }

  /// Same uuid as `profiles.id` and `auth.users.id`.
  final String id;
  final String? fullName;
  final String? avatarUrl;
  final String? phone;
  final List<String> skillTags;
  final List<String> specialization;
  final TechnicianTier tier;
  final bool isVerified;

  final String? badge;
  final double rating;
  final int totalJobs;
  final int currentWorkload;
  final double? latitude;
  final double? longitude;
  final DateTime? memberSince;

  /// Straight-line kilometres from the client, when the directory could work
  /// it out. Never derived on this side: the technician's own coordinates are
  /// deliberately not sent to a browsing client.
  final double? distanceKm;

  /// Rows of `technician_specializations` - the device + brand pairs this
  /// technician actually registered. Empty for sources that do not carry them
  /// (the match snapshot, the older directory function), which is why every
  /// caller must fall back rather than assume a first element.
  final List<TechnicianSpecialization> registeredSpecializations;

  /// How many written reviews back [rating]. Distinct from [totalJobs]: a
  /// completed job that nobody reviewed counts towards one and not the other,
  /// and "4.8 from 3 reviews" is a different claim from "4.8 from 60".
  final int reviewCount;

  /// The single specialisation the card names. On a task-matching row this is
  /// the one that matched the job, not the technician's usual one.
  final String? primaryDeviceType;
  final String? primaryBrand;

  /// Task matching only: 1-based position in the ranked list. Null on the
  /// dashboard, which has no ranking to show.
  final int? matchRank;

  /// True for ranks 1-3. Drives the "Top match" ribbon.
  final bool isTopMatch;

  /// `is_new` as the server computed it. Nullable so [isNew] can fall back for
  /// payloads that predate it - see the getter.
  final bool? isNewFromServer;

  /// Last day of the technician's current vacation, or null when working.
  ///
  /// While set, they are still shown - in the Top 3 and the listings - but
  /// cannot be booked: `job-response` refuses the request. This field only
  /// decides what the card SAYS; the refusal happens on the server.
  final DateTime? awayUntil;

  /// On vacation today.
  ///
  /// Re-checked against today because a match card is a snapshot taken when
  /// matching ran: a technician whose vacation ended since should not still
  /// read as away.
  bool get isAway {
    final DateTime? until = awayUntil;
    if (until == null) return false;
    final DateTime now = DateTime.now();
    return !until.isBefore(DateTime(now.year, now.month, now.day));
  }

  /// `On vacation until Sep 27`, or null when working.
  String? get awayLabel =>
      isAway ? 'On vacation until ${DateFormat('MMM d').format(awayUntil!)}' : null;

  /// Returns a copy with [awayUntil] merged in from `technicians_away()`.
  Technician copyWith({DateTime? awayUntil}) {
    return Technician(
      id: id,
      fullName: fullName,
      avatarUrl: avatarUrl,
      phone: phone,
      skillTags: skillTags,
      specialization: specialization,
      tier: tier,
      isVerified: isVerified,
      badge: badge,
      rating: rating,
      totalJobs: totalJobs,
      currentWorkload: currentWorkload,
      latitude: latitude,
      longitude: longitude,
      memberSince: memberSince,
      distanceKm: distanceKm,
      // Carried through explicitly. Omitting them here would silently reset a
      // card to "no specialisations, no reviews, unranked" the moment the
      // vacation merge rebuilt it.
      registeredSpecializations: registeredSpecializations,
      reviewCount: reviewCount,
      primaryDeviceType: primaryDeviceType,
      primaryBrand: primaryBrand,
      matchRank: matchRank,
      isTopMatch: isTopMatch,
      isNewFromServer: isNewFromServer,
      awayUntil: awayUntil ?? this.awayUntil,
    );
  }

  String get displayName {
    final String? name = fullName?.trim();
    return (name == null || name.isEmpty) ? 'SUGO technician' : name;
  }

  String get initials {
    final String name = displayName;
    final List<String> parts = name.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  /// No completed jobs yet. Drives the card's "New" badge.
  ///
  /// Prefers the server's own `is_new`, so both listings and the profile agree
  /// on the definition rather than each re-deriving it from whatever counters
  /// happened to be in their payload.
  bool get isNew => isNewFromServer ?? (totalJobs == 0);

  /// The specific registered specialisation the card prints under the name,
  /// e.g. `Laptop Repair`.
  ///
  /// Resolution order, most specific first:
  ///
  /// 1. `primary_device_type` from the listing RPC. On a task-matching row this
  ///    is the specialisation that matched the job, which is the one the client
  ///    needs to see.
  /// 2. The first row of [registeredSpecializations] - verified first, then
  ///    oldest, as the RPC ordered them.
  /// 3. [headline], which falls back through the coarse `specialization` and
  ///    `skill_tags` arrays.
  ///
  /// Only when all three are empty does this say "General repair technician",
  /// which now means what it says: nothing was ever registered.
  String get specializationLabel {
    final String? wire = primaryDeviceType;
    if (wire != null && wire.trim().isNotEmpty) {
      return '${catalog.SpecializationCatalog.deviceLabel(wire)} Repair';
    }
    if (registeredSpecializations.isNotEmpty) {
      return registeredSpecializations.first.repairLabel;
    }
    return headline;
  }

  /// Title under the name, e.g. "Computer repair specialist".
  ///
  /// Falls back to [skillTags] before giving up and saying "general". A
  /// technician who declared "laptop, printer" as skills but left
  /// `specialization` empty was being advertised as a generalist, which is both
  /// wrong and the least useful thing the line could say.
  String get headline {
    final List<String> labels = specialization.isNotEmpty
        ? specialization.map(labelForSkill).toList()
        : skillTags.map(labelForSkill).toList();

    if (labels.isEmpty) return 'General repair technician';
    if (labels.length == 1) return '${labels.first} specialist';
    if (labels.length == 2) return '${labels.first} and ${labels.last} repair';
    return '${labels.take(2).join(', ')} and more';
  }

  /// Turns any wire value that can land in `specialization` or `skill_tags`
  /// into something readable.
  ///
  /// Three vocabularies reach these two columns and nothing guarantees which:
  ///
  /// * **Assessment tracks** - `submit-assessment` writes
  ///   `specialization: [bank]`, where the bank is a track wire such as
  ///   `computer_repair`.
  /// * **RB-CARS categories** - the four `jobs.device_type` values.
  /// * **Catalogue devices** - `aircon`, `router`, `cctv` and the rest, which
  ///   is what `technician_specializations` records.
  ///
  /// Each is tried in turn, and anything still unrecognised is at least
  /// de-underscored rather than printed raw. The cards were showing
  /// "appliance_repair specialist" because only the second vocabulary was
  /// consulted, and a seeded account carried a value from the first.
  static String labelForSkill(String wire) {
    final String trimmed = wire.trim();
    if (trimmed.isEmpty) return trimmed;

    return catalog.AssessmentTrack.fromWire(trimmed)?.label ??
        DeviceType.fromWire(trimmed)?.label ??
        catalog.SpecializationCatalog.deviceByWire(trimmed)?.label ??
        _humanise(trimmed);
  }

  /// `washing_machine` -> `Washing machine`.
  static String _humanise(String wire) {
    final String spaced = wire.replaceAll('_', ' ').trim();
    if (spaced.isEmpty) return spaced;
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  /// The month and year this technician joined, e.g. `Mar 2026`.
  ///
  /// Null when `created_at` never arrived, and callers must hide the line
  /// rather than substitute anything. This replaced a `yearsOnPlatform` getter
  /// that returned 1 for a null date and floored real tenure at 1, so every
  /// technician on the platform - including one who signed up yesterday - was
  /// advertised as "1 year on SUGO". That is a fabricated credential on a
  /// screen whose whole job is helping someone choose who to trust.
  String? get memberSinceLabel {
    final DateTime? since = memberSince;
    return since == null ? null : DateFormat('MMM yyyy').format(since);
  }

  /// How long they have actually been here, at the resolution that is honest
  /// for the span: days, then months, then years.
  String? get tenureLabel {
    final DateTime? since = memberSince;
    if (since == null) return null;

    final int days = DateTime.now().difference(since).inDays;
    if (days < 0) return null;
    if (days < 14) return 'New this week';
    if (days < 60) return '${days ~/ 7} weeks';

    final int months = days ~/ 30;
    if (months < 24) return '$months month${months == 1 ? '' : 's'}';

    final int years = days ~/ 365;
    return '$years year${years == 1 ? '' : 's'}';
  }

  /// Distance for display, e.g. `1.2 km`, `850 m` or `Nearby`.
  ///
  /// Metres are rounded to the nearest 10, which is the resolution the
  /// directory function sends; printing single metres off a figure already
  /// rounded upstream would be false precision. Anything closer than that
  /// reads as "Nearby" rather than "0 m", which looks like a bug.
  String? get distanceLabel {
    final double? km = distanceKm;
    if (km == null) return null;

    if (km < 1) {
      final int metres = ((km * 1000) / 10).round() * 10;
      return metres < 10 ? 'Nearby' : '$metres m';
    }
    return '${km.toStringAsFixed(1)} km';
  }

  /// [distanceLabel] phrased for a card, e.g. `3.4 km away`.
  ///
  /// "Nearby" is returned unchanged - "Nearby away" is not English - which is
  /// why this is a getter rather than string concatenation at each call site.
  String? get distanceAwayLabel {
    final String? label = distanceLabel;
    if (label == null) return null;
    return label == 'Nearby' ? label : '$label away';
  }

  /// A technician with no completed jobs and no rating yet. Stage 1 gives
  /// these a cold-start boost when they are verified, so a new hire is not
  /// locked out by an empty history.
  bool get isColdStart => totalJobs == 0 && rating == 0;

  /// Published hourly band for the tier, in Philippine pesos.
  static const Map<TechnicianTier, int> _tierRates = <TechnicianTier, int>{
    TechnicianTier.standard: 350,
    TechnicianTier.pro: 550,
    TechnicianTier.elite: 800,
  };

  int get indicativeHourlyFee => _tierRates[tier] ?? 350;

  /// Rough job cost band shown next to the hourly fee: a typical repair runs
  /// two to four billable hours.
  (int, int) get estimatedJobCostRange =>
      (indicativeHourlyFee * 2, indicativeHourlyFee * 4);

  String get badgeLabel {
    final String? explicit = badge?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    if (tier == TechnicianTier.elite) return 'Elite';
    if (tier == TechnicianTier.pro) return 'Pro';
    return isVerified ? 'Verified' : 'New';
  }

  /// Composed "About" paragraph for the technician detail screen.
  String get bio {
    final StringBuffer buffer = StringBuffer();
    buffer.write('$displayName is a ${tier.label.toLowerCase()}-tier ');
    buffer.write('technician on SUGO');
    if (isVerified) buffer.write(', ID-verified by our team');
    buffer.write('. ');

    if (specialization.isNotEmpty) {
      final String areas = specialization
          .map((String s) => labelForSkill(s).toLowerCase())
          .join(', ');
      buffer.write('Specialises in $areas repairs. ');
    }

    if (totalJobs > 0) {
      buffer.write('Has completed $totalJobs job');
      buffer.write(totalJobs == 1 ? '' : 's');
      if (rating > 0) {
        buffer.write(' with an average rating of ${rating.toStringAsFixed(1)}');
      }
      buffer.write('. ');
    } else {
      buffer.write('Newly onboarded and taking first bookings. ');
    }

    if (skillTags.isNotEmpty) {
      buffer.write('Common jobs: ${skillTags.take(4).join(', ')}.');
    }

    return buffer.toString().trim();
  }
}
