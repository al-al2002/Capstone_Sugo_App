import 'package:supabase_flutter/supabase_flutter.dart';

/// A user-presentable auth error.
///
/// Repositories translate transport-level exceptions into this type so the UI
/// never has to reason about Supabase or socket errors.
class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.code});

  final String message;
  final String? code;

  /// Raised when the account exists but the email has not been verified yet.
  bool get isEmailNotConfirmed => code == 'email_not_confirmed';

  bool get isNetworkError => code == 'network_error';

  @override
  String toString() => 'AuthFailure(code: $code, message: $message)';
}

/// Maps Supabase and network errors onto friendly copy.
class AuthFailureMapper {
  const AuthFailureMapper._();

  static AuthFailure map(Object error) {
    if (error is AuthFailure) return error;

    if (error is AuthException) {
      return AuthFailure(_messageFor(error), code: error.code);
    }

    if (error is PostgrestException) {
      return AuthFailure(
        'We could not save your details. Please try again.',
        code: error.code,
      );
    }

    // Checked by message rather than by type so this file stays usable on web,
    // where dart:io (and therefore SocketException) is unavailable.
    if (_looksLikeNetworkError(error.toString())) {
      return const AuthFailure(
        'No internet connection. Check your network and try again.',
        code: 'network_error',
      );
    }

    return const AuthFailure('Something went wrong. Please try again.');
  }

  static bool _looksLikeNetworkError(String error) {
    final String raw = error.toLowerCase();
    return raw.contains('socketexception') ||
        raw.contains('clientexception') ||
        raw.contains('failed host lookup') ||
        raw.contains('connection refused') ||
        raw.contains('connection closed') ||
        raw.contains('network is unreachable') ||
        raw.contains('timeoutexception');
  }

  static String _messageFor(AuthException error) {
    switch (error.code) {
      case 'invalid_credentials':
      case 'invalid_grant':
        return 'Incorrect email or password.';
      case 'email_not_confirmed':
        return 'Please verify your email before logging in.';
      case 'user_already_exists':
      case 'email_exists':
        return 'That email is already registered. Try logging in instead.';
      case 'weak_password':
        return 'That password is too weak. Use at least 8 characters.';
      case 'over_email_send_rate_limit':
      case 'over_request_rate_limit':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'validation_failed':
        return 'Please check the details you entered.';
      case 'signup_disabled':
        return 'Sign ups are currently disabled. Contact SUGO support.';
      case 'provider_disabled':
        return 'That sign-in method is not enabled yet.';
      // Forgot password. GoTrue answers a mistyped code and an expired one
      // with the same code ("Token has expired or is invalid"), so the copy
      // names both remedies rather than guessing which one applies.
      case 'otp_expired':
        return 'That code is wrong or has expired. Check it, or tap resend '
            'for a new one.';
      case 'otp_disabled':
        return 'Email codes are switched off right now. Contact SUGO support.';
      case 'same_password':
        return 'Choose a password different from your old one.';
    }

    // Older Supabase deployments return only a message, with no code.
    final String raw = error.message.toLowerCase();
    if (raw.contains('invalid login credentials')) {
      return 'Incorrect email or password.';
    }
    if (raw.contains('already registered')) {
      return 'That email is already registered. Try logging in instead.';
    }
    if (raw.contains('email not confirmed')) {
      return 'Please verify your email before logging in.';
    }
    if (raw.contains('token has expired') || raw.contains('is invalid')) {
      return 'That code is not right, or has expired. Check it or tap resend.';
    }
    if (_looksLikeNetworkError(raw)) {
      return 'No internet connection. Check your network and try again.';
    }

    return error.message;
  }
}
