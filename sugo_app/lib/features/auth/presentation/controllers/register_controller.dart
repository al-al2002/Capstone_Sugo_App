import 'package:flutter/foundation.dart';

import '../../../../core/errors/auth_failure.dart';
import '../../data/repositories/auth_repository.dart';

/// Drives the registration form, including the terms checkbox.
class RegisterController extends ChangeNotifier {
  RegisterController(this._repository);

  final AuthRepository _repository;

  bool _isSubmitting = false;
  bool _acceptedTerms = false;
  String? _errorMessage;

  bool get isSubmitting => _isSubmitting;
  bool get acceptedTerms => _acceptedTerms;
  String? get errorMessage => _errorMessage;

  void setAcceptedTerms(bool value) {
    _acceptedTerms = value;
    _errorMessage = null;
    notifyListeners();
  }

  /// Returns a [SignUpResult] on success, or null when sign up failed - in
  /// which case [errorMessage] explains why.
  Future<SignUpResult?> register({
    required String fullName,
    required String email,
    required String password,
    required String phone,
  }) async {
    if (_isSubmitting) return null;
    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      return await _repository.signUpWithEmail(
        email: email,
        password: password,
        fullName: fullName,
        phone: phone,
      );
    } on AuthFailure catch (failure) {
      _errorMessage = failure.message;
      return null;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }
}
