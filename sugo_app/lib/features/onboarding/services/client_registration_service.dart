import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../models/client_onboarding_models.dart';

/// Outcome of checking a one-time code.
class PhoneVerificationResult {
  const PhoneVerificationResult({
    required this.verified,
    this.reason,
    this.attemptsLeft,
  });

  final bool verified;

  /// Machine-readable cause on failure: `no_code`, `expired`,
  /// `too_many_attempts`, `incorrect`.
  final String? reason;

  final int? attemptsLeft;

  /// A sentence the user can act on.
  ///
  /// The distinction between "expired" and "incorrect" matters: one means
  /// resend, the other means look again. Collapsing them into "invalid code"
  /// leaves the user retyping a code that can never work.
  String get message => switch (reason) {
    'no_code' => 'That code has expired. Tap resend to get a new one.',
    'expired' => 'That code has expired. Tap resend to get a new one.',
    'too_many_attempts' =>
      'Too many incorrect attempts. Tap resend to get a new code.',
    'incorrect' when (attemptsLeft ?? 0) > 0 =>
      'That code is not right. $attemptsLeft attempt'
          '${attemptsLeft == 1 ? '' : 's'} left.',
    'incorrect' => 'That code is not right.',
    _ => 'Could not verify that code. Please try again.',
  };
}

/// Everything the client registration flow writes and reads.
///
/// Phone verification and the trust profile both go through edge functions,
/// because both are decided server-side: the OTP code is never readable by the
/// client (RLS denies the whole table), and the trust profile's starting values
/// must not be chosen by the account they describe.
class ClientRegistrationService {
  ClientRegistrationService({SupabaseClient? client})
    : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  static const String _sendCodeFunction = 'send-phone-code';
  static const String _verifyCodeFunction = 'verify-phone-code';
  static const String _submitRegistrationFunction = 'submit-registration';

  /// How long before "resend" becomes available.
  ///
  /// Sixty seconds. Long enough that a delayed SMS usually arrives first -
  /// resending immediately is how a user ends up with two codes and enters the
  /// dead one - and short enough not to strand someone whose message was
  /// genuinely lost.
  static const Duration resendCooldown = Duration(seconds: 60);

  /// Digits in a code. Six is the SMS convention; matching it means the code
  /// looks right to a user who has seen a hundred of them.
  static const int codeLength = 6;

