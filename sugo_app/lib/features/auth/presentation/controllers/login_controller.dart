import 'package:flutter/foundation.dart';

import '../../../../core/errors/auth_failure.dart';
import '../../data/repositories/auth_repository.dart';

/// Drives the login form: submission state and the last error to display.
///
/// Email and password only. The Google and Facebook methods that used to be
/// here were removed on 2026-09-28, along with the repository calls behind
/// them.
class LoginController extends ChangeNotifier {
  LoginController(this._repository);

  final AuthRepository _repository;

  bool _isSubmitting = false;
  String? _errorMessage;

  bool get isSubmitting => _isSubmitting;

  /// Kept as its own getter so the screen reads "is anything in flight?"
  /// without caring that sign-in is now the only thing that can be.
  bool get isBusy => _isSubmitting;
  String? get errorMessage => _errorMessage;

  /// Returns true when the credentials were accepted; navigation is handled by
  /// the auth gate reacting to the new session.
  Future<bool> login({required String email, required String password}) async {
    if (_isSubmitting) return false;
    _setSubmitting(true);
    try {
      await _repository.signInWithEmail(email: email, password: password);
      return true;
    } on AuthFailure catch (failure) {
      _errorMessage = failure.message;
      return false;
    } finally {
      _setSubmitting(false);
    }
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  void _setSubmitting(bool value) {
    _isSubmitting = value;
    if (value) _errorMessage = null;
    notifyListeners();
  }
}
