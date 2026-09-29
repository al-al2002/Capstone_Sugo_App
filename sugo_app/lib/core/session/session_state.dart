/// The account's role, and where that role should land after login.
///
/// This file holds the *rule*; `SessionController` holds the *data*; `AuthGate`
/// renders the result. Splitting it this way is what keeps the routing decision
/// in one place. No screen anywhere else is allowed to ask "am I a technician?"
/// and branch on the answer.
library;

/// Mirrors the `profiles.role` check constraint.
enum UserRole {
  client('client'),
  technician('technician');

  const UserRole(this.wire);

  final String wire;

  /// Anything unrecognised is treated as a client. A malformed role must not
  /// grant technician access, and the client dashboard is the safe default.
  static UserRole fromWire(String? value) {
    return value == 'technician' ? UserRole.technician : UserRole.client;
  }
}

/// Where the app should send the current user.
enum LandingDestination {
  /// Session is still being restored, or the profile is still loading.
  loading,

  /// No session. Show the login / register screen.
  auth,

  /// Signed in with no `profiles` row. Should be unreachable since
  /// 20260907000001 restored the sign-up trigger, but kept as the safe landing
  /// for a row that failed to create - starting the flow beats a blank screen.
  registration,

  /// Registration is unfinished and no role has been chosen yet.
  roleSelection,

  /// `role = 'technician'`, registration unfinished or rejected.
  technicianRegistration,

  /// `role = 'client'`, registration unfinished or rejected.
  clientRegistration,

  /// Everything required was submitted and an admin has yet to rule. Both
  /// roles land here; there is nothing for the user to do.
  pendingReview,

  /// Approved, able to use the app, and signing in for the first time since.
  /// A one-time step for a profile photo and, for technicians, the workshop.
  ///
  /// Only reached by accounts approved AFTER the step was introduced: the
  /// migration that added it (20260917000003) marked every account that was
  /// already active as done, so nobody established is stopped at sign-in.
  profileSetup,

  /// `role = 'client'` and an admin approved their identity.
  clientDashboard,

  /// `role = 'technician'`, approved on identity but not yet cleared to work -
  /// no `technicians` row, or `is_verified` still false.
  technicianOnboarding,

  /// `role = 'technician'` and `is_verified = true`.
  technicianDashboard,
}

/// Everything the routing decision needs, in one immutable value.
class SessionProfile {
  const SessionProfile({
    required this.userId,
    required this.role,
    this.fullName,
    this.avatarUrl,
    this.phone,
    this.hasTechnicianRow = false,
    this.isVerified = false,
    this.roleChosenAt,
    this.onboardingCompletedAt,
    this.idDocumentUrl,
    this.specialization = const <String>[],
    this.registrationStatus = 'incomplete',
    this.profileSetupCompletedAt,
  });

  final String userId;
  final UserRole role;
  final String? fullName;
  final String? avatarUrl;
  final String? phone;

  /// False when `role = 'technician'` but no `technicians` row exists yet -
  /// the state a technician is in between registering and finishing
  /// onboarding.
  final bool hasTechnicianRow;

  /// `technicians.is_verified`. Set by SUGO staff, never by the technician.
  final bool isVerified;

  /// When the user explicitly picked a role. Null means the role selection
  /// screen has not been completed yet.
  final DateTime? roleChosenAt;

  /// When registration was first completed. Null means the account is still
  /// mid-signup and is eligible for automatic cleanup.
  final DateTime? onboardingCompletedAt;

  /// `profiles.id_document_url`. Null until an ID has been submitted.
  final String? idDocumentUrl;

  /// What they qualified in, set when an assessment is passed.
  final List<String> specialization;

  /// `profiles.registration_status`: incomplete, pending_review, active or
  /// rejected.
  ///
  /// Held as the raw wire string rather than the `RegistrationStatus` enum
  /// from the onboarding feature, so this core session type stays independent
  /// of a feature module. [destination] is the only thing that reads it, and
  /// it treats anything unrecognised as unfinished.
  final String registrationStatus;

  /// When the one-time profile setup was finished or skipped. Null means it is
  /// still owed - see [LandingDestination.profileSetup].
  final DateTime? profileSetupCompletedAt;

