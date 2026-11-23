import '../../../core/session/session_state.dart';
import '../../technician/models/assessment.dart';
import '../models/client_onboarding_models.dart';
import '../models/registration_status.dart';
import '../models/specialization_catalog.dart';
import '../models/travel_conditions.dart';
import '../models/verification_document.dart';
import '../services/technician_registration_service.dart';
import 'registration_flow_controller.dart';

/// Drives the seven-step technician registration.
///
/// account -> ID + selfie -> specialisation -> assessment -> documents ->
/// work type -> location -> review
class TechnicianRegistrationController extends RegistrationFlowController {
  TechnicianRegistrationController({
    TechnicianRegistrationService? service,
    super.identityService,
  }) : _service = service ?? TechnicianRegistrationService();

  final TechnicianRegistrationService _service;

  @override
  UserRole get role => UserRole.technician;

  // ---------------------------------------------------------------- state

  List<TechnicianSpecialization> _selected = <TechnicianSpecialization>[];
  List<PendingAssessment> _assessments = <PendingAssessment>[];
  List<VerificationDocument> _documents = <VerificationDocument>[];

  GeoPlace? _basePlace;
  double _radiusKm = TechnicianRegistrationService.defaultRadiusKm;

  // Work type (2026-11-17). Both start off: the step is a choice, not a
  // default to accept.
  bool _homeService = false;
  bool _shopRepair = false;
  GeoPlace? _shopPlace;
  String _shopName = '';

  /// Saved as a deliberate choice - see [loadRoleState].
  bool _workTypeChosen = false;

  // Will they still travel in rain / heavy traffic (2026-11-22). Null until
  // answered; nothing is preselected.
  RainTravel? _rainTravel;
  TrafficTravel? _trafficTravel;

  List<TechnicianSpecialization> get selected =>
      List<TechnicianSpecialization>.unmodifiable(_selected);

  List<PendingAssessment> get assessments =>
      List<PendingAssessment>.unmodifiable(_assessments);

  List<VerificationDocument> get documents =>
      List<VerificationDocument>.unmodifiable(_documents);

  /// Whether an NBI or police clearance has been uploaded.
  ///
  /// The one document on this step that gates progress. It is the only one
  /// about *safety* rather than about skill: a technician is admitted to
  /// somebody's home, and the clearance is what the client is trusting when
  /// they open the door. A certificate and a portfolio say how good the work
  /// is, which is a different question and stays optional.
  ///
  /// A rejected upload does not count - it was looked at and refused - but a
  /// pending one does. Registration should not stall behind a review queue the
  /// technician cannot influence; the admin still has the final say at
  /// activation.
  bool get hasNbiClearance => _documents.any(
    (VerificationDocument d) =>
        d.docType == VerificationDocType.nbiClearance &&
        d.status != DocumentStatus.rejected,
  );

  GeoPlace? get basePlace => _basePlace;

  double get radiusKm => _radiusKm;

  /// Assessments still to pass.
  List<PendingAssessment> get outstandingAssessments =>
      _assessments.where((PendingAssessment a) => !a.isPassed).toList();

  List<PendingAssessment> get passedAssessments =>
      _assessments.where((PendingAssessment a) => a.isPassed).toList();

  /// At least one passed assessment. No longer what the step gates on (see
  /// [hasPassedAllAssessments]); kept for the wording on the step.
  bool get hasPassedAnyAssessment =>
      _assessments.any((PendingAssessment a) => a.isPassed);

  /// The rule the flow gates on since 2026-11-22: EVERY assessment passed.
  ///
  /// The user asked for it ("they answer all the assessment, not only one"),
  /// and the paper promises competency verification before a technician takes
  /// jobs - so every skill a technician lists must be proven. The server's
  /// `submit_registration_for_review()` applies the same rule
  /// (20261122000003), so an older build cannot submit with less.
  ///
  /// The cost the old rule avoided - being stranded behind a 24-hour retake
  /// cooldown for a skill added as an afterthought - is handled by
  /// [removeTrack]: a technician who fails one can drop that skill and carry
  /// on with the ones they passed.
  bool get hasPassedAllAssessments =>
      _assessments.isNotEmpty &&
      _assessments.every((PendingAssessment a) => a.isPassed);

  /// Whether [track] is the only skill group the technician picked, so it
  /// cannot be removed - there would be nothing left to register with.
  bool isOnlyTrack(AssessmentTrack track) => _selected.every(
    (TechnicianSpecialization s) => s.track == track,
  );

