import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/app_user.dart';
import '../../data/repositories/auth_repository.dart';

/// Session-level auth state, used by the gate widget to decide whether to show
/// the login flow or the app.
class AuthController extends ChangeNotifier {
  AuthController(this._repository) {
    _user = _repository.currentUser;
    _subscription = _repository.authStateChanges().listen(
      (AppUser? user) {
        _user = user;
        _initialized = true;
        notifyListeners();
      },
      onError: (Object error) {
        _initialized = true;
        notifyListeners();
      },
    );
  }

  final AuthRepository _repository;
  late final StreamSubscription<AppUser?> _subscription;

  AppUser? _user;
  bool _initialized = false;

  AppUser? get user => _user;

  bool get isAuthenticated => _user != null;

  /// False until Supabase has restored (or rejected) the persisted session.
  bool get isInitialized => _initialized;

  Future<void> signOut() => _repository.signOut();

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
