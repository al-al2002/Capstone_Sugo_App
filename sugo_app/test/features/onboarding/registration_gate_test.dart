import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/session/session_state.dart';
import 'package:sugo_app/features/onboarding/models/identity_verification.dart';
import 'package:sugo_app/features/onboarding/models/registration_status.dart';
import 'package:sugo_app/features/onboarding/models/specialization_catalog.dart';
import 'package:sugo_app/features/onboarding/services/client_registration_service.dart';

/// Tests for the rules that decide whether an account may proceed.
///
/// These four groups are the pieces where a mistake is silent and expensive:
/// a broken gate lets an unverified account through, and broken routing sends
/// a brand-new signup to a live dashboard. Both are the kind of bug that only
/// shows up in front of a panel.

SessionProfile _profile({
  required String status,
  UserRole role = UserRole.client,
  DateTime? roleChosenAt,
  bool hasTechnicianRow = false,
  bool isVerified = false,
  bool profileSetupDone = true,
}) {
  return SessionProfile(
    userId: 'user-1',
    role: role,
    registrationStatus: status,
    roleChosenAt: roleChosenAt ?? DateTime(2026, 9, 7),
    hasTechnicianRow: hasTechnicianRow,
    isVerified: isVerified,
    // Defaults to done: the accounts in the older groups below are established
    // ones, which is exactly what 20260917000003 marked complete. The profile
    // setup group opts out explicitly.
    profileSetupCompletedAt: profileSetupDone ? DateTime(2026, 9, 10) : null,
  );
}

