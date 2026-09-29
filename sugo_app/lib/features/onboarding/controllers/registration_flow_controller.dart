import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';

import '../../../core/session/session_state.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../models/identity_verification.dart';
import '../models/registration_status.dart';
import '../services/identity_verification_service.dart';

/// Shared behaviour for both onboarding flows.
///
/// ## What lives here and why
///
/// The mandatory ID + selfie step, the account status machine, and the
/// save-and-resume logic are identical for a technician and a client. Holding
/// them in a base class is the code-level expression of the requirement that
/// both roles face the same verification: there is exactly one implementation
/// of [canLeaveIdentityStep], so the two cannot drift.
///
/// Role-specific steps - specialisations and assessments, or phone and
/// addresses - live in the subclasses.
///
/// ## Progress is written as it goes
///
/// This reverses the deferred-write model of migration 20260906000006, which
/// held the whole registration in memory and committed once. That design could
/// not offer "save and continue later", because there was nothing stored to
/// resume from. Now each step persists its own rows and
/// `profiles.registration_status` records how far the account has got.
///
/// The cost, stated plainly: an abandoned registration leaves rows behind.
/// They are labelled `incomplete` and swept by `purge-abandoned-signups`
/// rather than being absent, which is a bookkeeping burden the previous design
/// did not have. That was the trade accepted in exchange for resumability.
abstract class RegistrationFlowController extends ChangeNotifier {
  RegistrationFlowController({IdentityVerificationService? identityService})
    : identity = identityService ?? IdentityVerificationService();

  final IdentityVerificationService identity;

  /// Which role this flow registers. Decides the step list and the value
  /// written to `identity_verifications.role`.
  UserRole get role;

  /// The ordered steps for this role.
  List<OnboardingStepId> get steps => role == UserRole.technician
      ? OnboardingStepId.technicianFlow
      : OnboardingStepId.clientFlow;

  // ---------------------------------------------------------------- state

  int _stepIndex = 0;
  RegistrationStatus _status = RegistrationStatus.incomplete;
  IdentityCapture _capture = const IdentityCapture();
  IdentityValidation _validation = const IdentityValidation.valid();
  IdentityVerification? _submission;

  bool _isLoading = false;
  bool _isBusy = false;
  String? _error;

  int get stepIndex => _stepIndex;

  OnboardingStepId get currentStep => steps[_stepIndex];

  RegistrationStatus get status => _status;

  IdentityCapture get capture => _capture;

  IdentityValidation get validation => _validation;

  /// The most recent submission, whatever its verdict.
  IdentityVerification? get submission => _submission;

  /// A rejection the user still has to answer, or null.
  IdentityVerification? get rejection =>
      _submission?.isRejected ?? false ? _submission : null;

  /// A submission waiting on an admin, or null.
  IdentityVerification? get pendingSubmission =>
      _submission?.isPending ?? false ? _submission : null;

  /// A filed attempt that is not a rejection - pending review or already
  /// approved.
  ///
  /// This, not [pendingSubmission], is what the identity step renders from. An
  /// approved attempt must also replace the pickers: the step is settled, and
  /// showing empty upload boxes to someone whose ID has been approved reads as
  /// "do it again".
  IdentityVerification? get filedSubmission =>
      (_submission != null && !_submission!.isRejected) ? _submission : null;

  /// True while the initial resume read is in flight.
  bool get isLoading => _isLoading;

  /// True while any write is in flight. Buttons gate on this.
  bool get isBusy => _isBusy;

  String? get error => _error;

  bool get isFirstStep => _stepIndex == 0;

  bool get isLastStep => _stepIndex == steps.length - 1;

  /// Steps the user has satisfied, for the progress rail.
  Set<OnboardingStepId> get completedSteps;

  /// Whether the current step's requirements are met.
  bool get canContinue;

  // ------------------------------------------------------- the identity gate

  /// The single rule that makes ID verification mandatory.
  ///
  /// Both images present, both valid, and nothing already queued. Every other
  /// part of the flow - the Continue button, the stepper's forward navigation,
  /// the final submit - consults this rather than re-deriving it, which is why
  /// there is no path around it.
  bool get canLeaveIdentityStep {
    // Already submitted: the step is satisfied and there is nothing to redo,
    // even though `capture` is empty on a resumed session.
    if (_submission != null && !_submission!.isRejected) return true;
    return _capture.isComplete && _validation.isValid;
  }

  /// True when identity has been dealt with, one way or another.
  bool get hasSubmittedIdentity =>
      _submission != null && !_submission!.isRejected;

  // ------------------------------------------------------------- lifecycle

