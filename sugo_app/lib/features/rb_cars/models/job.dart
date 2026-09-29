import '../../../core/utils/formatters.dart';
import 'job_enums.dart';
import 'json_utils.dart';
import 'problem_catalog.dart';

/// One row of the `jobs` table: a repair request posted by a client.
class Job {
  const Job({
    required this.id,
    required this.clientId,
    required this.deviceType,
    required this.problemSymptom,
    required this.hasPhysicalDamage,
    required this.status,
    this.deviceDetail,
    this.brand,
    this.classificationConfidence,
    this.servicePath,
    this.urgency = Urgency.canWait,
    this.latitude,
    this.longitude,
    this.addressText,
    this.budgetMin,
    this.budgetMax,
    this.preferredSchedule,
    this.description,
    this.photoUrls = const <String>[],
    this.assignedTechnicianId,
    this.createdAt,
  });

  factory Job.fromJson(Map<String, dynamic> json) {
    return Job(
      id: json['id'] as String,
      clientId: json['client_id'] as String,
      deviceType:
          DeviceType.fromWire(json['device_type'] as String?) ??
          DeviceType.laptop,
      problemSymptom: json['problem_symptom'] as String? ?? '',
      hasPhysicalDamage: json['has_physical_damage'] as bool? ?? false,
      deviceDetail: json['device_detail'] as String?,
      brand: json['brand'] as String?,
      classificationConfidence: ClassificationConfidence.fromWire(
        json['classification_confidence'] as String?,
      ),
      servicePath: ServicePath.fromWire(json['service_path'] as String?),
      urgency: Urgency.fromWire(json['urgency'] as String?),
      latitude: asNullableDouble(json['latitude']),
      longitude: asNullableDouble(json['longitude']),
      addressText: json['address_text'] as String?,
      budgetMin: asNullableDouble(json['budget_min']),
      budgetMax: asNullableDouble(json['budget_max']),
      preferredSchedule: asDate(json['preferred_schedule']),
      description: json['description'] as String?,
      photoUrls: asStringList(json['photo_urls']),
      status: JobStatus.fromWire(json['status'] as String?),
      assignedTechnicianId: json['assigned_technician_id'] as String?,
      createdAt: asDate(json['created_at']),
    );
  }

  final String id;
  final String clientId;
  final DeviceType deviceType;

  /// The precise device and its brand, as the posting flow wrote them. Read so
  /// "Edit post" can reopen the flow exactly as it was left.
  final String? deviceDetail;
  final String? brand;

  /// A `ProblemCatalog` code, or `ProblemCatalog.notSureCode`.
  final String problemSymptom;

  final bool hasPhysicalDamage;
  final ClassificationConfidence? classificationConfidence;
  final ServicePath? servicePath;
  final Urgency urgency;
  final double? latitude;
  final double? longitude;

  /// Human-readable address captured when the client set the pin. Null when it
  /// could not be resolved - see [locationLabel] for what to show instead.
  final String? addressText;
  final double? budgetMin;
  final double? budgetMax;
  final DateTime? preferredSchedule;
  final String? description;
  final List<String> photoUrls;
  final JobStatus status;
  final String? assignedTechnicianId;
  final DateTime? createdAt;

  String get symptomLabel => ProblemCatalog.labelFor(problemSymptom);

  bool get hasLocation => latitude != null && longitude != null;

  /// Whether the client may still remove this job.
  ///
  /// Mirrors the guards in `handleDeleteJob` so the button is never shown for a
  /// request the server would refuse. Once anyone has accepted, the record
  /// belongs to the technician too - they may have travelled for it.
  bool get canBeDeletedByClient =>
      assignedTechnicianId == null &&
      (status == JobStatus.pending || status == JobStatus.matched);

  /// Whether the client may still edit this job ("Edit post").
  ///
  /// The same rule as deleting, and for the same reason - `handleUpdateJob`
  /// mirrors `handleDeleteJob`. Once a technician has accepted, the job is an
  /// agreement, and changing it from one side is not an edit.
  bool get canBeEditedByClient => canBeDeletedByClient;