  /// Drops every specialisation in [track] - the way forward for a technician
  /// who failed its assessment and does not want to wait for the retake.
  /// Refused for their only track. True when it was removed.
  Future<bool> removeTrack(AssessmentTrack track) async {
    if (isOnlyTrack(track)) return false;
    final List<TechnicianSpecialization> remaining = _selected
        .where((TechnicianSpecialization s) => s.track != track)
        .toList();
    final List<TechnicianSpecialization>? saved = await guard(
      () => _service.saveSpecializations(remaining),
    );
    if (saved == null) return false;
    _selected = saved;
    _assessments = await _service.loadAssessments();
    notifyListeners();
    return true;
  }

  bool get hasBaseLocation => _basePlace != null;

  bool get homeService => _homeService;
  bool get shopRepair => _shopRepair;
  GeoPlace? get shopPlace => _shopPlace;
  String get shopName => _shopName;

  /// At least one kind of work, and the shop's pin when Shop Repair is on.
  bool get hasWorkType =>
      (_homeService || _shopRepair) && (!_shopRepair || _shopPlace != null);

  RainTravel? get rainTravel => _rainTravel;
  TrafficTravel? get trafficTravel => _trafficTravel;

  /// Both travel questions answered (2026-11-22).
  bool get hasTravelConditions => _rainTravel != null && _trafficTravel != null;

  /// What the work-type step needs before Continue: the work, and both
  /// travel answers.
  bool get canLeaveWorkTypeStep => hasWorkType && hasTravelConditions;

  /// "Even in heavy rain · Goes in heavy traffic", for the recap.
  String get travelConditionsLabel => hasTravelConditions
      ? '${_rainTravel!.shortLabel} · ${_trafficTravel!.shortLabel}'
      : 'Rain and traffic not answered';

  /// "Home Service and Shop Repair", for the recap.
  String get workTypeLabel => switch ((_homeService, _shopRepair)) {
    (true, true) => 'Home Service and Shop Repair',
    (true, false) => 'Home Service',
    (false, true) => 'Shop Repair',
    (false, false) => 'Not chosen',
  };

  // ------------------------------------------------------------- lifecycle

  @override
  Future<void> loadRoleState() async {
    _selected = await _service.loadSpecializations();
    _assessments = await _service.loadAssessments();
    _documents = await _service.loadDocuments();

    final ({double? latitude, double? longitude, double radiusKm}) base =
        await _service.loadBaseLocation();

    final ({
      bool homeService,
      bool shopRepair,
      String? shopName,
      double? shopLatitude,
      double? shopLongitude,
      RainTravel? rainTravel,
      TrafficTravel? trafficTravel,
    })
    work = await _service.loadWorkType();
    final bool hasShop =
        work.shopLatitude != null && work.shopLongitude != null;
    // The travel answers have no default, so either one being set means the
    // step was saved here before.
    final bool answeredTravel =
        work.rainTravel != null || work.trafficTravel != null;
    // The columns default to both, so "both with no shop" is an untouched
    // row, not a choice: show it unchosen. Anything else was saved here.
    _workTypeChosen =
        answeredTravel || !(work.homeService && work.shopRepair && !hasShop);
    _homeService = _workTypeChosen && work.homeService;
    _shopRepair = _workTypeChosen && work.shopRepair;
    _shopName = work.shopName ?? '';
    _rainTravel = work.rainTravel;
    _trafficTravel = work.trafficTravel;
    if (hasShop) {
      _shopPlace = GeoPlace(
        latitude: work.shopLatitude!,
        longitude: work.shopLongitude!,
        addressText: '',
      );
    }

    _radiusKm = base.radiusKm;
    if (base.latitude != null && base.longitude != null) {
      _basePlace = GeoPlace(
        latitude: base.latitude!,
        longitude: base.longitude!,
        // The address text is not stored for a technician base - only the
        // coordinates are, since the radius is what matters. The map step
        // re-resolves it if the user revisits.
        addressText: '',
      );
    }
  }

  @override
  Set<OnboardingStepId> get completedSteps {
    return <OnboardingStepId>{
      OnboardingStepId.account,
      if (hasSubmittedIdentity) OnboardingStepId.identity,
      if (_selected.isNotEmpty) OnboardingStepId.specialization,
      if (hasPassedAllAssessments) OnboardingStepId.assessment,
      if (hasNbiClearance) OnboardingStepId.documents,
      if (_workTypeChosen && canLeaveWorkTypeStep) OnboardingStepId.workType,
      if (hasBaseLocation) OnboardingStepId.location,
    };
  }

