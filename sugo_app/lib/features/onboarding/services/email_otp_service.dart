import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../rb_cars/services/rb_cars_service.dart';

/// The six-digit email code on the client registration flow.
///
/// ## Why `signInWithOtp` and not `resend`
///
/// The obvious call is `auth.resend(type: OtpType.signup)`, and it is the wrong
/// one here. This project has **Confirm email switched off**, so GoTrue marks
/// every account confirmed the moment it is created - and `resend` refuses to
/// re-send a confirmation for an address that is already confirmed. The step
/// would fail on its first tap, for every user.
///
/// `signInWithOtp` has no such precondition. It issues a fresh one-time code
/// for an existing address whatever its confirmation state, which is exactly
/// what a verification step needs: something only the person holding that
/// inbox can produce.
///
/// `shouldCreateUser: false` matters. Left at its default, a typo would
/// silently create a second account rather than failing, and the flow would
/// then be verifying an address nobody owns.
///
/// ## What this proves, and what it does not
///
/// It proves the person can read that inbox right now. It does **not** set any
/// new column: `email_confirmed_at` was already true at signup, and there is
/// deliberately no `email_otp_verified` column - the step's result lives in the
/// flow, and `profiles.registration_step` is what carries it across a resume.
/// Stated plainly because the distinction matters: this is a live check, not a
/// stored credential.
///
/// ## Where the six digits come from
///
/// `signInWithOtp` mails through the **magic_link** template, and Supabase's
/// default for it renders only `{{ .ConfirmationURL }}` - a link, with nothing
/// to type. The template that replaces it lives in the repo at
/// `supabase/templates/magic_link.html` and is declared in `config.toml`, so
/// it deploys with `supabase config push` rather than being hand-edited in a
/// dashboard nobody can diff.
///
/// That override is only accepted on a project with a custom SMTP provider
/// configured; Supabase refuses template changes on the built-in sender. The
/// provider's credentials live in the dashboard and deliberately nowhere in
/// this repository.
///
/// ## Sending limits, and what breaks first
///
/// The project sends through Gmail SMTP on an App Password. Two ceilings apply,
/// and neither is visible from here:
///
/// * **500 emails per day.** A personal Gmail account will not send more, and
///   the cap resets on a rolling 24-hour window rather than at midnight. Fine
///   for a registration flow at this size; the first thing to outgrow if the
///   app ever has real traffic, at which point a transactional provider with a
///   verified sending domain is the replacement.
/// * **The From address must be the authenticated account**, or an alias
///   verified inside it under "Send mail as". Gmail rejects anything else
///   outright, which surfaces here as a generic send failure.
///
/// ## Why a failed send is so hard to see
///
/// Whatever the provider, a rejection happens *after* Supabase has returned
/// `200`. So the failure looks like this, and looks like nothing else:
///
/// * the app reports the code was sent, because as far as it knows it was;
/// * `POST /otp` shows `200` in the Supabase auth log, because it succeeded;
/// * no mail arrives, and no error reaches the app, because the rejection
///   happened one hop further out than anything the client can observe.
///
/// If a code never arrives, check the **provider's own delivery log** before
/// looking at any of this code. Nothing in this file can detect it.
class EmailOtpService {
  EmailOtpService({SupabaseClient? client})
    : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  /// Seconds before "resend" becomes available.
  ///
  /// Sixty, not thirty, and it is not arbitrary: it matches the project's
  /// `auth.email.max_frequency` of one minute exactly. A shorter cooldown
  /// would offer a button that the server then refuses, and a refused resend
  /// reads to the user as the code being broken rather than as them being
  /// early.
  static const Duration resendCooldown = Duration(seconds: 60);

  static const int codeLength = 6;

  /// The signed-in account's address. The step never lets this be edited.
  String? get currentEmail => _client.auth.currentUser?.email;

  /// Mails a fresh code and returns the address it went to.
  Future<String> sendCode() async {
    final String? email = currentEmail;

    if (email == null || email.isEmpty) {
      throw const RbCarsFailure(
        'This account has no email address on file. Sign in again and retry.',
      );
    }

    try {
      await _client.auth.signInWithOtp(
        email: email,
        // Never invent an account from this screen - see the class comment.
        shouldCreateUser: false,
      );
      return email;
    } on AuthException catch (error) {
      _log('sendCode', error);
      throw RbCarsFailure(_describeSend(error));
    } catch (error) {
      _log('sendCode', error);
      throw const RbCarsFailure(
        'Could not reach the server. Check your connection and try again.',
      );
    }
  }

