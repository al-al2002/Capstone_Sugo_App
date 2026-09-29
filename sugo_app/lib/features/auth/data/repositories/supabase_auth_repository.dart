import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_env.dart';
import '../../../../core/errors/auth_failure.dart';
import '../../../../core/utils/validators.dart';
import '../models/app_user.dart';
import 'auth_repository.dart';
import '../../../../core/services/push_notification_service.dart';

/// Supabase-backed implementation of [AuthRepository].
///
/// Every method funnels errors through [AuthFailureMapper] so callers only ever
/// see an [AuthFailure] with copy that is safe to show to a user.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  @override
  AppUser? get currentUser {
    final User? user = _auth.currentUser;
    return user == null ? null : AppUser.fromSupabase(user);
  }

  @override
  Stream<AppUser?> authStateChanges() {
    return _auth.onAuthStateChange.map((AuthState state) {
      final User? user = state.session?.user;
      return user == null ? null : AppUser.fromSupabase(user);
    });
  }

  @override
  Future<AppUser> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final AuthResponse response = await _auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      final User? user = response.user;
      if (user == null) {
        throw const AuthFailure('Login failed. Please try again.');
      }
      return AppUser.fromSupabase(user);
    } catch (error, stackTrace) {
      _log('signInWithEmail', error, stackTrace);
      throw AuthFailureMapper.map(error);
    }
  }

  @override
  Future<SignUpResult> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
    required String phone,
  }) async {
    try {
      final AuthResponse response = await _auth.signUp(
        email: email.trim().toLowerCase(),
        password: password,
        // Stored on the auth user; a database trigger copies these into the
        // `profiles` table (see supabase/migrations).
        data: <String, dynamic>{
          'full_name': fullName.trim(),
          'phone': Validators.normalizePhone(phone),
        },
        emailRedirectTo: AppEnv.authRedirectUrl,
      );

      final User? user = response.user;
      if (user == null) {
        throw const AuthFailure('Sign up failed. Please try again.');
      }

      return SignUpResult(
        user: AppUser.fromSupabase(user),
        // No session means the project has email confirmation switched on.
        needsEmailVerification: response.session == null,
      );
    } catch (error, stackTrace) {
      _log('signUpWithEmail', error, stackTrace);
      throw AuthFailureMapper.map(error);
    }
  }

  /// Mails the `recovery` template, which since 2026-09-28 carries a
  /// six-digit `{{ .Token }}` instead of a link
  /// (`supabase/templates/recovery.html`, pushed with `supabase config push`).
  ///
  /// No `redirectTo`: there is no link in the mail to redirect.
  @override
  Future<void> sendPasswordResetCode(String email) async {
    try {
      await _auth.resetPasswordForEmail(email.trim().toLowerCase());
    } catch (error, stackTrace) {
      _log('sendPasswordResetCode', error, stackTrace);
      throw AuthFailureMapper.map(error);
    }
  }

  /// GoTrue compares the code; the app never sees the right answer. Success
  /// installs a session for that account, which is what lets
  /// [updatePassword] run without the old password.
  @override
  Future<void> verifyPasswordResetCode({
    required String email,
    required String code,
  }) async {
    try {
      await _auth.verifyOTP(
        type: OtpType.recovery,
        email: email.trim().toLowerCase(),
        token: code.trim(),
      );
    } catch (error, stackTrace) {
      _log('verifyPasswordResetCode', error, stackTrace);
      throw AuthFailureMapper.map(error);
    }
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    try {
      await _auth.updateUser(UserAttributes(password: newPassword));
    } catch (error, stackTrace) {
      _log('updatePassword', error, stackTrace);
      throw AuthFailureMapper.map(error);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      // Before `signOut`, while the session still authorises the delete. After
      // it the row would be orphaned and a shared handset would keep receiving
      // this account's job notifications.
      await PushNotificationService.unregister();
      await _auth.signOut();
    } catch (error, stackTrace) {
      _log('signOut', error, stackTrace);
      throw AuthFailureMapper.map(error);
    }
  }

  void _log(String operation, Object error, StackTrace stackTrace) {
    if (kDebugMode) {
      debugPrint('[AuthRepository] $operation failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