  String get _uid {
    final String? id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const RbCarsFailure('Please sign in again to continue.');
    }
    return id;
  }

  // ------------------------------------------------------------------ phone

  /// Normalises a Philippine mobile number to E.164.
  ///
  /// Accepts the three forms people actually type - `09171234567`,
  /// `+639171234567`, `639171234567` - and returns `+639171234567`. Returns
  /// null when it is not a recognisable PH mobile number.
  ///
  /// Done client-side so the error appears under the field as they type,
  /// rather than after a round trip. The edge function normalises again before
  /// sending, because a client-side check is a convenience and never a
  /// guarantee.
  static String? normalizePhone(String input) {
    final String digits = input.replaceAll(RegExp(r'[^0-9+]'), '');

    // PH mobile numbers are 10 digits after the country code and always start
    // with 9.
    if (digits.startsWith('+639') && digits.length == 13) return digits;
    if (digits.startsWith('639') && digits.length == 12) return '+$digits';
    if (digits.startsWith('09') && digits.length == 11) {
      return '+63${digits.substring(1)}';
    }
    if (digits.startsWith('9') && digits.length == 10) return '+63$digits';

    return null;
  }

  /// Formats for display: `+63 917 123 4567`.
  static String formatPhone(String e164) {
    if (e164.length != 13 || !e164.startsWith('+63')) return e164;
    return '+63 ${e164.substring(3, 6)} ${e164.substring(6, 9)} '
        '${e164.substring(9)}';
  }

  /// Sends a one-time code.
  ///
  /// ## Two delivery modes, and the app is told which
  ///
  /// `send-phone-code` supports Semaphore and Twilio, selected by the
  /// `SMS_PROVIDER` secret. With none configured it runs in DEMO mode: the
  /// code is still generated, stored, expiring, single-use and rate limited -
  /// it is simply returned in the response instead of texted.
  ///
  /// The response carries `delivery`, so the screen can show the code in demo
  /// mode rather than leaving someone waiting for a text. That is deliberately
  /// not gated on `kDebugMode`: a release build with no provider would
  /// otherwise present a step nobody can complete.
  ///
  /// Demo mode verifies nothing about who holds the phone. It exists so the
  /// flow is demonstrable without an SMS account, and says so on screen.
  Future<PhoneCodeRequest> sendCode(String phone) async {
    final String? normalized = normalizePhone(phone);
    if (normalized == null) {
      throw const RbCarsFailure(
        'Enter a valid Philippine mobile number, like 0917 123 4567.',
      );
    }

    try {
      final FunctionResponse response = await _client.functions.invoke(
        _sendCodeFunction,
        body: <String, dynamic>{'phone': normalized},
      );

      final Object? data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const RbCarsFailure('The server returned an unexpected reply.');
      }
      if (data['error'] != null) {
        throw RbCarsFailure(data['error'].toString());
      }

      return PhoneCodeRequest(
        phone: normalized,
        expiresAt:
            DateTime.tryParse(data['expires_at'] as String? ?? '') ??
            DateTime.now().add(const Duration(minutes: 10)),
        // 'sms' when a gateway actually sent it, 'demo' when none is
        // configured. The screen needs to know: waiting for a text that will
        // never arrive is the worst version of this step.
        deliveredBySms: data['delivery'] == 'sms',
        debugCode: data['debug_code'] as String?,
      );
    } on FunctionException catch (error) {
      _log('sendCode', error);
      final Object? details = error.details;
      if (details is Map && details['error'] is String) {
        throw RbCarsFailure(details['error'] as String);
      }
      throw const RbCarsFailure('Could not send the code. Please try again.');
    } on RbCarsFailure {
      rethrow;
    } catch (error) {
      _log('sendCode', error);
      throw const RbCarsFailure(
        'Could not reach the server. Check your connection and try again.',
      );
    }
  }

  /// Checks a code. The comparison happens server-side; the app never sees
  /// what the correct code was.
  Future<PhoneVerificationResult> verifyCode(String code) async {
    final String trimmed = code.trim();
    if (trimmed.length != codeLength) {
      return const PhoneVerificationResult(
        verified: false,
        reason: 'incorrect',
      );
    }

    try {
      final FunctionResponse response = await _client.functions.invoke(
        _verifyCodeFunction,
        body: <String, dynamic>{'code': trimmed},
      );

      final Object? data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const RbCarsFailure('The server returned an unexpected reply.');
      }

      return PhoneVerificationResult(
        verified: data['verified'] as bool? ?? false,
        reason: data['reason'] as String?,
        attemptsLeft: data['attempts_left'] as int?,
      );
    } on FunctionException catch (error) {
      _log('verifyCode', error);
      throw const RbCarsFailure('Could not check that code. Please try again.');
    } on RbCarsFailure {
      rethrow;
    } catch (error) {
      _log('verifyCode', error);
      throw const RbCarsFailure(
        'Could not reach the server. Check your connection and try again.',
      );
    }
  }

  // -------------------------------------------------------------- addresses

  Future<List<SavedAddress>> loadAddresses() async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('client_saved_addresses')
          .select()
          .eq('client_id', _uid)
          .order('is_default', ascending: false)
          .order('created_at');

      return rows.map(SavedAddress.fromJson).toList(growable: false);
    } on PostgrestException catch (error) {
      _log('loadAddresses', error);
      throw const RbCarsFailure('Could not load your saved addresses.');
    }
  }

  /// Saves the default address, replacing the previous default if there is one.
  ///
  /// Updates in place when a default already exists rather than inserting a
  /// second row. Someone correcting their pin three times during registration
  /// should end up with one address, not three - and the partial unique index
  /// would reject the second insert anyway.
  Future<SavedAddress> saveDefaultAddress(SavedAddress address) async {
    final String uid = _uid;

    try {
      final List<SavedAddress> existing = await loadAddresses();
      final SavedAddress? currentDefault = existing
          .where((SavedAddress a) => a.isDefault)
          .firstOrNull;

      final Map<String, dynamic> payload = address.toInsertJson(uid);

      final Map<String, dynamic> row;
      if (currentDefault?.id != null) {
        row = await _client
            .from('client_saved_addresses')
            .update(payload)
            .eq('id', currentDefault!.id!)
            .select()
            .single();
      } else {
        row = await _client
            .from('client_saved_addresses')
            .insert(payload)
            .select()
            .single();
      }

      return SavedAddress.fromJson(row);
    } on PostgrestException catch (error) {
      _log('saveDefaultAddress', error);
      throw RbCarsFailure(_describe(error, 'Could not save your address.'));
    }
  }

  /// Saves any address - a new one, or an edit of an existing one.
  ///
  /// Distinct from [saveDefaultAddress], which exists for registration and
  /// deliberately keeps a client to exactly one address while they sign up.
  /// Once someone is using the app they can keep several ("Home", "Office",
  /// "Mum's place"), which is what the table was built for from the start.
  ///
  /// Making one the default clears the others: the
  /// `client_addresses_single_default` trigger does that in the same
  /// statement, so no caller has to remember to unset the previous one.
  Future<SavedAddress> saveAddress(SavedAddress address) async {
    final String uid = _uid;

    try {
      final Map<String, dynamic> payload = address.toInsertJson(uid);

      final Map<String, dynamic> row = address.id == null
          ? await _client
                .from('client_saved_addresses')
                .insert(payload)
                .select()
                .single()
          : await _client
                .from('client_saved_addresses')
                .update(payload)
                .eq('id', address.id!)
                .select()
                .single();

      return SavedAddress.fromJson(row);
    } on PostgrestException catch (error) {
      _log('saveAddress', error);
      throw RbCarsFailure(_describe(error, 'Could not save that address.'));
    }
  }

  /// Promotes an address to the default one.
  Future<void> setDefaultAddress(String addressId) async {
    try {
      await _client
          .from('client_saved_addresses')
          .update(<String, dynamic>{'is_default': true})
          .eq('id', addressId);
    } on PostgrestException catch (error) {
      _log('setDefaultAddress', error);
      throw RbCarsFailure(
        _describe(error, 'Could not change your default address.'),
      );
    }
  }

  /// Removes an address.
  ///
  /// Jobs keep their own copy of where they happened (`jobs.latitude`,
  /// `longitude` and `address_text`), so deleting an address here never
  /// rewrites the history of a booking that used it.
  Future<void> deleteAddress(String addressId) async {
    try {
      await _client
          .from('client_saved_addresses')
          .delete()
          .eq('id', addressId);
    } on PostgrestException catch (error) {
      _log('deleteAddress', error);
      throw RbCarsFailure(_describe(error, 'Could not delete that address.'));
    }
  }

  // ---------------------------------------------------------- trust profile

  Future<ClientTrustProfile?> loadTrustProfile() async {
    try {
      final Map<String, dynamic>? row = await _client
          .from('client_verification_status')
          .select()
          .eq('client_id', _uid)
          .maybeSingle();

      return row == null ? null : ClientTrustProfile.fromJson(row);
    } on PostgrestException catch (error) {
      _log('loadTrustProfile', error);
      return null;
    }
  }

  /// Files the finished registration for review.
  ///
  /// The same `submit-registration` edge function the technician flow uses. It
  /// branches on the caller's role, initialises the trust profile through
  /// `initialize_client_trust_profile()`, and only then moves the account to
  /// `pending_review`.
  Future<void> submitForReview() async {
    try {
      final FunctionResponse response = await _client.functions.invoke(
        _submitRegistrationFunction,
      );

      final Object? data = response.data;
      if (data is Map<String, dynamic> && data['error'] != null) {
        throw RbCarsFailure(data['error'].toString());
      }
    } on FunctionException catch (error) {
      _log('submitForReview', error);
      final Object? details = error.details;
      if (details is Map && details['error'] is String) {
        throw RbCarsFailure(details['error'] as String);
      }
      throw const RbCarsFailure('Could not submit your registration.');
    } on RbCarsFailure {
      rethrow;
    } catch (error) {
      _log('submitForReview', error);
      throw const RbCarsFailure(
        'Could not reach the server. Check your connection and try again.',
      );
    }
  }

  String _describe(PostgrestException error, String fallback) {
    final String message = error.message.toLowerCase();

    if (message.contains('row-level security') || error.code == '42501') {
      return '$fallback Your account is not permitted to do that yet - '
          'this usually means a database policy is missing.';
    }
    if (message.contains('foreign key')) {
      return '$fallback Your profile could not be found.';
    }
    return '$fallback Please try again.';
  }

  void _log(String action, Object error) {
    if (kDebugMode) {
      if (error is PostgrestException) {
        debugPrint(
          'ClientRegistrationService.$action failed: '
          '[${error.code}] ${error.message}',
        );
      } else {
        debugPrint('ClientRegistrationService.$action failed: $error');
      }
    }
  }
}

/// A code that has been issued and is waiting to be entered.
class PhoneCodeRequest {
  const PhoneCodeRequest({
    required this.phone,
    required this.expiresAt,
    this.deliveredBySms = true,
    this.debugCode,
  });

  final String phone;
  final DateTime expiresAt;

  /// True when a gateway actually sent a text. False in demo mode, where the
  /// server returned the code instead.
  final bool deliveredBySms;

  /// The code itself, returned only when no SMS provider is configured. Null
  /// whenever a real text was sent.
  final String? debugCode;

  /// True when the screen must display the code because nothing was texted.
  bool get isDemo => !deliveredBySms && debugCode != null;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Duration get timeLeft {
    final Duration left = expiresAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }
}