  /// Checks a typed code.
  ///
  /// GoTrue does the comparison; the app never sees the correct answer. A
  /// success returns a refreshed session for the same user, which
  /// `supabase_flutter` installs - harmless, since they were already signed in
  /// as that user.
  Future<void> verifyCode(String token) async {
    final String trimmed = token.trim();

    if (trimmed.length != codeLength) {
      throw RbCarsFailure('Enter the $codeLength-digit code.');
    }

    final String? email = currentEmail;
    if (email == null || email.isEmpty) {
      throw const RbCarsFailure('Sign in again and retry.');
    }

    try {
      await _client.auth.verifyOTP(
        type: OtpType.email,
        email: email,
        token: trimmed,
      );
    } on AuthException catch (error) {
      _log('verifyCode', error);
      throw RbCarsFailure(_describeVerify(error));
    }
  }

  // ------------------------------------------------------------ diagnostics
  //
  // Two mappers, not one. The same GoTrue failure means different things
  // depending on which call raised it: `over_email_send_rate_limit` on a send
  // is "wait before asking again", while a 400 on a verify is almost always a
  // mistyped code. A single mapper had to guess, and guessed wrong often
  // enough that the message stopped being useful.
  //
  // Both prefer `AuthException.code` over the message text. Codes are a
  // documented contract; the prose is not, and it has changed under us before.
  // The message is only read as a fallback for older responses that carry no
  // code at all.

  /// Why the mail could not be sent.
  String _describeSend(AuthException error) {
    final String code = error.code ?? '';
    final String message = error.message.toLowerCase();

    // Rate limit. Two flavours: the per-user frequency cap and the project's
    // hourly ceiling. Both mean wait, so both say so.
    if (code == 'over_email_send_rate_limit' ||
        code == 'over_request_rate_limit' ||
        message.contains('security purposes') ||
        message.contains('rate limit')) {
      return 'Too many requests. Wait a minute, then try again.';
    }

    // The send itself failed at the mail provider. Distinct from a rate limit
    // and worth its own message: retrying immediately is reasonable here,
    // whereas retrying into a rate limit only makes it worse.
    if (code == 'unexpected_failure' ||
        message.contains('error sending') ||
        error.statusCode == '500') {
      return 'The email could not be sent. This is our mail service, not '
          'anything you did - try again in a moment.';
    }

    if (code == 'email_address_invalid' || code == 'validation_failed') {
      return 'That address was rejected as invalid. Sign in again and retry.';
    }

    // The provider refused this recipient outright. On a free SMTP tier with
    // no verified sending domain this is the usual answer for any address
    // other than the provider account's own - see the class comment.
    //
    // The user is told the one thing they can act on; the operator-facing
    // detail goes to the debug log rather than into copy that would read as
    // gibberish to a client.
    if (code == 'email_address_not_authorized') {
      return 'We are not able to send to that address. Try another one, or '
          'contact support.';
    }

    if (code == 'email_provider_disabled' || code == 'signup_disabled') {
      return 'Email sign-in is switched off on this project right now.';
    }

    if (code == 'user_not_found' || message.contains('not found')) {
      return 'We could not find that account. Sign in again and retry.';
    }

    return 'Could not send the code. Try again in a moment.';
  }

  /// Why the typed code was refused.
  ///
  /// These may name the Resend button: by the time a code is being verified,
  /// the boxes are on screen and that button is beside them. The send-side
  /// messages above cannot, because the first send happens on a branch whose
  /// only button reads "Send code".
  String _describeVerify(AuthException error) {
    final String code = error.code ?? '';
    final String message = error.message.toLowerCase();

    // Expired and wrong are both 400s and feel identical to the user, but the
    // remedy differs: one needs a new code, the other needs a closer look at
    // the one they have.
    if (code == 'otp_expired' || message.contains('expired')) {
      return 'That code has expired. Tap resend to get a new one.';
    }

    if (code == 'over_request_rate_limit' ||
        message.contains('security purposes')) {
      return 'Too many attempts. Wait a minute before trying again.';
    }

    if (code == 'validation_failed' ||
        message.contains('invalid') ||
        message.contains('token')) {
      return 'That code is not right. Check it and try again.';
    }

    return 'We could not confirm that code. Tap resend for a new one.';
  }

  void _log(String action, Object error) {
    if (!kDebugMode) return;

    debugPrint('EmailOtpService.$action failed: $error');

    // The hint that saves the most time, printed where somebody debugging a
    // missing code will actually be looking. A send that fails at the provider
    // is indistinguishable from a broken request at this layer.
    if (action == 'sendCode') {
      debugPrint(
        '  Note: the rejection may be at the mail provider, after Supabase '
        'returned 200. Check the sender address matches the authenticated '
        'account, and the provider daily limit, before this code.',
      );
    }
  }
}
