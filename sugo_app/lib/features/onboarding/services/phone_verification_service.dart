import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import 'client_registration_service.dart';

/// Which mechanism carried the code.
enum OtpTransport {
  /// Firebase Phone Auth. The real path - it sends an actual SMS.
  firebase,

  /// SUGO's own `send-phone-code` edge function. Used only when Firebase is
  /// unavailable, so the step is never a dead end.
  sugoFallback,
}

/// The result of asking for a code.
class PhoneCodeSent {
  const PhoneCodeSent({
    required this.phone,
    required this.transport,
    this.verificationId,
    this.resendToken,
    this.demoCode,
  });

  /// The E.164 number the code was sent to.
  final String phone;

  final OtpTransport transport;

  /// Firebase's handle for this attempt. It is what pairs the code the user
  /// types with the request that sent it, so it must be kept between the two
  /// halves of the flow.
  final String? verificationId;

  /// Lets a resend continue the same verification rather than starting a new
  /// one, which is what stops Firebase counting it as a fresh SMS.
  final int? resendToken;

  /// Present only on the fallback path with no gateway, where the server
  /// returns the code instead of texting it.
  final String? demoCode;

  bool get isDemo => demoCode != null;
}

/// Phone verification via Firebase, recorded against the Supabase account.
///
/// ## Why Firebase for this one step
///
/// Supabase is the platform - accounts, data, storage, realtime. Firebase is
/// here purely as an **SMS transport**, because its free tier sends real
/// messages while Supabase's phone provider needs a funded Twilio account
/// behind it.
///
/// A Firebase user is NOT a SUGO user. Nobody signs in to SUGO with it. It
/// proves control of a number, that proof is handed to the server, and the
/// Firebase session is then discarded - see [verifyCode].
///
/// ## The server never takes the app's word for it
///
/// The obvious shortcut - the app telling Supabase "Firebase said yes" - would
/// be worthless, because anyone can send that request. So `verifyCode` sends
/// the **Firebase ID token**: a JWT signed by Google, carrying the verified
/// number as a claim. The `verify-firebase-phone` edge function checks that
/// signature against Google's published keys before writing anything.
///
/// Firebase proves the number, Google's signature proves Firebase said it, and
/// only then is the flag set. The app only carries the token.
class PhoneVerificationService {
  PhoneVerificationService({SupabaseClient? client, FirebaseAuth? firebaseAuth})
    : _client = client ?? SupabaseService.client,
      _firebaseAuth = firebaseAuth;

  final SupabaseClient _client;
  final FirebaseAuth? _firebaseAuth;

  /// Resolved lazily: touching `FirebaseAuth.instance` before
  /// `Firebase.initializeApp` throws, and the app deliberately treats a failed
  /// Firebase init as non-fatal.
  FirebaseAuth get _auth => _firebaseAuth ?? FirebaseAuth.instance;

  /// The fallback transport, used only when Firebase cannot run.
  final ClientRegistrationService _fallback = ClientRegistrationService();

  static const String _verifyFunction = 'verify-firebase-phone';

  /// Seconds before "resend" becomes available.
  ///
  /// Long enough that a slow SMS usually lands first - resending immediately
  /// is how someone ends up with two codes and types the dead one - and short
  /// enough not to strand a person whose message was genuinely lost.
  static const Duration resendCooldown = Duration(seconds: 30);

  static const int codeLength = 6;

  /// How long Firebase waits for Android to auto-read the SMS before giving
  /// up and leaving the person to type it. Also the ceiling on how long
  /// [sendCode] can block.
  static const Duration _autoRetrievalTimeout = Duration(seconds: 60);

  /// Normalises a Philippine mobile number to E.164.
  ///
  /// Accepts what people actually type - `09171234567`, `+639171234567`,
  /// `639171234567`, `9171234567` - and passes through any other well-formed
  /// E.164 number, so a Firebase test number from another country still works.
  static String? normalizePhone(String input) {
    final String digits = input.replaceAll(RegExp(r'[^0-9+]'), '');

    if (digits.startsWith('+639') && digits.length == 13) return digits;
    if (digits.startsWith('639') && digits.length == 12) return '+$digits';
    if (digits.startsWith('09') && digits.length == 11) {
      return '+63${digits.substring(1)}';
    }
    if (digits.startsWith('9') && digits.length == 10) return '+63$digits';

    if (RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(digits)) return digits;

    return null;
  }

