import 'dart:async';

import '../../../core/services/supabase_service.dart';
import '../../../core/session/session_state.dart';
import '../models/client_onboarding_models.dart';
import '../models/registration_status.dart';
import '../services/client_registration_service.dart';
import '../services/email_otp_service.dart';
import 'registration_flow_controller.dart';

/// Drives the five-step client registration.
///
/// account -> ID + selfie -> email code -> location -> review
class ClientRegistrationController extends RegistrationFlowController {
  ClientRegistrationController({
    ClientRegistrationService? service,
    EmailOtpService? otpService,
    super.identityService,
  }) : _service = service ?? ClientRegistrationService(),
       _otp = otpService ?? EmailOtpService();

  final ClientRegistrationService _service;
  final EmailOtpService _otp;

  @override
  UserRole get role => UserRole.client;

  // -------------------------------------------------------------- email step

  EmailVerificationState get emailState => _emailState;
  String? get emailError => _emailError;
  int get resendIn => _resendIn;
  bool get canResend => _resendIn == 0;

  /// The address the code goes to. Read from the session rather than typed:
  /// the client signed up with it, and letting them edit it here would mean
  /// verifying an address the account does not use.
  String get emailLabel =>
      _otp.currentEmail ??
      SupabaseService.client.auth.currentUser?.email ??
      'your email';

  bool get isEmailVerified => _emailState == EmailVerificationState.verified;

  /// Whether the step is satisfied, verified in this session or not.
  ///
  /// The OTP result is deliberately not stored anywhere, so the only durable
  /// evidence that it happened is `profiles.registration_step` having moved
  /// past it. A resumed registration sitting on Location or Review has already
  /// been through this; asking again would punish somebody for closing the app.
  bool get isEmailStepSatisfied {
    if (isEmailVerified) return true;

    const List<OnboardingStepId> flow = OnboardingStepId.clientFlow;
    return flow.indexOf(currentStep) > flow.indexOf(OnboardingStepId.email);
  }

