import 'package:flutter/material.dart';

import '../../rb_cars/models/json_utils.dart';

/// Why a problem is being reported. Mirrors the `job_disputes.reason` check.
///
/// Each side is offered only the reasons that make sense from where they
/// stand: a technician cannot say the repair was not fixed, and a client
/// cannot say they were not paid.
enum DisputeReason {
  notFixed('not_fixed', 'The problem was not fixed', Icons.build_circle_outlined,
      client: true),
  overcharged('overcharged', 'I was charged more than agreed',
      Icons.payments_outlined, client: true),
  noShow('no_show', 'They did not show up', Icons.event_busy_outlined,
      client: true, technician: true),
  damage('damage', 'Something was damaged', Icons.broken_image_outlined,
      client: true),
  conduct('conduct', 'Rude or unsafe behaviour', Icons.report_outlined,
      client: true, technician: true),
  payment('payment', 'I was not paid', Icons.money_off_rounded,
      technician: true),
  other('other', 'Something else', Icons.more_horiz_rounded,
      client: true, technician: true);

  const DisputeReason(
    this.wire,
    this.label,
    this.icon, {
    this.client = false,
    this.technician = false,
  });

  final String wire;
  final String label;
  final IconData icon;
  final bool client;
  final bool technician;

  /// The reasons one side is offered, in the order above.
  static List<DisputeReason> forRole({required bool isClient}) =>
      DisputeReason.values
          .where((DisputeReason r) => isClient ? r.client : r.technician)
          .toList(growable: false);

  static DisputeReason fromWire(String? value) => DisputeReason.values
      .firstWhere((DisputeReason r) => r.wire == value, orElse: () => other);
}

/// Where a report is. Mirrors the `job_disputes.status` check.
enum DisputeStatus {
  open('open', 'Under review'),
  resolved('resolved', 'Resolved'),
  dismissed('dismissed', 'Closed');

  const DisputeStatus(this.wire, this.label);

  final String wire;
  final String label;

  static DisputeStatus fromWire(String? value) => DisputeStatus.values
      .firstWhere((DisputeStatus s) => s.wire == value, orElse: () => open);
}

/// One row of `job_disputes`: a problem reported on a job, and SUGO's
/// decision on it.
class JobDispute {
  const JobDispute({
    required this.id,
    required this.jobId,
    required this.raisedBy,
    required this.raisedByClient,
    required this.reason,
    required this.details,
    required this.status,
    this.photoPaths = const <String>[],
    this.resolutionNote,
    this.resolvedAt,
    this.createdAt,
  });

  factory JobDispute.fromJson(Map<String, dynamic> json) {
    return JobDispute(
      id: json['id'] as String,
      jobId: json['job_id'] as String,
      raisedBy: json['raised_by'] as String,
      raisedByClient: json['raised_by_role'] == 'client',
      reason: DisputeReason.fromWire(json['reason'] as String?),
      details: json['details'] as String? ?? '',
      status: DisputeStatus.fromWire(json['status'] as String?),
      photoPaths: asStringList(json['photo_paths']),
      resolutionNote: json['resolution_note'] as String?,
      resolvedAt: asDate(json['resolved_at']),
      createdAt: asDate(json['created_at']),
    );
  }

  final String id;
  final String jobId;
  final String raisedBy;

  /// True when the client reported it; false for the technician.
  final bool raisedByClient;

  final DisputeReason reason;
  final String details;
  final DisputeStatus status;
  final List<String> photoPaths;

  /// The admin's decision, shown word for word. Null while open.
  final String? resolutionNote;
  final DateTime? resolvedAt;
  final DateTime? createdAt;

  bool get isOpen => status == DisputeStatus.open;
}