  /// What a screen should print for this job's location.
  ///
  /// The address when we have one, the coordinate pair when we do not, and an
  /// honest "not set" when there is nothing at all. Centralised here because
  /// five screens were each formatting the raw numbers themselves, and a client
  /// reading "7.07361, 125.61278" learns nothing about where their appliance
  /// is.
  String get locationLabel {
    final String? address = addressText?.trim();
    if (address != null && address.isNotEmpty) return address;
    if (!hasLocation) return 'No location set';
    return '${latitude!.toStringAsFixed(5)}, ${longitude!.toStringAsFixed(5)}';
  }

  /// "₱800 – ₱2,500", or how the range is open at one end.
  ///
  /// Peso sign and grouped thousands, through [Fmt]. It used to read
  /// "PHP 800 - 2500": the currency code is what a bank statement uses, and
  /// four-figure amounts without a separator are genuinely misread - ₱2500
  /// and ₱25000 differ by one glyph.
  String get budgetLabel {
    final double? min = budgetMin;
    final double? max = budgetMax;
    // "Any budget", the words the posting flow's review step uses for the
    // same answer - one fact, one phrase. "No budget set" read as a missing
    // field rather than a choice the client made.
    if (min == null && max == null) return 'Any budget';
    if (min == null) return 'Up to ${Fmt.peso(max!)}';
    if (max == null) return 'From ${Fmt.peso(min)}';
    return Fmt.pesoRange(min, max);
  }

  String get title => '${deviceType.label}: $symptomLabel';

  /// Short, human-quotable code for this booking, e.g. `#A3F2B1`.
  ///
  /// Derived from the row id rather than stored, because `jobs` is frozen and
  /// a second identifier column would have to be kept unique by something.
  /// Six hex characters is 16 million combinations - ample for a client to read
  /// out while support searches on the full id, which is what the code is for.
  String get reference {
    final String compact = id.replaceAll('-', '');
    final String head = compact.length >= 6 ? compact.substring(0, 6) : compact;
    return '#${head.toUpperCase()}';
  }
}

/// The payload the client builds across the posting flow, before the row
/// exists. Kept separate from [Job] so the form can be half-filled without
/// every field being nullable on the persisted model.
class JobDraft {
  JobDraft();

  DeviceType? deviceType;

  /// Precise device, from the same vocabulary as
  /// `technician_specializations.device_type` (laptop, desktop, aircon, ...).
  ///
  /// [deviceType] stays the coarse RB-CARS category the frozen `jobs` schema
  /// froze. This narrows it so Stage 1 can match a desktop specialist to a
  /// desktop rather than to anything filed under "laptop".
  String? deviceDetail;

  /// Brand of the machine, matching `technician_specializations.brand`.
  ///
  /// Optional on purpose. Null - or "Others" - means the client did not say,
  /// and Stage 1 degrades to matching on device alone rather than excluding
  /// every technician on a detail the client never expressed.
  String? brand;

  String? problemSymptom;
  bool hasPhysicalDamage = false;
  ClassificationResult? classification;

  /// Set when the client overrides the suggested path on the review step.
  ServicePath? servicePathOverride;

  Urgency urgency = Urgency.canWait;
  double? latitude;
  double? longitude;
  String? locationLabel;
  double? budgetMin;
  double? budgetMax;
  DateTime? preferredSchedule;

  /// Free-text model, e.g. `IdeaPad 3 14"`. Deliberately not validated against
  /// a catalogue: the point of the field is to capture what is printed on the
  /// sticker, including the models nobody has listed yet.
  String? model;

  /// "What happened?", asked on the device step.
  String? description;

  /// Anything the client added on the review step, after seeing the summary.
  String? notes;

  List<String> photoUrls = <String>[];

  ServicePath? get servicePath =>
      servicePathOverride ?? classification?.servicePath;

