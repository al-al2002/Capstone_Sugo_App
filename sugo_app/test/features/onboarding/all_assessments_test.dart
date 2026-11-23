import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/features/onboarding/controllers/technician_registration_controller.dart';
import 'package:sugo_app/features/onboarding/models/registration_status.dart';
import 'package:sugo_app/features/onboarding/models/specialization_catalog.dart';
import 'package:sugo_app/features/onboarding/models/travel_conditions.dart';
import 'package:sugo_app/features/onboarding/models/verification_document.dart';
import 'package:sugo_app/features/onboarding/services/identity_verification_service.dart';
import 'package:sugo_app/features/onboarding/services/technician_registration_service.dart';

/// Every skill assessment must be passed before a technician can move on
/// (2026-11-22, migration 20261122000003) - one pass used to be enough. A
/// technician who fails one can remove that skill instead of waiting 24 hours,
/// but never their only one.
void main() {
  const TechnicianSpecialization laptop = TechnicianSpecialization(
    category: ServiceCategory.itDevice,
    deviceType: 'laptop',
    brand: 'Dell',
    id: 's1',
  );
  const TechnicianSpecialization aircon = TechnicianSpecialization(
    category: ServiceCategory.appliance,
    deviceType: 'aircon',
    brand: 'LG',
    id: 's2',
  );

  PendingAssessment track(AssessmentTrack t, {bool passed = false, int attempts = 0}) =>
      PendingAssessment(
        track: t,
        specializationCount: 1,
        verifiedCount: passed ? 1 : 0,
        attemptCount: attempts,
      );

  Future<TechnicianRegistrationController> controllerWith(_FakeService service) async {
    final TechnicianRegistrationController c = TechnicianRegistrationController(
      service: service,
      identityService: _FakeIdentity(),
    );
    await c.loadRoleState();
    return c;
  }

  test('one of two passed is no longer enough', () async {
    final TechnicianRegistrationController c = await controllerWith(
      _FakeService(
        specs: <TechnicianSpecialization>[laptop, aircon],
        assessments: <PendingAssessment>[
          track(AssessmentTrack.computerRepair, passed: true, attempts: 1),
          track(AssessmentTrack.refrigeration, attempts: 1),
        ],
      ),
    );
    addTearDown(c.dispose);
    expect(c.hasPassedAnyAssessment, isTrue);
    expect(c.hasPassedAllAssessments, isFalse);
    expect(c.completedSteps, isNot(contains(OnboardingStepId.assessment)));
  });

  test('all passed lets them continue', () async {
    final TechnicianRegistrationController c = await controllerWith(
      _FakeService(
        specs: <TechnicianSpecialization>[laptop, aircon],
        assessments: <PendingAssessment>[
          track(AssessmentTrack.computerRepair, passed: true, attempts: 1),
          track(AssessmentTrack.refrigeration, passed: true, attempts: 2),
        ],
      ),
    );
    addTearDown(c.dispose);
    expect(c.hasPassedAllAssessments, isTrue);
    expect(c.completedSteps, contains(OnboardingStepId.assessment));
  });

  test('removing the failed skill keeps the passed one and unlocks the step', () async {
    final _FakeService service = _FakeService(
      specs: <TechnicianSpecialization>[laptop, aircon],
      assessments: <PendingAssessment>[
        track(AssessmentTrack.computerRepair, passed: true, attempts: 1),
        track(AssessmentTrack.refrigeration, attempts: 1),
      ],
    );
    final TechnicianRegistrationController c = await controllerWith(service);
    addTearDown(c.dispose);

    expect(c.isOnlyTrack(AssessmentTrack.refrigeration), isFalse);
    final bool removed = await c.removeTrack(AssessmentTrack.refrigeration);

    expect(removed, isTrue);
    expect(service.saved?.map((TechnicianSpecialization s) => s.deviceType), <String>['laptop']);
    expect(c.selected.map((TechnicianSpecialization s) => s.deviceType), <String>['laptop']);
    expect(c.hasPassedAllAssessments, isTrue);
  });

  test('their only skill cannot be removed', () async {
    final _FakeService service = _FakeService(
      specs: <TechnicianSpecialization>[aircon],
      assessments: <PendingAssessment>[track(AssessmentTrack.refrigeration, attempts: 1)],
    );
    final TechnicianRegistrationController c = await controllerWith(service);
    addTearDown(c.dispose);

    expect(c.isOnlyTrack(AssessmentTrack.refrigeration), isTrue);
    expect(await c.removeTrack(AssessmentTrack.refrigeration), isFalse);
    expect(service.saved, isNull, reason: 'nothing was written');
  });
}

/// Stands in for the registration service: specialisations and assessments
/// in memory, and removing a track drops its assessment.
class _FakeService implements TechnicianRegistrationService {
  _FakeService({required this.specs, required this.assessments});

  List<TechnicianSpecialization> specs;
  List<PendingAssessment> assessments;
  List<TechnicianSpecialization>? saved;

  @override
  Future<List<TechnicianSpecialization>> loadSpecializations() async => specs;

  @override
  Future<List<PendingAssessment>> loadAssessments() async => assessments;

  @override
  Future<List<VerificationDocument>> loadDocuments() async => const <VerificationDocument>[];

  @override
  Future<({double? latitude, double? longitude, double radiusKm})> loadBaseLocation() async =>
      (latitude: null, longitude: null, radiusKm: 10.0);

  @override
  Future<
    ({
      bool homeService,
      bool shopRepair,
      String? shopName,
      double? shopLatitude,
      double? shopLongitude,
      RainTravel? rainTravel,
      TrafficTravel? trafficTravel,
    })
  >
  loadWorkType() async => (
    homeService: true,
    shopRepair: true,
    shopName: null,
    shopLatitude: null,
    shopLongitude: null,
    rainTravel: null,
    trafficTravel: null,
  );

  @override
  Future<List<TechnicianSpecialization>> saveSpecializations(
    List<TechnicianSpecialization> selection,
  ) async {
    saved = selection;
    specs = selection;
    final Set<AssessmentTrack?> kept = selection
        .map((TechnicianSpecialization s) => s.track)
        .toSet();
    assessments = assessments
        .where((PendingAssessment a) => kept.contains(a.track))
        .toList();
    return selection;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeIdentity implements IdentityVerificationService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