  /// Formats a PH number for display; leaves anything else alone.
  static String formatPhone(String e164) {
    if (e164.length != 13 || !e164.startsWith('+63')) return e164;
    return '+63 ${e164.substring(3, 6)} ${e164.substring(6, 9)} '
        '${e164.substring(9)}';
  }

  /// Sends an OTP by SMS.
  ///
  /// [onAutoVerified] fires on Android when the platform reads the SMS itself
  /// and completes verification with no typing. It is a real path, not an
  /// optimisation: on many Android phones the code never has to be entered,
  /// and a screen that ignores it would sit waiting for input the user has no
  /// reason to provide.
  Future<PhoneCodeSent> sendCode(
    String phone, {
    int? resendToken,
    Future<void> Function(PhoneAuthCredential credential)? onAutoVerified,
  }) async {
    final String? normalized = normalizePhone(phone);

    if (normalized == null) {
      throw const RbCarsFailure(
        'Enter a valid mobile number, like 0917 123 4567.',
      );
    }

    final Completer<PhoneCodeSent> completer = Completer<PhoneCodeSent>();

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: normalized,
        timeout: _autoRetrievalTimeout,
        forceResendingToken: resendToken,

        verificationCompleted: (PhoneAuthCredential credential) async {
          if (onAutoVerified != null) await onAutoVerified(credential);
        },

        verificationFailed: (FirebaseAuthException error) {
          _log('verifyPhoneNumber', error);
          if (completer.isCompleted) return;

          // Firebase itself is not usable here - not configured for this
          // platform, missing SHA-1, quota exhausted. Fall back rather than
          // dead-end a mandatory registration step.
          if (_isFirebaseUnavailable(error)) {
            completer.complete(_sendViaFallback(normalized));
          } else {
            completer.completeError(RbCarsFailure(_describeFirebase(error)));
          }
        },

        codeSent: (String verificationId, int? token) {
          if (completer.isCompleted) return;
          completer.complete(
            PhoneCodeSent(
              phone: normalized,
              transport: OtpTransport.firebase,
              verificationId: verificationId,
              resendToken: token,
            ),
          );
        },

        codeAutoRetrievalTimeout: (String verificationId) {
          // Auto-read gave up; the code still has to be typed. `codeSent` has
          // already fired by this point, so there is nothing to complete.
        },
      );
    } catch (error) {
      _log('sendCode', error);
      if (!completer.isCompleted) {
        // A synchronous throw usually means Firebase never initialised - a
        // fresh clone without `flutterfire configure`, or an unregistered
        // platform.
        return _sendViaFallback(normalized);
      }
    }

    return completer.future;
  }

  /// True when Firebase cannot deliver at all, as opposed to rejecting input.
  bool _isFirebaseUnavailable(FirebaseAuthException error) {
    const Set<String> codes = <String>{
      'unknown',
      'internal-error',
      'operation-not-allowed', // Phone sign-in not enabled on the project.
      'app-not-authorized', // SHA-1 missing from the Firebase project.
      'missing-client-identifier',
      'quota-exceeded',
      'too-many-requests',
      'network-request-failed',
    };

    return codes.contains(error.code);
  }

  Future<PhoneCodeSent> _sendViaFallback(String phone) async {
    final PhoneCodeRequest request = await _fallback.sendCode(phone);

    return PhoneCodeSent(
      phone: phone,
      transport: OtpTransport.sugoFallback,
      demoCode: request.debugCode,
    );
  }

  /// Confirms a typed code and records the verified number on the server.
  Future<void> verifyCode({
    required String phone,
    required String token,
    required OtpTransport transport,
    String? verificationId,
  }) async {
    final String trimmed = token.trim();

    if (trimmed.length != codeLength) {
      throw RbCarsFailure('Enter the $codeLength-digit code.');
    }

    // The fallback checks against our own table and sets the flag itself.
    if (transport == OtpTransport.sugoFallback) {
      final PhoneVerificationResult result = await _fallback.verifyCode(
        trimmed,
      );
      if (!result.verified) throw RbCarsFailure(result.message);
      return;
    }

    if (verificationId == null) {
      throw const RbCarsFailure('Request a new code and try again.');
    }

    final PhoneAuthCredential credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: trimmed,
    );

    await confirmCredential(credential);
  }

  /// Signs in to Firebase with a verified credential, hands the resulting ID
  /// token to the server, then discards the Firebase session.
  ///
  /// Shared by the typed-code path and Android's auto-retrieval, because both
  /// end with the same thing: a credential that needs turning into proof.
  Future<void> confirmCredential(PhoneAuthCredential credential) async {
    final String idToken;

    try {
      final UserCredential result = await _auth.signInWithCredential(
        credential,
      );
      final String? fetched = await result.user?.getIdToken();

      if (fetched == null || fetched.isEmpty) {
        throw const RbCarsFailure('Could not confirm that code. Try again.');
      }
      idToken = fetched;
    } on FirebaseAuthException catch (error) {
      _log('signInWithCredential', error);
      throw RbCarsFailure(_describeFirebase(error));
    }

    try {
      final FunctionResponse response = await _client.functions.invoke(
        _verifyFunction,
        body: <String, dynamic>{'id_token': idToken},
      );

      final Object? data = response.data;
      if (data is Map<String, dynamic> && data['error'] != null) {
        throw RbCarsFailure(data['error'].toString());
      }
    } on FunctionException catch (error) {
      _log('confirmCredential', error);
      final Object? details = error.details;
      if (details is Map && details['error'] is String) {
        throw RbCarsFailure(details['error'] as String);
      }
      throw const RbCarsFailure('Could not save your verified number.');
    } finally {
      // The Firebase session has done its job. Keeping it would leave two
      // notions of "signed in" alive at once, which is the confusion this
      // whole boundary exists to avoid.
      await _signOutFirebase();
    }
  }

  Future<void> _signOutFirebase() async {
    try {
      await _auth.signOut();
    } catch (error) {
      // Never fatal: the number is already verified server-side by this point.
      _log('signOutFirebase', error);
    }
  }

  /// Whether this account already has a verified phone, for a resumed flow.
  Future<({String? phone, bool verified})> status() async {
    try {
      final dynamic row = await _client.rpc<dynamic>('my_phone_status');

      if (row is Map<String, dynamic>) {
        final String? raw = row['phone'] as String?;
        return (
          phone: raw == null || raw.isEmpty
              ? null
              : (raw.startsWith('+') ? raw : '+$raw'),
          verified: row['verified'] as bool? ?? false,
        );
      }
    } catch (error) {
      _log('status', error);
    }

    return (phone: null, verified: false);
  }

  /// Turns a Firebase failure into something the person can act on.
  String _describeFirebase(FirebaseAuthException error) {
    return switch (error.code) {
      'invalid-verification-code' =>
        'That code is not right. Check it and try again.',
      'session-expired' || 'invalid-verification-id' =>
        'That code has expired. Tap resend to get a new one.',
      'invalid-phone-number' =>
        'That number was rejected. Check it and try again.',
      'too-many-requests' =>
        'Too many attempts from this device. Wait a few minutes.',
      'quota-exceeded' =>
        'The SMS quota for today is used up. Try again tomorrow.',
      'operation-not-allowed' =>
        'Phone sign-in is not enabled on the Firebase project yet.',
      'app-not-authorized' =>
        'This build is not authorised for phone sign-in. Add its SHA-1 '
            'fingerprint to the Firebase project.',
      'credential-already-in-use' ||
      'account-exists-with-different-credential' =>
        'That number is already linked to another account.',
      _ => error.message ?? 'Could not verify that number. Please try again.',
    };
  }

  void _log(String action, Object error) {
    if (kDebugMode) {
      if (error is FirebaseAuthException) {
        debugPrint(
          'PhoneVerificationService.$action failed: '
          '[${error.code}] ${error.message}',
        );
      } else {
        debugPrint('PhoneVerificationService.$action failed: $error');
      }
    }
  }
}