  /// Reads saved progress and jumps to the right step.
  ///
  /// Called once when the flow opens. Subclasses override [loadRoleState] to
  /// add their own reads; this handles the parts common to both.
  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    try {
      final ({RegistrationStatus status, OnboardingStepId? step}) progress =
          await identity.loadProgress();

      _status = progress.status;
      _submission = await identity.latest();

      await loadRoleState();

      _stepIndex = _resumeIndex(progress.step);
    } on RbCarsFailure catch (failure) {
      _error = failure.message;
    } catch (error) {
      if (kDebugMode) debugPrint('RegistrationFlowController.load: $error');
      _error = 'Could not load your progress. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Role-specific reads, run during [load].
  @protected
  Future<void> loadRoleState() async {}

  /// Where to drop the user back in.
  ///
  /// A rejected identity always wins, whatever step was saved: nothing later
  /// in the flow matters until the photos are replaced, and landing someone on
  /// the documents step while their ID is rejected buries the one thing they
  /// have to act on.
  int _resumeIndex(OnboardingStepId? saved) {
    if (_submission?.isRejected ?? false) {
      return steps.indexOf(OnboardingStepId.identity);
    }

    if (saved == null) {
      // No saved step. If identity is already done, the account info step is
      // behind them; otherwise start at the gate.
      return hasSubmittedIdentity
          ? steps.indexOf(OnboardingStepId.identity) + 1
          : steps.indexOf(OnboardingStepId.identity);
    }

    final int index = steps.indexOf(saved);
    if (index < 0) return 0;

    // A saved step past the identity gate is only honoured if the gate was
    // actually passed. Otherwise the resume point would let someone re-enter
    // beyond a step they never completed.
    final int gate = steps.indexOf(OnboardingStepId.identity);
    if (index > gate && !hasSubmittedIdentity) return gate;

    return index;
  }

  // ------------------------------------------------------------- navigation

  void goToStep(int index) {
    if (index < 0 || index >= steps.length) return;

    // The gate, enforced on navigation as well as on Continue. Without this a
    // tap on the progress rail would walk straight past it.
    final int gate = steps.indexOf(OnboardingStepId.identity);
    if (index > gate && !canLeaveIdentityStep) return;

    _stepIndex = index;
    _error = null;
    notifyListeners();
  }

  Future<void> next() async {
    if (!canContinue || _isBusy) return;

    final bool saved = await persistCurrentStep();
    if (!saved) return;

    if (isLastStep) return;

    _stepIndex += 1;
    _error = null;
    notifyListeners();

    // Best-effort; a failed write costs a resume point, never the step itself.
    await identity.saveStep(currentStep);
  }

  void back() {
    if (isFirstStep) return;
    _stepIndex -= 1;
    _error = null;
    notifyListeners();
  }

  /// Writes whatever the current step collected. Returns false when the write
  /// failed, which keeps the user on the step with [error] set.
  @protected
  Future<bool> persistCurrentStep();

  /// Saves the resume point so the user can leave.
  Future<void> saveAndExit() async {
    await identity.saveStep(currentStep);
  }

  // -------------------------------------------------------------- identity

  /// Records a picked ID photo and validates it immediately.
  ///
  /// Validation runs on pick rather than on submit so the error appears beside
  /// the preview, while the user still has the camera in mind - not after a
  /// failed upload two steps later.
  Future<void> pickIdDocument(XFile file) async {
    _capture = _capture.copyWith(idDocument: file);
    _validation = _validation.copyWith(clearIdDocument: true);
    _error = null;
    notifyListeners();

    await _revalidate(file, isSelfie: false);
  }

  Future<void> pickSelfie(XFile file) async {
    _capture = _capture.copyWith(selfie: file);
    _validation = _validation.copyWith(clearSelfie: true);
    _error = null;
    notifyListeners();

    await _revalidate(file, isSelfie: true);
  }

  Future<void> _revalidate(XFile file, {required bool isSelfie}) async {
    final IdentityValidation result = await identity.validate(_capture);

    // Guard against a second pick landing while the first was being checked.
    final XFile? current = isSelfie ? _capture.selfie : _capture.idDocument;
    if (!identical(current, file)) return;

    _validation = result;
    notifyListeners();
  }

  /// Uploads both images and files the submission.
  ///
  /// Returns true on success. The step then becomes read-only - the pickers
  /// are replaced by a waiting panel - because an attempt under review cannot
  /// be edited.
  Future<bool> submitIdentity() async {
    if (!_capture.isComplete) {
      _error = _capture.missingLabel;
      notifyListeners();
      return false;
    }

    _isBusy = true;
    _error = null;
    notifyListeners();

    try {
      _submission = await identity.submit(capture: _capture, role: role);

      // The local files have served their purpose and are several megabytes
      // each; dropping them frees that and makes the panel render from the
      // submission rather than from stale local state.
      _capture = const IdentityCapture();
      _validation = const IdentityValidation.valid();
      return true;
    } on RbCarsFailure catch (failure) {
      _error = failure.message;
      return false;
    } catch (error) {
      if (kDebugMode) debugPrint('submitIdentity: $error');
      _error = 'Could not submit your ID. Please try again.';
      return false;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  /// Clears a rejected attempt so the user can retake.
  void startRetake() {
    _capture = const IdentityCapture();
    _validation = const IdentityValidation.valid();
    _submission = null;
    _error = null;
    _stepIndex = steps.indexOf(OnboardingStepId.identity);
    notifyListeners();
  }

  // ----------------------------------------------------------------- submit

  /// Files the finished registration for admin review.
  Future<bool> submitForReview() async {
    _isBusy = true;
    _error = null;
    notifyListeners();

    try {
      await performSubmit();
      _status = RegistrationStatus.pendingReview;
      return true;
    } on RbCarsFailure catch (failure) {
      _error = failure.message;
      return false;
    } catch (error) {
      if (kDebugMode) debugPrint('submitForReview: $error');
      _error = 'Could not submit your registration. Please try again.';
      return false;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  /// The role-specific submit call.
  @protected
  Future<void> performSubmit();

  // ----------------------------------------------------------------- errors

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  @protected
  void setError(String? message) {
    _error = message;
    notifyListeners();
  }

  @protected
  Future<T?> guard<T>(Future<T> Function() action) async {
    _isBusy = true;
    _error = null;
    notifyListeners();

    try {
      return await action();
    } on RbCarsFailure catch (failure) {
      _error = failure.message;
      return null;
    } catch (error) {
      if (kDebugMode) debugPrint('RegistrationFlowController.guard: $error');
      _error = 'Something went wrong. Please try again.';
      return null;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }
}
