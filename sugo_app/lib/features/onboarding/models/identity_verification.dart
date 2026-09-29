import 'package:cross_file/cross_file.dart';

import '../../../core/session/session_state.dart';

/// The review state of one ID + selfie submission.
enum IdentityStatus {
  pending('pending'),
  approved('approved'),
  rejected('rejected');

  const IdentityStatus(this.wire);

  final String wire;

  static IdentityStatus fromWire(String? value) {
    for (final IdentityStatus s in IdentityStatus.values) {
      if (s.wire == value) return s;
    }
    return IdentityStatus.pending;
  }
}

/// A submitted attempt, as read back from `identity_verifications`.
class IdentityVerification {
  const IdentityVerification({
    required this.id,
    required this.userId,
    required this.role,
    required this.idDocumentPath,
    required this.selfiePath,
    required this.status,
    required this.submittedAt,
    this.adminNotes,
    this.reviewedAt,
  });

  factory IdentityVerification.fromJson(Map<String, dynamic> json) {
    return IdentityVerification(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      role: UserRole.fromWire(json['role'] as String?),
      idDocumentPath: json['id_document_url'] as String? ?? '',
      selfiePath: json['selfie_with_id_url'] as String? ?? '',
      status: IdentityStatus.fromWire(json['status'] as String?),
      submittedAt:
          DateTime.tryParse(json['submitted_at'] as String? ?? '') ??
          DateTime.now(),
      adminNotes: json['admin_notes'] as String?,
      reviewedAt: DateTime.tryParse(json['reviewed_at'] as String? ?? ''),
    );
  }

  final String id;
  final String userId;
  final UserRole role;

  /// Object paths in the private `identity-documents` bucket, not URLs.
  /// Rendering one requires a short-lived signed URL - see
  /// `IdentityVerificationService.signedUrl`.
  final String idDocumentPath;
  final String selfiePath;

  final IdentityStatus status;
  final DateTime submittedAt;
  final String? adminNotes;
  final DateTime? reviewedAt;

  bool get isPending => status == IdentityStatus.pending;

  bool get isApproved => status == IdentityStatus.approved;

  bool get isRejected => status == IdentityStatus.rejected;

  /// What to show the user on a rejection.
  ///
  /// Falls back to a generic line when a reviewer somehow left no note. The
  /// database refuses a note-less rejection, so this should be unreachable -
  /// but a user staring at a blank rejection screen is a worse failure than a
  /// slightly vague one.
  String get rejectionReason {
    final String? notes = adminNotes?.trim();
    if (notes == null || notes.isEmpty) {
      return 'Your ID could not be verified. Please submit clearer photos.';
    }
    return notes;
  }
}

/// The two images, held locally before they are uploaded.
///
/// A value type rather than two loose fields on the controller, because the
/// invariant this whole feature rests on - *both* parts or neither - is much
/// harder to break when it is expressed once, in [isComplete], than when it is
/// re-checked at every call site.
class IdentityCapture {
  const IdentityCapture({this.idDocument, this.selfie});

  /// Photo or scan of the government ID.
  final XFile? idDocument;

  /// Selfie of the person holding that same ID.
  final XFile? selfie;

  /// The gate. Nothing in either flow may advance past the identity step
  /// while this is false.
  bool get isComplete => idDocument != null && selfie != null;

  bool get isEmpty => idDocument == null && selfie == null;

  /// True when exactly one half is present - the state the UI has to nudge
  /// hardest on, because it looks like progress but submits to nothing.
  bool get isPartial => !isComplete && !isEmpty;

  /// What is still outstanding, phrased for a prompt.
  String? get missingLabel {
    if (isComplete) return null;
    if (idDocument == null && selfie == null) {
      return 'Add your ID photo and a selfie holding it.';
    }
    if (idDocument == null) return 'Add a photo of your government ID.';
    return 'Add a selfie holding your ID.';
  }

  IdentityCapture copyWith({
    XFile? idDocument,
    XFile? selfie,
    bool clearIdDocument = false,
    bool clearSelfie = false,
  }) {
    return IdentityCapture(
      idDocument: clearIdDocument ? null : (idDocument ?? this.idDocument),
      selfie: clearSelfie ? null : (selfie ?? this.selfie),
    );
  }
}

/// Per-image validation verdicts, so the two errors can be shown separately.
///
/// A single error string would have to say "one of your images is too large",
/// leaving the user to guess which. Keyed results let each picker carry its own
/// red border and message.
class IdentityValidation {
  const IdentityValidation({this.idDocumentError, this.selfieError});

  const IdentityValidation.valid() : idDocumentError = null, selfieError = null;

  final String? idDocumentError;
  final String? selfieError;

  bool get isValid => idDocumentError == null && selfieError == null;

  IdentityValidation copyWith({
    String? idDocumentError,
    String? selfieError,
    bool clearIdDocument = false,
    bool clearSelfie = false,
  }) {
    return IdentityValidation(
      idDocumentError: clearIdDocument
          ? null
          : (idDocumentError ?? this.idDocumentError),
      selfieError: clearSelfie ? null : (selfieError ?? this.selfieError),
    );
  }
}
