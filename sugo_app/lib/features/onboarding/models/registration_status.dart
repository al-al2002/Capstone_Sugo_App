import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// Mirrors the `profiles.registration_status` check constraint.
///
/// The account-level state machine. It is deliberately separate from
/// "which step is the user on": a technician can be on the documents step for
/// an hour and still be [incomplete], and someone in [pendingReview] is on no
/// step at all.
enum RegistrationStatus {
  /// Signed up, mandatory ID + selfie not yet submitted. The account exists so
  /// the flow can be resumed, but it can do nothing else.
  incomplete('incomplete'),

  /// Everything required has been submitted and an admin has yet to rule.
  pendingReview('pending_review'),

  /// An admin approved the identity. The account can trade.
  active('active'),

  /// An admin refused it. [IdentityVerification.adminNotes] says why, and the
  /// user may retake and resubmit.
  rejected('rejected');

  const RegistrationStatus(this.wire);

  final String wire;

  /// Anything unrecognised reads as [incomplete].
  ///
  /// The safe default in the strict direction: a malformed value must never
  /// resolve to [active], because that is the one value that unlocks the app.
  static RegistrationStatus fromWire(String? value) {
    for (final RegistrationStatus s in RegistrationStatus.values) {
      if (s.wire == value) return s;
    }
    return RegistrationStatus.incomplete;
  }

  bool get isActive => this == RegistrationStatus.active;

  bool get isAwaitingAdmin => this == RegistrationStatus.pendingReview;

  /// True while the user still has something to do. A rejection counts: they
  /// have to retake the photos.
  bool get needsUserAction =>
      this == RegistrationStatus.incomplete ||
      this == RegistrationStatus.rejected;

  String get label => switch (this) {
    RegistrationStatus.incomplete => 'Incomplete',
    RegistrationStatus.pendingReview => 'Pending review',
    RegistrationStatus.active => 'Active',
    RegistrationStatus.rejected => 'Needs attention',
  };

  String get blurb => switch (this) {
    RegistrationStatus.incomplete =>
      'Finish your registration to start using SUGO.',
    RegistrationStatus.pendingReview =>
      'Your ID is with our review team. This usually takes under a day.',
    RegistrationStatus.active => 'Your account is verified and active.',
    RegistrationStatus.rejected =>
      'We could not verify your ID. Check the note and submit again.',
  };

  Color get tone => switch (this) {
    RegistrationStatus.incomplete => AppColors.textSecondary,
    RegistrationStatus.pendingReview => AppColors.warning,
    RegistrationStatus.active => AppColors.success,
    RegistrationStatus.rejected => AppColors.error,
  };

  IconData get icon => switch (this) {
    RegistrationStatus.incomplete => Icons.hourglass_empty_rounded,
    RegistrationStatus.pendingReview => Icons.schedule_rounded,
    RegistrationStatus.active => Icons.verified_rounded,
    RegistrationStatus.rejected => Icons.error_outline_rounded,
  };
}

/// A step in either onboarding stepper.
///
/// One enum covers both roles rather than two, because the steps they share -
/// account info, identity, location, review - are genuinely the same step and
/// resume through the same `profiles.registration_step` column. Which subset
/// applies is decided by [technicianFlow] and [clientFlow] below.
enum OnboardingStepId {
  account('account', 'Account', Icons.person_outline_rounded),
  identity('identity', 'ID check', Icons.badge_outlined),

  // Technician only.
  specialization('specialization', 'Skills', Icons.handyman_outlined),
  assessment('assessment', 'Assessment', Icons.quiz_outlined),
  documents('documents', 'Documents', Icons.folder_open_rounded),

  // Client only.
  email('email', 'Email code', Icons.mark_email_read_outlined),

  location('location', 'Location', Icons.place_outlined),
  review('review', 'Review', Icons.fact_check_outlined);

  const OnboardingStepId(this.wire, this.label, this.icon);

  /// Stored in `profiles.registration_step` so the flow can resume here.
  final String wire;

  final String label;

  /// Shown on the progress rail.
  ///
  /// Carried on the enum rather than mapped in the widget so a new step cannot
  /// be added without deciding what it looks like - and so the stepper never
  /// has to branch on which step it is drawing.
  final IconData icon;

  static OnboardingStepId? fromWire(String? value) {
    // Registrations saved under the SMS flow carry 'phone' in
    // `profiles.registration_step`. The contact step is email now, so they
    // resume on it rather than being dropped back to the start.
    if (value == 'phone') return OnboardingStepId.email;

    for (final OnboardingStepId s in OnboardingStepId.values) {
      if (s.wire == value) return s;
    }
    return null;
  }

  /// Technician stepper order, per the brief. The mandatory ID check sits at
  /// index 1 - immediately after account info - so no later step can be
  /// reached without passing it.
  static const List<OnboardingStepId> technicianFlow = <OnboardingStepId>[
    OnboardingStepId.account,
    OnboardingStepId.identity,
    OnboardingStepId.specialization,
    OnboardingStepId.assessment,
    OnboardingStepId.documents,
    OnboardingStepId.location,
    OnboardingStepId.review,
  ];

  /// Client stepper order. Same principle: identity is index 1.
  static const List<OnboardingStepId> clientFlow = <OnboardingStepId>[
    OnboardingStepId.account,
    OnboardingStepId.identity,
    OnboardingStepId.email,
    OnboardingStepId.location,
    OnboardingStepId.review,
  ];

  /// Steps that may be left and returned to later.
  ///
  /// [account] and [identity] are excluded on purpose. Everything before the
  /// mandatory ID check is what *creates* the resumable state, so there is
  /// nothing to save yet - and offering "continue later" on the identity step
  /// would imply the step is optional, which is the one thing this flow must
  /// never suggest.
  bool get allowsSaveAndExit =>
      this != OnboardingStepId.account && this != OnboardingStepId.identity;
}