  @override
  bool get canContinue => switch (currentStep) {
    OnboardingStepId.account => true,
    OnboardingStepId.identity => canLeaveIdentityStep,
    OnboardingStepId.specialization => _selected.isNotEmpty,
    OnboardingStepId.assessment => hasPassedAllAssessments,
    OnboardingStepId.documents => hasNbiClearance,
    OnboardingStepId.workType => canLeaveWorkTypeStep,
    OnboardingStepId.location => hasBaseLocation,
    OnboardingStepId.review => true,
    OnboardingStepId.email => true, // Not in the technician flow.
  };

  @override
  Future<bool> persistCurrentStep() async {
    switch (currentStep) {
      case OnboardingStepId.specialization:
        final List<TechnicianSpecialization>? saved = await guard(
          () => _service.saveSpecializations(_selected),
        );
        if (saved == null) return false;
        _selected = saved;
        // Reload so newly saved rows carry their database ids - the assessment
        // step cannot submit without them.
        _assessments = await _service.loadAssessments();
        notifyListeners();
        return true;

      case OnboardingStepId.workType:
        if (!canLeaveWorkTypeStep) return false;
        final bool? saved = await guard<bool>(() async {
          await _service.saveWorkType(
            homeService: _homeService,
            shopRepair: _shopRepair,
            shopName: _shopName,
            shopLatitude: _shopPlace?.latitude,
            shopLongitude: _shopPlace?.longitude,
            rainTravel: _rainTravel,
            trafficTravel: _trafficTravel,
          );
          return true;
        });
        if (saved != true) return false;
        _workTypeChosen = true;
        // A shop-only technician works from the shop: their service area
        // starts there unless they already pinned a base.
        if (_basePlace == null && _shopRepair && _shopPlace != null) {
          _basePlace = _shopPlace;
        }
        notifyListeners();
        return true;

      case OnboardingStepId.location:
        final GeoPlace? place = _basePlace;
        if (place == null) return false;
        final bool? ok = await guard<bool>(() async {
          await _service.saveBaseLocation(
            latitude: place.latitude,
            longitude: place.longitude,
            radiusKm: _radiusKm,
            barangay: place.barangay,
          );
          return true;
        });
        return ok ?? false;

      // Every other step either writes as it goes (identity, assessments,
      // documents) or collects nothing that needs saving.
      case OnboardingStepId.account:
      case OnboardingStepId.identity:
      case OnboardingStepId.assessment:
      case OnboardingStepId.documents:
      case OnboardingStepId.review:
      case OnboardingStepId.email:
        return true;
    }
  }

  // -------------------------------------------------------- specialisations

  void setSelection(List<TechnicianSpecialization> selection) {
    _selected = selection;
    clearError();
    notifyListeners();
  }

  // ------------------------------------------------------------ assessments

  Future<List<AssessmentQuestion>?> loadQuestions(AssessmentTrack track) {
    return guard(() => _service.fetchQuestions(track));
  }

  /// Submits an attempt and refreshes the list.
  ///
  /// The refresh matters more now than it did: passing a track writes
  /// `skill_level` and `verified` on EVERY specialisation in that track, so a
  /// single submission can change six rows at once. Without the reload the
  /// review summary would still show them all as unproven.
  Future<AssessmentOutcome?> submitAssessment({
    required AssessmentTrack track,
    required Map<String, int> answers,
  }) async {
    final AssessmentOutcome? outcome = await guard(
      () => _service.submitAssessment(track: track, answers: answers),
    );

    if (outcome != null) {
      _selected = await _service.loadSpecializations();
      _assessments = await _service.loadAssessments();
      notifyListeners();
    }

    return outcome;
  }

  // -------------------------------------------------------------- documents

  Future<void> refreshDocuments() async {
    _documents = await _service.loadDocuments();
    notifyListeners();
  }

  TechnicianRegistrationService get service => _service;

  // -------------------------------------------------------------- work type

  void setHomeService(bool value) {
    _homeService = value;
    clearError();
    notifyListeners();
  }

  void setShopRepair(bool value) {
    _shopRepair = value;
    clearError();
    notifyListeners();
  }

  void setShopPlace(GeoPlace place) {
    _shopPlace = place;
    clearError();
    notifyListeners();
  }

  void setShopName(String value) {
    _shopName = value;
  }

  void setRainTravel(RainTravel value) {
    _rainTravel = value;
    clearError();
    notifyListeners();
  }

  void setTrafficTravel(TrafficTravel value) {
    _trafficTravel = value;
    clearError();
    notifyListeners();
  }

  // --------------------------------------------------------------- location

  void setBasePlace(GeoPlace place) {
    _basePlace = place;
    clearError();
    notifyListeners();
  }

  void setRadius(double km) {
    _radiusKm = km;
    notifyListeners();
  }

  // ----------------------------------------------------------------- submit

  @override
  Future<void> performSubmit() => _service.submitForReview();
}
