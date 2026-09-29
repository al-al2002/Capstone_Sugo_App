import 'job_enums.dart';
import 'json_utils.dart';
import 'problem_catalog.dart';
import 'technician.dart';
import 'technician_specialization.dart';

/// One client-authored review, as `technician_profile()` and
/// `technician_reviews()` return it.
class TechnicianReview {
  const TechnicianReview({
    required this.id,
    required this.stars,
    this.comment,
    this.createdAt,
    this.reviewerName,
    this.reviewerAvatarUrl,
    this.jobDeviceType,
    this.jobBrand,
    this.jobSymptom,
    this.jobServicePath,
  });

  factory TechnicianReview.fromJson(Map<String, dynamic> json) {
    return TechnicianReview(
      id: json['id'] as String? ?? '',
      stars: asInt(json['stars']),
      comment: json['comment'] as String?,
      createdAt: asDate(json['created_at']),
      reviewerName: json['reviewer_name'] as String?,
      reviewerAvatarUrl: json['reviewer_avatar'] as String?,
      // Added in migration 20260921000009. Older payloads - and a review whose
      // job has been removed - simply lack them, and the card then shows the
      // review without a repair line rather than failing.
      jobDeviceType: DeviceType.fromWire(json['job_device_type'] as String?),
      jobBrand: json['job_brand'] as String?,
      jobSymptom: json['job_symptom'] as String?,
      jobServicePath: ServicePath.fromWire(
        json['job_service_path'] as String?,
      ),
    );
  }

  /// The repair this review is about.
  ///
  /// Deliberately only these four fields: what was fixed, not where, not for
  /// whom beyond the reviewer's own name. The client's address, photos and
  /// free-text description never leave the jobs table - see migration
  /// 20260921000009.
  final DeviceType? jobDeviceType;
  final String? jobBrand;

  /// A catalog code such as `laptop_screen_broken`, rendered through
  /// [ProblemCatalog.labelFor]. Not free text.
  final String? jobSymptom;

  final ServicePath? jobServicePath;

  bool get hasJob => jobDeviceType != null || jobSymptom != null;

  /// "Screen cracked", from the catalog code.
  String? get jobSymptomLabel {
    final String? code = jobSymptom?.trim();
    if (code == null || code.isEmpty) return null;
    return ProblemCatalog.labelFor(code);
  }

  /// "Laptop / PC · Lenovo", or just the device when no brand was given.
  String? get jobDeviceLabel {
    final DeviceType? device = jobDeviceType;
    if (device == null) return null;
    final String? brand = jobBrand?.trim();
    return (brand == null || brand.isEmpty)
        ? device.label
        : '${device.label} · $brand';
  }

  final String id;

  /// 1-5, whole stars. The column is an integer with a check constraint, so
  /// there is no half-star case to render.
  final int stars;

  /// Null when the client rated without writing anything, which is common and
  /// not an error - the tile then shows stars and a date only.
  final String? comment;

  final DateTime? createdAt;
  final String? reviewerName;
  final String? reviewerAvatarUrl;

  /// Shown when the reviewer has no name on their profile. Not "Anonymous",
  /// which implies a deliberate choice that was never offered.
  String get reviewerLabel {
    final String? name = reviewerName?.trim();
    return (name == null || name.isEmpty) ? 'SUGO client' : name;
  }

  bool get hasComment => (comment?.trim().isNotEmpty) ?? false;
}

/// Completed jobs of one device type, from `work_history`.
///
/// An aggregate, and deliberately nothing more. It counts every completed job,
/// reviewed or not - which is what makes it "past work" rather than a second
/// copy of the reviews - so it must not carry anything that could identify the
/// client behind an unreviewed job. A device and a number cannot.
class WorkHistoryEntry {
  const WorkHistoryEntry({required this.deviceType, required this.jobs});

  factory WorkHistoryEntry.fromJson(Map<String, dynamic> json) {
    return WorkHistoryEntry(
      deviceType: DeviceType.fromWire(json['device_type'] as String?),
      jobs: asInt(json['jobs']),
    );
  }

  /// Null for a device value the app does not know yet. Rendered as "Other"
  /// rather than dropped, so the counts still add up to the total.
  final DeviceType? deviceType;
  final int jobs;
}

/// One piece of past work from `technician_portfolio`.
class PortfolioItem {
  const PortfolioItem({
    required this.id,
    required this.photoUrl,
    this.description,
    this.createdAt,
  });

  factory PortfolioItem.fromJson(Map<String, dynamic> json) {
    return PortfolioItem(
      id: json['id'] as String? ?? '',
      photoUrl: json['photo_url'] as String? ?? '',
      description: json['description'] as String?,
      createdAt: asDate(json['created_at']),
    );
  }

  final String id;
  final String photoUrl;
  final String? description;
  final DateTime? createdAt;
}

