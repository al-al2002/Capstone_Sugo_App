import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/session/session_state.dart';
import '../../../rb_cars/services/rb_cars_service.dart';
import '../../../technician/models/assessment.dart';
import '../../../technician/services/onboarding_service.dart';

/// Which screen of the registration flow is showing.
enum RegistrationStep {
  /// Client or technician.
  role,

  /// Government ID. Held as a local file, not uploaded yet.
  identity,

  /// Technician only: what they repair.
  specialization,

  /// Technician only: the assessment.
  quiz,

  /// A failed attempt, with the score and a retry.
  failedResult,
}

/// Holds a registration in memory until it is finished, then commits it once.
///
/// ## Why nothing is written as you go
///
/// Every step used to write immediately - role selection updated `profiles`,
/// the ID step created a `technicians` row, the quiz inserted an attempt. Any
/// abandonment left that trail behind.
///
/// Now the answers live here, in memory, and a single call to
/// `complete-registration` writes every row inside one database transaction at
/// the end. An abandoned registration touches no table at all.
///
/// ## The consequence, stated plainly
///
/// **A half-finished registration cannot be resumed.** Close the app at the
/// quiz and you start again from role selection, because there is nothing
/// stored to resume from. That is the direct cost of the requirement, not an
/// oversight. The previous design resumed exactly where you left off precisely
/// because it wrote each step as it went.
///
/// The `auth.users` row still exists from sign-up - Storage and every RLS
/// policy need `auth.uid()` before an ID can be uploaded - and is swept later
/// by `purge-abandoned-signups` if the person never returns.
class RegistrationController extends ChangeNotifier {
  RegistrationController({OnboardingService? service})
    : _service = service ?? OnboardingService();

  final OnboardingService _service;

  // ------------------------------------------------------------- the draft

  UserRole? _role;
  XFile? _idFile;
  Specialization? _specialization;
  Map<String, int> _answers = <String, int>{};

  UserRole? get role => _role;
  XFile? get idFile => _idFile;
  Specialization? get specialization => _specialization;
  Map<String, int> get answers => Map<String, int>.unmodifiable(_answers);

  // ------------------------------------------------------------- flow state

  RegistrationStep _step = RegistrationStep.role;
  AssessmentResult? _failedResult;
  bool _isSubmitting = false;
  String? _error;
  String? _idValidationError;

  RegistrationStep get step => _step;
  AssessmentResult? get failedResult => _failedResult;
  bool get isSubmitting => _isSubmitting;
  String? get error => _error;
  String? get idValidationError => _idValidationError;

  bool get isTechnician => _role == UserRole.technician;

  /// Position in the visible step rail. Clients see two steps, technicians
  /// four, so the rail is sized from the role rather than fixed.
  int get totalSteps => isTechnician ? 4 : 2;

  int get stepIndex => switch (_step) {
    RegistrationStep.role => 0,
    RegistrationStep.identity => 1,
    RegistrationStep.specialization => 2,
    RegistrationStep.quiz || RegistrationStep.failedResult => 3,
  };

  // --------------------------------------------------------------- mutators

  void chooseRole(UserRole role) {
    _role = role;
    _error = null;
    _step = RegistrationStep.identity;
    notifyListeners();
  }

  /// Records a picked ID, running the format and size checks immediately so
  /// the error appears beside the preview rather than after a failed upload.
  ///
  /// Async because validation reads the file's length, and on web that is an
  /// asynchronous blob read rather than a filesystem stat. The preview appears
  /// straight away and the verdict follows a frame later.
  Future<void> pickIdFile(XFile file) async {
    _idFile = file;
    _idValidationError = null;
    _error = null;
    notifyListeners();

    final IdValidation result = await _service.validateIdFile(file);

    // Guard against a second pick landing while the first was being checked.
    if (!identical(_idFile, file)) return;

    _idValidationError = result.error;
    notifyListeners();
  }

  bool get canLeaveIdentityStep =>
      _idFile != null && _idValidationError == null;

  void chooseSpecialization(Specialization value) {
    _specialization = value;
    _step = RegistrationStep.quiz;
    notifyListeners();
  }

  void setAnswer(String questionId, int choiceIndex) {
    _answers = <String, int>{..._answers, questionId: choiceIndex};
    notifyListeners();
  }

  /// Moves off the identity step. Clients submit from here; technicians carry
  /// on to the assessment.
  void continueFromIdentity() {
    if (!canLeaveIdentityStep) return;
    _step = isTechnician
        ? RegistrationStep.specialization
        : RegistrationStep.identity;
    notifyListeners();
  }

  void retryQuiz() {
    _failedResult = null;
    _answers = <String, int>{};
    _step = RegistrationStep.quiz;
    notifyListeners();
  }

  void back() {
    _error = null;
    switch (_step) {
      case RegistrationStep.identity:
        _step = RegistrationStep.role;
      case RegistrationStep.specialization:
        _step = RegistrationStep.identity;
      case RegistrationStep.quiz:
        _step = RegistrationStep.specialization;
      case RegistrationStep.failedResult:
        _step = RegistrationStep.quiz;
      case RegistrationStep.role:
        return;
    }
    notifyListeners();
  }

  bool get canGoBack => _step != RegistrationStep.role && !_isSubmitting;

  // ---------------------------------------------------------------- commit

  /// Uploads the ID, then commits the whole registration in one transaction.
  ///
  /// Returns true when the account now exists. A technician who fails the
  /// assessment gets false with [failedResult] set and **nothing written**.
  ///
  /// The ID is uploaded first because Storage is not part of the database
  /// transaction. If the commit then fails, the orphaned object is deleted so
  /// a retry does not leave a pile of abandoned files behind.
  Future<bool> submit({String? fullName, String? phone}) async {
    if (_isSubmitting) return false;
    if (_role == null || _idFile == null) {
      _error = 'Add your ID before finishing.';
      notifyListeners();
      return false;
    }

    _isSubmitting = true;
    _error = null;
    notifyListeners();

    String? uploadedPath;

    try {
      uploadedPath = await _service.uploadIdDocument(_idFile!);

      final RegistrationOutcome outcome = await _service.completeRegistration(
        role: _role!,
        idDocumentUrl: uploadedPath,
        fullName: fullName,
        phone: phone,
        specialization: _specialization,
        answers: _answers,
      );

      if (outcome.completed) return true;

      // Failed the assessment. Nothing was written, so clean up the orphaned
      // upload and let them retry.
      await _service.discardIdDocument(uploadedPath);
      uploadedPath = null;

      _failedResult = outcome.result;
      _step = RegistrationStep.failedResult;
      return false;
    } on RbCarsFailure catch (failure) {
      if (uploadedPath != null) {
        await _service.discardIdDocument(uploadedPath);
      }
      _error = failure.message;
      return false;
    } catch (error) {
      if (uploadedPath != null) {
        await _service.discardIdDocument(uploadedPath);
      }
      _error = 'Could not finish your registration. Please try again.';
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }
}