  ClassificationConfidence? get confidence => classification?.confidence;

  /// The three free-text answers as the single `jobs.description` column.
  ///
  /// The form asks for the model, the problem and any afterthoughts on three
  /// different screens, because that is when each is easiest to answer. The
  /// frozen `jobs` table has one text column for all three, so they are joined
  /// here rather than two of them being dropped.
  ///
  /// Labelled, not concatenated: a technician opening the job sees
  /// `Model: IdeaPad 3 14"` on its own line instead of a model number welded to
  /// the front of a sentence. Empty answers contribute no line at all, so a
  /// client who filled in one field does not get two empty labels.
  String? get composedDescription {
    final List<String> parts = <String>[
      if (_present(model)) 'Model: ${model!.trim()}',
      if (_present(description)) description!.trim(),
      if (_present(notes)) 'Notes: ${notes!.trim()}',
    ];
    return parts.isEmpty ? null : parts.join('\n\n');
  }

  static bool _present(String? value) =>
      value != null && value.trim().isNotEmpty;

  bool get isClassified => deviceType != null && problemSymptom != null;

  bool get isReadyToPost =>
      isClassified && servicePath != null && latitude != null;

  /// Runs the rule base and caches the result on the draft.
  ClassificationResult classify() {
    final ClassificationResult result = ClassificationResult.evaluate(
      symptomCode: problemSymptom ?? ProblemCatalog.notSureCode,
      hasPhysicalDamage: hasPhysicalDamage,
    );
    classification = result;
    servicePathOverride = null;
    return result;
  }

  /// Column map for the `jobs` insert. `client_id` is added by the service
  /// from the current session, never from the form.
  Map<String, dynamic> toInsert({required String clientId}) {
    return <String, dynamic>{
      'client_id': clientId,
      ..._columns(),
      'status': JobStatus.pending.wire,
    };
  }

  /// The edited columns for "Edit post" - everything [toInsert] writes except
  /// who owns the job and where it is in its lifecycle, neither of which an
  /// edit may change. `handleUpdateJob` whitelists the same set.
  Map<String, dynamic> toUpdate() => _columns();

  /// The columns the client fills in. One list shared by posting and editing,
  /// so the two can never disagree about what a job is made of.
  Map<String, dynamic> _columns() {
    return <String, dynamic>{
      'device_type': deviceType!.wire,
      // Added in 20260907000010 so Stage 1 can match on brand and on the exact
      // device. Both nullable: an unanswered brand must not block a posting.
      'device_detail': deviceDetail,
      'brand': brand,
      'problem_symptom': problemSymptom!,
      'has_physical_damage': hasPhysicalDamage,
      'classification_confidence': confidence?.wire,
      'service_path': servicePath?.wire,
      'urgency': urgency.wire,
      'latitude': latitude,
      'longitude': longitude,
      // Added in 20260916000006. Nullable: a job posted while the geocoder was
      // unreachable must still be postable, and every screen falls back to the
      // coordinates.
      'address_text': locationLabel,
      'budget_min': budgetMin,
      'budget_max': budgetMax,
      'preferred_schedule': preferredSchedule?.toUtc().toIso8601String(),
      'description': composedDescription,
      'photo_urls': photoUrls,
    };
  }

  /// The reverse of [composedDescription], for "Edit post".
  ///
  /// The frozen `jobs` table has one text column for three answers, joined
  /// with labelled paragraphs. Splitting on those same labels puts each answer
  /// back in the field it came from, instead of the whole paragraph landing in
  /// "What happened?" and growing a second "Model:" line on every save.
  void restoreDescription(String? composed) {
    model = null;
    description = null;
    notes = null;
    if (composed == null || composed.trim().isEmpty) return;

    final List<String> body = <String>[];
    for (final String part in composed.split('\n\n')) {
      final String trimmed = part.trim();
      if (trimmed.startsWith('Model: ')) {
        model = trimmed.substring('Model: '.length).trim();
      } else if (trimmed.startsWith('Notes: ')) {
        notes = trimmed.substring('Notes: '.length).trim();
      } else if (trimmed.isNotEmpty) {
        body.add(trimmed);
      }
    }
    if (body.isNotEmpty) description = body.join('\n\n');
  }
}

