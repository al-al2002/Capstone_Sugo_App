import '../models/app_user.dart';

/// Result of a sign-up attempt.
///
/// When the project requires email confirmation, Supabase creates the user but
/// returns no session - the UI has to tell the user to check their inbox
/// instead of navigating them into the app.
class SignUpResult {
  const SignUpResult({
    required this.user,
    required this.needsEmailVerification,
  });

  final AppUser? user;
  final bool needsEmailVerification;
}

/// Contract the auth screens depend on.
///
/// Keeping this abstract means the UI can be tested against a fake and the
/// backend could be swapped without touching presentation code.
abstract class AuthRepository {
  /// Emits the current user on subscribe, then on every auth state change.
  Stream<AppUser?> authStateChanges();

  AppUser? get currentUser;

  Future<AppUser> signInWithEmail({
    required String email,
    required String password,
  });

  Future<SignUpResult> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,

    /// Philippine mobile number as typed; the implementation normalises it to
    /// E.164 before storing it in user metadata.
    required String phone,
  });

  // Google and Facebook sign-in were removed on 2026-09-28 at the client's
  // request: SUGO signs in with email and password only.

  // ----------------------------------------------------- forgot password
  //
  // Three calls, one per screen of the flow: the email is sent a six-digit
  // code, the code is checked, then a new password is set. See
  // `ForgotPasswordController` for why it is a code and not a link.

  /// Emails a six-digit reset code to [email].
  ///
  /// Succeeds whether or not an account exists for that address - the server
  /// answers the same either way, so this screen cannot be used to find out
  /// who has a SUGO account.
  Future<void> sendPasswordResetCode(String email);

  /// Checks the code. On success the person is signed in, which is what
  /// allows [updatePassword] to run next.
  Future<void> verifyPasswordResetCode({
    required String email,
    required String code,
  });

  /// Sets a new password for the signed-in account.
  Future<void> updatePassword(String newPassword);

  Future<void> signOut();
}