void main() {
  group('IdentityCapture — the mandatory two-part gate', () {
    final XFile file = XFile('id.jpg');

    test('is incomplete until both the ID and the selfie are present', () {
      expect(const IdentityCapture().isComplete, isFalse);
      expect(IdentityCapture(idDocument: file).isComplete, isFalse);
      expect(IdentityCapture(selfie: file).isComplete, isFalse);
      expect(
        IdentityCapture(idDocument: file, selfie: file).isComplete,
        isTrue,
      );
    });

    test('reports which half is missing, so the prompt can be specific', () {
      expect(
        IdentityCapture(idDocument: file).missingLabel,
        contains('selfie'),
      );
      expect(IdentityCapture(selfie: file).missingLabel, contains('ID'));
      expect(
        IdentityCapture(idDocument: file, selfie: file).missingLabel,
        isNull,
      );
    });

    test('one half present is "partial", the state worth nudging on', () {
      expect(IdentityCapture(idDocument: file).isPartial, isTrue);
      expect(const IdentityCapture().isPartial, isFalse);
      expect(
        IdentityCapture(idDocument: file, selfie: file).isPartial,
        isFalse,
      );
    });
  });

  group('SessionProfile.destination — status gates the role', () {
    test('a brand-new signup does not reach a dashboard', () {
      // The regression this guards: restoring the sign-up trigger means a
      // profile row now exists immediately, so routing on role alone would
      // send every new account straight to the client dashboard.
      expect(
        _profile(status: 'incomplete').destination,
        isNot(LandingDestination.clientDashboard),
      );
    });

    test('an unchosen role goes to role selection', () {
      expect(
        _profile(
          status: 'incomplete',
          roleChosenAt: DateTime(0),
        ).destination,
        isNot(LandingDestination.clientDashboard),
      );

      final SessionProfile undecided = SessionProfile(
        userId: 'u',
        role: UserRole.client,
        registrationStatus: 'incomplete',
      );
      expect(undecided.destination, LandingDestination.roleSelection);
    });

    test('an unfinished account goes to its own registration flow', () {
      expect(
        _profile(status: 'incomplete', role: UserRole.client).destination,
        LandingDestination.clientRegistration,
      );
      expect(
        _profile(status: 'incomplete', role: UserRole.technician).destination,
        LandingDestination.technicianRegistration,
      );
    });

    test('a rejection routes back into the flow, not to a dashboard', () {
      expect(
        _profile(status: 'rejected', role: UserRole.client).destination,
        LandingDestination.clientRegistration,
      );
    });

    test('pending review is a waiting room for both roles', () {
      expect(
        _profile(status: 'pending_review').destination,
        LandingDestination.pendingReview,
      );
      expect(
        _profile(
          status: 'pending_review',
          role: UserRole.technician,
        ).destination,
        LandingDestination.pendingReview,
      );
    });

    test('an active client reaches the dashboard', () {
      expect(
        _profile(status: 'active').destination,
        LandingDestination.clientDashboard,
      );
    });

    test('an active technician still needs is_verified to work', () {
      expect(
        _profile(
          status: 'active',
          role: UserRole.technician,
          hasTechnicianRow: true,
        ).destination,
        LandingDestination.technicianOnboarding,
      );

      expect(
        _profile(
          status: 'active',
          role: UserRole.technician,
          hasTechnicianRow: true,
          isVerified: true,
        ).destination,
        LandingDestination.technicianDashboard,
      );
    });

    test('an unrecognised status fails closed, never to a dashboard', () {
      expect(
        _profile(status: 'something_new').destination,
        LandingDestination.roleSelection,
      );
    });
  });

  group('SkillLevel bands — mirrors assessment_skill_level()', () {
    test('90 and above is expert', () {
      expect(SkillLevel.fromScore(100), SkillLevel.expert);
      expect(SkillLevel.fromScore(90), SkillLevel.expert);
    });

    test('70 to 89 is intermediate', () {
      expect(SkillLevel.fromScore(89.9), SkillLevel.intermediate);
      expect(SkillLevel.fromScore(70), SkillLevel.intermediate);
    });

    test('below 70 awards no level at all', () {
      expect(SkillLevel.fromScore(69.9), isNull);
      expect(SkillLevel.fromScore(0), isNull);
    });
  });

  group('ClientRegistrationService.normalizePhone', () {
    test('accepts the three formats people actually type', () {
      const String expected = '+639171234567';
      expect(ClientRegistrationService.normalizePhone('09171234567'), expected);
      expect(
        ClientRegistrationService.normalizePhone('+639171234567'),
        expected,
      );
      expect(
        ClientRegistrationService.normalizePhone('639171234567'),
        expected,
      );
      expect(ClientRegistrationService.normalizePhone('9171234567'), expected);
    });

    test('tolerates the spaces and dashes people paste in', () {
      expect(
        ClientRegistrationService.normalizePhone('0917 123 4567'),
        '+639171234567',
      );
      expect(
        ClientRegistrationService.normalizePhone('0917-123-4567'),
        '+639171234567',
      );
    });

    test('rejects a wrong length, prefix or a landline', () {
      expect(ClientRegistrationService.normalizePhone(''), isNull);
      expect(ClientRegistrationService.normalizePhone('0917123456'), isNull);
      expect(ClientRegistrationService.normalizePhone('081712345678'), isNull);
      // A Davao landline is not a mobile number and cannot receive an SMS.
      expect(ClientRegistrationService.normalizePhone('0822271234'), isNull);
    });
  });

  group('AssessmentTrack — one assessment per skill, not per brand', () {
    test('laptop and desktop share a track', () {
      // The point the whole grouping exists for: they are the same repair, so
      // they must not be two separate quizzes.
      expect(
        AssessmentTrack.forDevice('laptop'),
        AssessmentTrack.forDevice('desktop'),
      );
      expect(
        AssessmentTrack.forDevice('laptop'),
        AssessmentTrack.computerRepair,
      );
    });

    test('phone and tablet share a track', () {
      expect(
        AssessmentTrack.forDevice('smartphone'),
        AssessmentTrack.forDevice('tablet'),
      );
    });

    test('aircon and refrigerator share a track — both sealed systems', () {
      expect(
        AssessmentTrack.forDevice('aircon'),
        AssessmentTrack.forDevice('refrigerator'),
      );
      expect(
        AssessmentTrack.forDevice('aircon'),
        AssessmentTrack.refrigeration,
      );
    });

    test('genuinely different repairs stay apart', () {
      expect(
        AssessmentTrack.forDevice('laptop'),
        isNot(AssessmentTrack.forDevice('aircon')),
      );
      expect(
        AssessmentTrack.forDevice('printer'),
        isNot(AssessmentTrack.forDevice('laptop')),
      );
    });

    test('every catalogue device belongs to a track', () {
      // A device with no track has no question bank, so a technician who picks
      // it can never pass an assessment and can never finish registering. That
      // exact dead end existed before tracks were introduced.
      for (final DeviceType device in SpecializationCatalog.devices) {
        expect(
          device.track,
          isNotNull,
          reason: '${device.wire} has no assessment track',
        );
      }
    });

    test('the Dart mapping matches assessment_track() in SQL', () {
      // Duplicated on purpose - the UI groups the list without a round trip -
      // so this pins the two copies together.
      const Map<String, AssessmentTrack> sql = <String, AssessmentTrack>{
        'laptop': AssessmentTrack.computerRepair,
        'desktop': AssessmentTrack.computerRepair,
        'smartphone': AssessmentTrack.mobileRepair,
        'tablet': AssessmentTrack.mobileRepair,
        'printer': AssessmentTrack.printerRepair,
        'aircon': AssessmentTrack.refrigeration,
        'refrigerator': AssessmentTrack.refrigeration,
        'washing_machine': AssessmentTrack.laundryAppliance,
        'television': AssessmentTrack.homeElectronics,
        'microwave': AssessmentTrack.homeElectronics,
        'router': AssessmentTrack.networkSurveillance,
        'cctv': AssessmentTrack.networkSurveillance,
      };

      sql.forEach((String device, AssessmentTrack expected) {
        expect(AssessmentTrack.forDevice(device), expected, reason: device);
      });
    });

    test('an unknown device gets no track rather than a wrong one', () {
      expect(AssessmentTrack.forDevice('flux_capacitor'), isNull);
    });
  });

  group('OnboardingStepId — the flows put identity second', () {
    test('the ID check sits immediately after account info in both flows', () {
      expect(OnboardingStepId.technicianFlow[1], OnboardingStepId.identity);
      expect(OnboardingStepId.clientFlow[1], OnboardingStepId.identity);
    });

    test('save-and-exit is offered only after the gate', () {
      expect(OnboardingStepId.account.allowsSaveAndExit, isFalse);
      expect(OnboardingStepId.identity.allowsSaveAndExit, isFalse);
      expect(OnboardingStepId.specialization.allowsSaveAndExit, isTrue);
      expect(OnboardingStepId.location.allowsSaveAndExit, isTrue);
    });
  });

  group('SessionProfile.destination - one-time profile setup', () {
    test('a newly approved client is asked to set up their profile', () {
      expect(
        _profile(status: 'active', profileSetupDone: false).destination,
        LandingDestination.profileSetup,
      );
    });

    test('an established client goes straight to the dashboard', () {
      // The migration marked every already-active account complete, so this
      // is what everyone approved before the step existed looks like.
      expect(
        _profile(status: 'active').destination,
        LandingDestination.clientDashboard,
      );
    });

    test('an account still under review is never shown setup', () {
      for (final String status in <String>[
        'incomplete',
        'pending_review',
        'rejected',
      ]) {
        expect(
          _profile(status: status, profileSetupDone: false).destination,
          isNot(LandingDestination.profileSetup),
          reason: '$status is not approved yet',
        );
      }
    });

    test('a technician who cannot work yet is sent to onboarding first', () {
      // Asking for a workshop before they may take a single job would be work
      // that might never matter.
      expect(
        _profile(
          status: 'active',
          role: UserRole.technician,
          hasTechnicianRow: true,
          profileSetupDone: false,
        ).destination,
        LandingDestination.technicianOnboarding,
      );
    });

    test('a technician cleared to work gets setup, then the dashboard', () {
      final SessionProfile owes = _profile(
        status: 'active',
        role: UserRole.technician,
        hasTechnicianRow: true,
        isVerified: true,
        profileSetupDone: false,
      );
      expect(owes.destination, LandingDestination.profileSetup);

      expect(
        _profile(
          status: 'active',
          role: UserRole.technician,
          hasTechnicianRow: true,
          isVerified: true,
        ).destination,
        LandingDestination.technicianDashboard,
      );
    });
  });
}