/// The job details the matcher copies into `score_breakdown.job`.
///
/// A technician can read their own `job_matches` rows, but
/// `jobs_technician_select_assigned` only lets them read a `jobs` row once they
/// are *assigned* to it. Before accepting they are not assigned, so without
/// this snapshot an incoming offer would show a score and nothing to judge.
///
/// The client's identity and exact coordinates are deliberately absent. A
/// technician who has merely been offered a job gets the distance (from
/// `context.distance_km`) but not the doorstep; the full `jobs` row opens up
/// the moment they accept.
class JobSnapshot {
  const JobSnapshot({
    required this.id,
    required this.deviceType,
    required this.problemSymptom,
    required this.hasPhysicalDamage,
    this.deviceDetail,
    this.brand,
    this.servicePath,
    this.urgency = Urgency.canWait,
    this.confidence,
    this.budgetMin,
    this.budgetMax,
    this.preferredSchedule,
    this.description,
    this.photoUrls = const <String>[],
  });

  factory JobSnapshot.fromJson(Map<String, dynamic> json) {
    return JobSnapshot(
      id: json['id'] as String? ?? '',
      deviceType:
          DeviceType.fromWire(json['device_type'] as String?) ??
          DeviceType.laptop,
      problemSymptom: json['problem_symptom'] as String? ?? '',
      hasPhysicalDamage: json['has_physical_damage'] as bool? ?? false,
      // The matcher has always put these in the snapshot - see the JobSnapshot
      // interface in `match-technician/scoring/types.ts` - but this model
      // dropped them on the floor, so a technician deciding whether to accept
      // could not see what machine it was.
      deviceDetail: json['device_detail'] as String?,
      brand: json['brand'] as String?,
      servicePath: ServicePath.fromWire(json['service_path'] as String?),
      urgency: Urgency.fromWire(json['urgency'] as String?),
      confidence: ClassificationConfidence.fromWire(
        json['classification_confidence'] as String?,
      ),
      budgetMin: asNullableDouble(json['budget_min']),
      budgetMax: asNullableDouble(json['budget_max']),
      preferredSchedule: asDate(json['preferred_schedule']),
      description: json['description'] as String?,
      photoUrls: asStringList(json['photo_urls']),
    );
  }

  final String id;
  final DeviceType deviceType;
  final String problemSymptom;
  final bool hasPhysicalDamage;

  /// The exact machine and its make, as the client typed them - "ThinkPad
  /// T480", "Acer". Both nullable: the posting flow does not insist on either,
  /// so a technician sees them when they were given and nothing when not.
  final String? deviceDetail;
  final String? brand;

  final ServicePath? servicePath;
  final Urgency urgency;
  final ClassificationConfidence? confidence;
  final double? budgetMin;
  final double? budgetMax;
  final DateTime? preferredSchedule;
  final String? description;
  final List<String> photoUrls;

  String get symptomLabel => ProblemCatalog.labelFor(problemSymptom);

  String get title => '${deviceType.label}: $symptomLabel';

  bool get isUrgent => urgency == Urgency.needToday;

  /// Same formatting as [Job.budgetLabel] - see there for why it is a peso
  /// sign with grouped thousands rather than a currency code.
  String get budgetLabel {
    final double? min = budgetMin;
    final double? max = budgetMax;
    // "Any budget", the words the posting flow's review step uses for the
    // same answer - one fact, one phrase. "No budget set" read as a missing
    // field rather than a choice the client made.
    if (min == null && max == null) return 'Any budget';
    if (min == null) return 'Up to ${Fmt.peso(max!)}';
    if (max == null) return 'From ${Fmt.peso(min)}';
    return Fmt.pesoRange(min, max);
  }
}
