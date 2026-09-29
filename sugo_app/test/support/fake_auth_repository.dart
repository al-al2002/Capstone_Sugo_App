import 'dart:async';

import 'package:sugo_app/core/errors/auth_failure.dart';
import 'package:sugo_app/features/auth/data/models/app_user.dart';
import 'package:sugo_app/features/auth/data/repositories/auth_repository.dart';

/// In-memory [AuthRepository] so the auth screens can be tested without a
/// network or a Supabase project.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.failure, this.needsEmailVerification = false});

  /// When set, every call throws this instead of succeeding.
  final AuthFailure? failure;
  final bool needsEmailVerification;

  final StreamController<AppUser?> _controller =
      StreamController<AppUser?>.broadcast();
  final List<String> calls = <String>[];

  AppUser? _user;

  @override
  AppUser? get currentUser => _user;

  @override
  Stream<AppUser?> authStateChanges() => _controller.stream;

  @override
  Future<AppUser> signInWithEmail({
    required String email,
    required String password,
  }) async {
    calls.add('signInWithEmail:$email');
    final AuthFailure? error = failure;
    if (error != null) throw error;
    _user = AppUser(id: 'test-user', email: email, fullName: 'Test User');
    _controller.add(_user);
    return _user!;
  }

  @override
  Future<SignUpResult> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
    String? phone,
  }) async {
    calls.add('signUpWithEmail:$email:$fullName:$phone');
    final AuthFailure? error = failure;
    if (error != null) throw error;
    final AppUser user = AppUser(
      id: 'test-user',
      email: email,
      fullName: fullName,
      phone: phone,
    );
    if (!needsEmailVerification) {
      _user = user;
      _controller.add(user);
    }
    return SignUpResult(
      user: user,
      needsEmailVerification: needsEmailVerification,
    );
  }

  /// The only code [verifyPasswordResetCode] accepts.
  static const String validResetCode = '123456';

  @override
  Future<void> sendPasswordResetCode(String email) async {
    calls.add('sendPasswordResetCode:$email');
    final AuthFailure? error = failure;
    if (error != null) throw error;
  }

  @override
  Future<void> verifyPasswordResetCode({
    required String email,
    required String code,
  }) async {
    calls.add('verifyPasswordResetCode:$email:$code');
    if (code != validResetCode) {
      throw const AuthFailure(
        'That code is wrong or has expired. Check it, or tap resend for a '
        'new one.',
        code: 'otp_expired',
      );
    }
    _user = AppUser(id: 'test-user', email: email, fullName: 'Test User');
    _controller.add(_user);
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    calls.add('updatePassword');
    final AuthFailure? error = failure;
    if (error != null) throw error;
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    _user = null;
    _controller.add(null);
  }

  void dispose() => _controller.close();
}
