import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/errors/auth_failure.dart';
import '../../data/repositories/auth_repository.dart';

/// Where the forgot-password flow is.
enum ForgotStep {
  /// Asking which address to send the code to.
  email,

  /// The code is in the inbox; waiting for the six digits.
  code,

  /// The code was accepted; choosing a new password.
  newPassword,

  /// The password has been changed.
  done,
}

/// Drives the three-step "forgot password" flow.
///
/// ## Why a code and not a link
///
/// Supabase's default reset email holds a link to a web page. SUGO is an app,
/// so that link would open a browser on a page that does not exist, or would
/// need deep-link plumbing on every platform just to land back here. A
/// six-digit code keeps the whole flow on one screen: type the email, type the
/// code from the inbox, type a new password. It is the same pattern the
/// registration flow already uses for its email check (`EmailOtpService`).
///
/// The code comes from the `recovery` email template
/// (`supabase/templates/recovery.html`), pushed with `supabase config push`.
///
/// ## What each step proves
///
/// * **Send** proves nothing, deliberately. The server answers the same
///   whether or not an account exists, so this screen cannot be used to learn
///   who has a SUGO account.
/// * **Verify** proves the person can read that inbox right now. GoTrue does
///   the comparison, and success signs them in.
/// * **Update** is only possible because verify signed them in - the old
///   password is never needed.
///
/// After the update they stay signed in, and the auth gate under this screen
/// has already routed to their home. Asking them to log in again straight
/// after proving who they are would add a step and prove nothing new.
class ForgotPasswordController extends ChangeNotifier {
  ForgotPasswordController(this._repository);

  final AuthRepository _repository;

  /// Matches the project's `auth.email.max_frequency` of one minute. A
  /// shorter cooldown would offer a resend the server then refuses.
  static const Duration resendCooldown = Duration(seconds: 60);

  ForgotStep _step = ForgotStep.email;
  String _email = '';
  bool _isBusy = false;
  String? _errorMessage;
  int _cooldownLeft = 0;
  Timer? _cooldown;

  ForgotStep get step => _step;
  String get email => _email;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;

  /// Seconds until resend is allowed again; 0 when it is.
  int get resendIn => _cooldownLeft;

  /// Step 1: mail a code. Returns true when it was sent.
  Future<bool> sendCode(String email) async {
    if (_isBusy) return false;
    final bool ok = await _run(() => _repository.sendPasswordResetCode(email));
    if (ok) {
      _email = email.trim().toLowerCase();
      _step = ForgotStep.code;
      _startCooldown();
      notifyListeners();
    }
    return ok;
  }

  /// Sends another code to the same address, once the cooldown allows.
  Future<bool> resend() async {
    if (_cooldownLeft > 0 || _email.isEmpty) return false;
    final bool ok = await _run(() => _repository.sendPasswordResetCode(_email));
    if (ok) _startCooldown();
    return ok;
  }

  /// Step 2: check the six digits. The code boxes animate the answer, so this
  /// returns it rather than moving on by itself - see `OtpCodeField`.
  Future<bool> verifyCode(String code) async {
    final bool ok = await _run(
      () => _repository.verifyPasswordResetCode(email: _email, code: code),
    );
    return ok;
  }

  /// Called by the screen once the boxes have shown their green tick.
  void codeAccepted() {
    _step = ForgotStep.newPassword;
    _cooldown?.cancel();
    notifyListeners();
  }

  /// Step 3: set the new password.
  Future<bool> setPassword(String password) async {
    final bool ok = await _run(() => _repository.updatePassword(password));
    if (ok) {
      _step = ForgotStep.done;
      notifyListeners();
    }
    return ok;
  }

  /// Back from the code step to fix a mistyped address.
  void changeEmail() {
    _step = ForgotStep.email;
    _errorMessage = null;
    notifyListeners();
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  Future<bool> _run(Future<void> Function() action) async {
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on AuthFailure catch (failure) {
      _errorMessage = failure.message;
      return false;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  void _startCooldown() {
    _cooldown?.cancel();
    _cooldownLeft = resendCooldown.inSeconds;
    _cooldown = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      _cooldownLeft -= 1;
      if (_cooldownLeft <= 0) {
        _cooldownLeft = 0;
        timer.cancel();
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _cooldown?.cancel();
    super.dispose();
  }
}