  /// Mails a fresh code and starts the resend countdown.
  Future<bool> sendCode() async {
    _emailError = null;

    final String? sentTo = await guard<String>(() => _otp.sendCode());

    if (sentTo == null) {
      // Moved out of the banner deliberately. `OnboardingScaffold` draws
      // `error` above its scroll view, and by the time somebody taps Resend
      // they are scrolled down to the code boxes - so a refused send set a
      // message that was off-screen, and the button looked like it did
      // nothing at all. It belongs next to the control that caused it.
      _emailError = error;
      clearError();
      notifyListeners();
      return false;
    }

    _emailState = EmailVerificationState.awaitingCode;
    _emailError = null;
    _startResendCountdown();
    notifyListeners();
    return true;
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    _resendIn = EmailOtpService.resendCooldown.inSeconds;

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      _resendIn -= 1;
      if (_resendIn <= 0) {
        _resendIn = 0;
        timer.cancel();
      }
      notifyListeners();
    });
  }

  /// Checks a typed code. GoTrue does the comparison.
  Future<bool> verifyCode(String code) async {
    _emailError = null;

    final bool? ok = await guard<bool>(() async {
      await _otp.verifyCode(code);
      return true;
    });

    if (ok == null) {
      // `guard` put the message in `error`, which renders as a banner over the
      // whole step. A wrong code is a correction to one field, so it is moved
      // under that field instead.
      _emailError = error;
      clearError();
      notifyListeners();
      return false;
    }

    _emailState = EmailVerificationState.verified;
    _emailError = null;
    _resendTimer?.cancel();
    _resendIn = 0;
    notifyListeners();

    // Persisted here rather than left to `next()`, and this is load-bearing.
    //
    // `verifyOTP` returns a *new session* for the same user. `supabase_flutter`
    // installs it, which fires `onAuthStateChange`, which makes
    // `SessionController.refresh()` run and the gate rebuild - and the rebuild
    // constructs a fresh controller. Every field on this object, `_emailState`
    // included, is gone at that point.
    //
    // Writing the resume point first means the rebuilt controller opens on
    // Location instead of bouncing back to an unverified email step. The step
    // index is deliberately *not* advanced here: leaving it lets the tick
    // finish before the screen changes, and `next()` writing the same value a
    // moment later is harmless.
    await identity.saveStep(_stepAfterEmail);

    return true;
  }

  /// The step the flow moves to once the code is accepted.
  ///
  /// Derived from the flow rather than named, so reordering `clientFlow` cannot
  /// leave this pointing somewhere that no longer follows the email step.
  OnboardingStepId get _stepAfterEmail {
    const List<OnboardingStepId> flow = OnboardingStepId.clientFlow;
    final int next = flow.indexOf(OnboardingStepId.email) + 1;
    return next < flow.length ? flow[next] : OnboardingStepId.review;
  }

  /// Back to the "send it" state, e.g. when the mail never arrived.
  void restartVerification() {
    _emailState = EmailVerificationState.entry;
    _emailError = null;
    _resendTimer?.cancel();
    _resendIn = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------------ state

  EmailVerificationState _emailState = EmailVerificationState.entry;
  String? _emailError;

  /// Seconds until "resend" becomes available. Driven by [_resendTimer].
  int _resendIn = 0;
  Timer? _resendTimer;

  SavedAddress? _address;
  GeoPlace? _place;
  String _addressLabel = 'Home';

  /// The number an OTP was sent to, or the already-verified one.

  GeoPlace? get place => _place;

  String get addressLabel => _addressLabel;

  SavedAddress? get address => _address;

  bool get hasAddress => _place != null;

  // -------------------------------------------------------------- lifecycle

  @override
  Future<void> loadRoleState() async {
    final List<SavedAddress> addresses = await _service.loadAddresses();
    final SavedAddress? existing = addresses
        .where((SavedAddress a) => a.isDefault)
        .firstOrNull;

    if (existing != null) {
      _address = existing;
      _place = existing.place;
      _addressLabel = existing.label;
    }
  }

  @override
  Set<OnboardingStepId> get completedSteps {
    return <OnboardingStepId>{
      OnboardingStepId.account,
      if (hasSubmittedIdentity) OnboardingStepId.identity,
      if (isEmailStepSatisfied) OnboardingStepId.email,
      if (hasAddress) OnboardingStepId.location,
    };
  }

  @override
  bool get canContinue => switch (currentStep) {
    OnboardingStepId.account => true,
    OnboardingStepId.identity => canLeaveIdentityStep,
    // A hard requirement: a booking confirmation has to reach somebody, and
    // this is the one address the account is guaranteed to have.
    OnboardingStepId.email => isEmailStepSatisfied,
    OnboardingStepId.location => hasAddress,
    OnboardingStepId.review => true,
    // Not in the client flow.
    OnboardingStepId.specialization => true,
    OnboardingStepId.assessment => true,
    OnboardingStepId.documents => true,
  };

  @override
  Future<bool> persistCurrentStep() async {
    switch (currentStep) {
      case OnboardingStepId.location:
        final GeoPlace? pinned = _place;
        if (pinned == null) return false;

        final SavedAddress? saved = await guard<SavedAddress>(
          () => _service.saveDefaultAddress(
            SavedAddress(
              label: _addressLabel.trim().isEmpty
                  ? 'Home'
                  : _addressLabel.trim(),
              latitude: pinned.latitude,
              longitude: pinned.longitude,
              addressText: pinned.displayText,
              notes: _address?.notes,
            ),
          ),
        );

        if (saved == null) return false;
        _address = saved;
        notifyListeners();
        return true;

      // Identity writes as it goes; the rest collect nothing.
      case OnboardingStepId.account:
      case OnboardingStepId.identity:
      case OnboardingStepId.email:
      case OnboardingStepId.review:
      case OnboardingStepId.specialization:
      case OnboardingStepId.assessment:
      case OnboardingStepId.documents:
        return true;
    }
  }

  // --------------------------------------------------------------- location

  void setPlace(GeoPlace value) {
    _place = value;
    clearError();
    notifyListeners();
  }

  void setAddressLabel(String label) {
    _addressLabel = label;
    notifyListeners();
  }

  // ----------------------------------------------------------------- submit

  @override
  Future<void> performSubmit() => _service.submitForReview();
}