/// Everything the technician profile screen draws, from one `technician_profile`
/// call.
///
/// The RPC returns a single jsonb document rather than four row sets, so the
/// screen either has all of it or none of it - there is no state where the
/// badges have arrived but the reviews have not, and therefore no half-rendered
/// profile to design around.
class TechnicianProfileDetails {
  const TechnicianProfileDetails({
    required this.technician,
    this.specializations = const <TechnicianSpecialization>[],
    this.portfolio = const <PortfolioItem>[],
    this.reviews = const <TechnicianReview>[],
    this.workHistory = const <WorkHistoryEntry>[],
    this.starBreakdown = const <int, int>{},
    this.contactUnlocked = false,
    this.phone,
    this.shopName,
    this.shopLatitude,
    this.shopLongitude,
  });

  factory TechnicianProfileDetails.fromJson(Map<String, dynamic> json) {
    // The technician itself parses from the same flat keys the listing RPCs
    // emit, so one model serves the card and the profile header.
    final Technician technician = Technician.fromJson(json);

    final Map<String, dynamic> breakdown =
        json['star_breakdown'] as Map<String, dynamic>? ??
        const <String, dynamic>{};

    return TechnicianProfileDetails(
      technician: technician,
      specializations: technician.registeredSpecializations,
      portfolio: (json['portfolio'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(PortfolioItem.fromJson)
          .toList(growable: false),
      reviews: (json['reviews'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(TechnicianReview.fromJson)
          .toList(growable: false),
      workHistory:
          (json['work_history'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(WorkHistoryEntry.fromJson)
              .where((WorkHistoryEntry e) => e.jobs > 0)
              .toList(growable: false),
      starBreakdown: <int, int>{
        for (int star = 1; star <= 5; star++)
          star: asInt(breakdown['$star']),
      },
      contactUnlocked: json['contact_unlocked'] as bool? ?? false,
      phone: json['phone'] as String?,
      shopName: json['shop_name'] as String?,
      shopLatitude: asNullableDouble(json['shop_latitude']),
      shopLongitude: asNullableDouble(json['shop_longitude']),
    );
  }

  final Technician technician;
  final List<TechnicianSpecialization> specializations;
  final List<PortfolioItem> portfolio;
  final List<TechnicianReview> reviews;

  /// Completed jobs by device, busiest first. Empty for a technician with no
  /// finished work, and for payloads older than migration 20260921000009.
  final List<WorkHistoryEntry> workHistory;

  /// Star value (1-5) to how many reviews gave it. Always has all five keys,
  /// so the bar chart never has a missing row.
  final Map<int, int> starBreakdown;

  /// True when the caller has a confirmed, in-progress or completed job with
  /// this technician. Gates the call button.
  final bool contactUnlocked;

  /// Null unless [contactUnlocked].
  final String? phone;

  /// Where to collect a repaired unit. Behind the same booking gate as [phone]:
  /// a browsing client never receives it, which is the rule
  /// `technician-directory` set and this keeps.
  final String? shopName;
  final double? shopLatitude;
  final double? shopLongitude;

  /// True when we can actually point the client at the workshop.
  bool get hasShopLocation =>
      shopLatitude != null && shopLongitude != null;

  int get reviewCount => technician.reviewCount;
  double get averageRating => technician.rating;

  /// Largest bucket in [starBreakdown], used to scale the bars. Never zero, so
  /// callers can divide by it without a guard.
  int get largestStarBucket {
    int largest = 0;
    for (final int count in starBreakdown.values) {
      if (count > largest) largest = count;
    }
    return largest == 0 ? 1 : largest;
  }

  /// A copy with more reviews appended, for the paged list.
  TechnicianProfileDetails withMoreReviews(List<TechnicianReview> more) =>
      _copy(reviews: <TechnicianReview>[...reviews, ...more]);

  /// A copy with [technician] replaced - used to merge in vacation status
  /// from `technicians_away()`, which the profile RPC does not carry.
  TechnicianProfileDetails withTechnician(Technician technician) =>
      _copy(technician: technician);

  /// The one place every field is carried through. Both copies above go
  /// through it, so a field added later cannot be dropped by one of them -
  /// the trap that once blanked "Past work" and the workshop location on a
  /// second page of reviews.
  TechnicianProfileDetails _copy({
    Technician? technician,
    List<TechnicianReview>? reviews,
  }) {
    return TechnicianProfileDetails(
      technician: technician ?? this.technician,
      specializations: specializations,
      portfolio: portfolio,
      reviews: reviews ?? this.reviews,
      workHistory: workHistory,
      starBreakdown: starBreakdown,
      contactUnlocked: contactUnlocked,
      phone: phone,
      shopName: shopName,
      shopLatitude: shopLatitude,
      shopLongitude: shopLongitude,
    );
  }
}
