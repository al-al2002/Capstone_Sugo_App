import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// Mirrors `technician_verification_documents.doc_type`.
///
/// The NBI clearance is required; the other two are not. The split is between
/// safety and skill: a technician is let into somebody's home, and the
/// clearance is what the client is trusting when they open the door. A
/// certificate and a portfolio describe how good the work is, which raises
/// `verification_tier` rather than gating entry.
enum VerificationDocType {
  certificate(
    'certificate',
    'Certificate',
    'TESDA, vendor or training certificates.',
    Icons.workspace_premium_rounded,
  ),
  nbiClearance(
    'nbi_clearance',
    'NBI / Police clearance',
    'Reassures clients letting you into their home.',
    Icons.verified_user_rounded,
  ),
  portfolio(
    'portfolio',
    'Portfolio',
    'Photos of past repairs. Add as many as you like.',
    Icons.photo_library_rounded,
  );

  const VerificationDocType(this.wire, this.label, this.blurb, this.icon);

  final String wire;
  final String label;
  final String blurb;
  final IconData icon;

  /// Only the portfolio takes several files; the other two are a single
  /// document each, and offering "add another" for them invites confusion
  /// about which copy is the real one.
  bool get allowsMultiple => this == VerificationDocType.portfolio;

  /// Only portfolio items carry a caption.
  bool get allowsCaption => this == VerificationDocType.portfolio;

  static VerificationDocType? fromWire(String? value) {
    for (final VerificationDocType t in VerificationDocType.values) {
      if (t.wire == value) return t;
    }
    return null;
  }
}

/// Review state of an uploaded document.
enum DocumentStatus {
  pending('pending', 'In review', AppColors.warning),
  approved('approved', 'Approved', AppColors.success),
  rejected('rejected', 'Rejected', AppColors.error);

  const DocumentStatus(this.wire, this.label, this.tone);

  final String wire;
  final String label;
  final Color tone;

  static DocumentStatus fromWire(String? value) {
    for (final DocumentStatus s in DocumentStatus.values) {
      if (s.wire == value) return s;
    }
    return DocumentStatus.pending;
  }
}

/// A row of `technician_verification_documents`.
class VerificationDocument {
  const VerificationDocument({
    required this.id,
    required this.technicianId,
    required this.docType,
    required this.fileUrl,
    required this.status,
    required this.uploadedAt,
    this.caption,
    this.adminNotes,
    this.reviewedAt,
  });

  factory VerificationDocument.fromJson(Map<String, dynamic> json) {
    return VerificationDocument(
      id: json['id'] as String,
      technicianId: json['technician_id'] as String,
      docType:
          VerificationDocType.fromWire(json['doc_type'] as String?) ??
          VerificationDocType.certificate,
      fileUrl: json['file_url'] as String? ?? '',
      status: DocumentStatus.fromWire(json['status'] as String?),
      uploadedAt:
          DateTime.tryParse(json['uploaded_at'] as String? ?? '') ??
          DateTime.now(),
      caption: json['caption'] as String?,
      adminNotes: json['admin_notes'] as String?,
      reviewedAt: DateTime.tryParse(json['reviewed_at'] as String? ?? ''),
    );
  }

  final String id;
  final String technicianId;
  final VerificationDocType docType;

  /// Portfolio images live in the public `job-photos` bucket and this is a
  /// real URL. Certificates and clearances live in the private
  /// `identity-documents` bucket and this is an object path needing a signed
  /// URL. [isPublicUrl] tells them apart.
  final String fileUrl;

  final DocumentStatus status;
  final DateTime uploadedAt;
  final String? caption;
  final String? adminNotes;
  final DateTime? reviewedAt;

  /// Certificates and clearances are personal documents and are stored
  /// privately; portfolio work is promotional and is meant to be seen.
  bool get isPublicUrl => docType == VerificationDocType.portfolio;

  /// Only a document nobody has ruled on may be withdrawn - matching the
  /// `verification_documents_delete_pending` policy, so the UI does not offer
  /// a delete the database will refuse.
  bool get canDelete => status == DocumentStatus.pending;
}

/// The technician's overall verification badge.
///
/// Mirrors `technicians.verification_tier`. Distinct from `technicians.tier`,
/// which is the skill grade RB-CARS ranks on: this one describes how much
/// paperwork has been checked, not how good they are.
enum VerificationTier {
  basic('basic', 'Basic', 'Identity approved.'),
  verified('verified', 'Verified', 'Identity approved and assessment passed.'),
  certifiedPro(
    'certified_pro',
    'Certified Pro',
    'Identity, assessment, and approved credentials on file.',
  );

  const VerificationTier(this.wire, this.label, this.blurb);

  final String wire;
  final String label;
  final String blurb;

  static VerificationTier fromWire(String? value) {
    for (final VerificationTier t in VerificationTier.values) {
      if (t.wire == value) return t;
    }
    return VerificationTier.basic;
  }
}
