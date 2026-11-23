import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../rb_cars/models/job_enums.dart';

/// A step of the work record (`job_evidence.milestone`, migration
/// 20261122000002).
///
/// One vocabulary for every kind of job. What the first step is CALLED
/// depends on how the job travels - see [labelFor]. The server words its
/// "add photos first" refusal with the same names (`_shared/evidence.ts`).
enum EvidenceMilestone {
  intake('intake', required: true, icon: Icons.photo_camera_front_outlined),
  diagnosis('diagnosis', required: false, icon: Icons.manage_search_rounded),
  progress('progress', required: false, icon: Icons.build_circle_outlined),
  after('after', required: true, icon: Icons.verified_outlined),
  handover('handover', required: false, icon: Icons.handshake_outlined);

  const EvidenceMilestone(this.wire, {required this.required, required this.icon});

  final String wire;

  /// Required before the technician can mark the job complete.
  final bool required;
  final IconData icon;

  static EvidenceMilestone? fromWire(Object? value) {
    for (final EvidenceMilestone m in EvidenceMilestone.values) {
      if (m.wire == value) return m;
    }
    return null;
  }

  /// "Before" on a home visit, "Collected" on a pickup, "Unit received" on a
  /// drop-off - the same unit-as-found step, named for what happened.
  String labelFor(ServicePath? path, {bool selfDropOff = false}) =>
      switch (this) {
        EvidenceMilestone.intake =>
          path == ServicePath.homeService
              ? 'Before'
              : (selfDropOff ? 'Unit received' : 'Collected'),
        EvidenceMilestone.diagnosis => 'Diagnosis',
        EvidenceMilestone.progress => 'Progress',
        EvidenceMilestone.after =>
          path == ServicePath.homeService ? 'After' : 'After repair',
        EvidenceMilestone.handover => 'Handover',
      };

  /// What to photograph, in one line.
  String blurbFor(ServicePath? path, {bool selfDropOff = false}) =>
      switch (this) {
        EvidenceMilestone.intake =>
          path == ServicePath.homeService
              ? 'The device as you found it, before you touch it.'
              : (selfDropOff
                    ? 'Its condition when the client hands it over.'
                    : 'Its condition when you collect it.'),
        EvidenceMilestone.diagnosis => 'The fault you found, e.g. the burnt part.',
        EvidenceMilestone.progress => 'The repair under way.',
        EvidenceMilestone.after => 'Repaired and working, e.g. powered on.',
        EvidenceMilestone.handover => 'Handed back to the client.',
      };

  /// The steps a job of [path] shows, in order. A home visit has no
  /// handover - the unit never left.
  static List<EvidenceMilestone> stepsFor(ServicePath? path) =>
      path == ServicePath.homeService
      ? const <EvidenceMilestone>[intake, diagnosis, progress, after]
      : EvidenceMilestone.values;
}

/// One checkpoint on a job's work record: 1-4 photos, an optional note, where
/// and when it was taken. Never changed after it is saved.
@immutable
class JobEvidence {
  const JobEvidence({
    required this.id,
    required this.jobId,
    required this.milestone,
    required this.photoPaths,
    required this.capturedAt,
    this.note,
    this.latitude,
    this.longitude,
  });

  factory JobEvidence.fromJson(Map<String, dynamic> json) {
    return JobEvidence(
      id: json['id'] as String,
      jobId: json['job_id'] as String,
      milestone:
          EvidenceMilestone.fromWire(json['milestone']) ??
          EvidenceMilestone.progress,
      photoPaths: <String>[
        for (final Object? p in (json['photo_paths'] as List<dynamic>? ?? const <dynamic>[]))
          if (p is String) p,
      ],
      note: json['note'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      // Set by the database, in UTC.
      capturedAt: DateTime.parse(json['captured_at'] as String).toLocal(),
    );
  }

  final String id;
  final String jobId;
  final EvidenceMilestone milestone;
  final List<String> photoPaths;
  final String? note;
  final double? latitude;
  final double? longitude;
  final DateTime capturedAt;

  bool get hasLocation => latitude != null && longitude != null;

  /// Straight-line km from ([lat], [lng]), or null when either is unknown.
  double? distanceKmFrom(double? lat, double? lng) {
    if (!hasLocation || lat == null || lng == null) return null;
    const double r = 6371;
    double rad(double d) => d * math.pi / 180;
    final double dLat = rad(lat - latitude!);
    final double dLng = rad(lng - longitude!);
    final double a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(latitude!)) *
            math.cos(rad(lat)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.min(1, math.sqrt(a)));
  }

  /// "At the job address", "2.4 km from the job address", or "Location not
  /// recorded" - the location stamp as a person reads it.
  String locationStamp(double? jobLat, double? jobLng) {
    if (!hasLocation) return 'Location not recorded';
    final double? km = distanceKmFrom(jobLat, jobLng);
    if (km == null) return 'Location recorded';
    if (km < 0.2) return 'At the job address';
    return '${km < 10 ? km.toStringAsFixed(1) : km.round()} km from the job address';
  }
}

/// Which required steps a list of records still lacks, for a job of [path].
/// The server's `job_evidence_missing()` is the authority; this mirrors it
/// for the checklist while a reload is in flight.
List<EvidenceMilestone> missingRequired(List<JobEvidence> evidence) {
  final Set<EvidenceMilestone> have = <EvidenceMilestone>{
    for (final JobEvidence e in evidence) e.milestone,
  };
  return <EvidenceMilestone>[
    for (final EvidenceMilestone m in EvidenceMilestone.values)
      if (m.required && !have.contains(m)) m,
  ];
}