  bool get owesProfileSetup => profileSetupCompletedAt == null;

  /// True once an admin has approved the account.
  bool get isRegistrationActive => registrationStatus == 'active';

  /// True while an admin has yet to rule on a submitted registration.
  bool get isAwaitingReview => registrationStatus == 'pending_review';

  /// True once the role selection screen has been answered.
  bool get hasChosenRole => roleChosenAt != null;

  /// True once registration is finished and the account is safe from the
  /// abandoned-signup purge.
  bool get hasCompletedOnboarding => onboardingCompletedAt != null;

  /// True once a government ID has been submitted.
  bool get hasSubmittedId => idDocumentUrl != null && idDocumentUrl!.isNotEmpty;

  bool get isTechnician => role == UserRole.technician;

  bool get isClient => role == UserRole.client;

  /// A technician who has been cleared to work.
  bool get canWork => isTechnician && hasTechnicianRow && isVerified;

  /// The single routing rule for the whole app.
  ///
  /// ## Why this reads `registrationStatus` first
  ///
  /// Before 20260907000001 a `profiles` row only existed once registration had
  /// finished, so merely reaching this method proved the account was complete
  /// and the role alone decided the destination.
  ///
  /// That is no longer true. The sign-up trigger creates the row immediately so
  /// the flow can be resumed, which means a profile now exists for someone who
  /// has done nothing at all. The status column is what distinguishes them, and
  /// checking it before the role is what stops a brand-new signup landing on a
  /// dashboard it has not earned.
  ///
  /// A technician who is approved on identity but not yet cleared to work is
  /// deliberately sent to onboarding rather than a disabled dashboard. A
  /// dashboard full of greyed-out sections implies the account is broken;
  /// onboarding tells them what is actually outstanding.
  LandingDestination get destination {
    switch (registrationStatus) {
      case 'pending_review':
        return LandingDestination.pendingReview;

      case 'incomplete':
      case 'rejected':
        // Role is chosen inside the flow, not at sign-up, so an unchosen role
        // has to be settled before either registration stepper can start.
        if (!hasChosenRole) return LandingDestination.roleSelection;
        return isTechnician
            ? LandingDestination.technicianRegistration
            : LandingDestination.clientRegistration;

      case 'active':
        break;

      default:
        // An unrecognised status is treated as unfinished. The strict
        // direction is the safe one: the failure mode of guessing wrong here
        // is an unverified account reaching a live dashboard.
        return LandingDestination.roleSelection;
    }

    if (isClient) {
      return owesProfileSetup
          ? LandingDestination.profileSetup
          : LandingDestination.clientDashboard;
    }

    // A technician whose verification is revoked later falls back here
    // automatically, because the destination is recomputed from live data on
    // every session refresh rather than latched at login.
    if (!canWork) return LandingDestination.technicianOnboarding;

    // Setup comes AFTER a technician is cleared to work, not before. Asking
    // someone to choose a workshop location for jobs they are not yet allowed
    // to take is asking them to do work that might never matter.
    return owesProfileSetup
        ? LandingDestination.profileSetup
        : LandingDestination.technicianDashboard;
  }

  /// Which onboarding step a technician is on. Read by
  /// `TechnicianOnboardingScreen`, which hosts the steps; the gate only
  /// decides *that* they are onboarding, not *where* within it.
  OnboardingStep get onboardingStep {
    if (!hasTechnicianRow || !hasSubmittedId) return OnboardingStep.idUpload;
    if (specialization.isEmpty) return OnboardingStep.specialization;
    return OnboardingStep.assessment;
  }

  String get displayName {
    final String? name = fullName?.trim();
    if (name == null || name.isEmpty) return 'there';
    return name.split(' ').first;
  }

  String get initials {
    final String? name = fullName?.trim();
    if (name == null || name.isEmpty) return '?';
    final List<String> parts = name.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

/// The ordered steps a technician passes through before the dashboard opens.
enum OnboardingStep {
  /// Upload a government ID. Creates the `technicians` row.
  idUpload,

  /// Choose what they repair. Drives which question bank the quiz pulls.
  specialization,

  /// Take the quiz. Passing auto-sets tier and `is_verified`.
  assessment,
}
