import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import 'session_state.dart';
import '../services/push_notification_service.dart';

/// Loads the signed-in user's profile and technician status, and exposes the
/// one [LandingDestination] every navigation decision reads from.
///
/// ## Why this exists as its own controller
///
/// `AuthController` knows whether there is a session. It does not know whether
/// that session belongs to a client or a technician, because that lives in
/// `profiles.role`, not in the JWT. Rather than have `AuthGate` do a one-off
/// query, or have each dashboard re-check on entry, the lookup happens once
/// here and everything else reads [profile].
///
/// It listens to auth state itself, so a sign-in, a sign-out or a token refresh
/// reloads or clears the profile without any screen having to coordinate it.
///
/// ## Why two queries and not a join
///
/// `profiles` and `technicians` are read separately because a technician who
/// has registered but not finished onboarding has a `profiles` row and no
/// `technicians` row. An inner join would return nothing for exactly the user
/// who most needs to be routed somewhere useful. Both reads go straight through
/// RLS - each policy already restricts the row to `auth.uid()` - so no edge
/// function is involved.
class SessionController extends ChangeNotifier {
  SessionController({SupabaseClient? client})
    : _client = client ?? SupabaseService.client {
    _subscription = _client.auth.onAuthStateChange.listen(
      _handleAuthChange,
      onError: (Object error) {
        _error = 'Could not restore your session.';
        _isLoading = false;
        notifyListeners();
      },
    );

    // A session may already have been restored before this controller was
    // built, in which case no auth event will fire for it.
    if (_client.auth.currentUser != null) {
      unawaited(refresh());
    }
  }

  final SupabaseClient _client;
  late final StreamSubscription<AuthState> _subscription;

  SessionProfile? _profile;
  bool _isLoading = false;
  bool _initialized = false;
  String? _error;

  SessionProfile? get profile => _profile;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// False until the first load settles, so the gate can hold on a splash
  /// rather than flashing the login screen at a signed-in user.
  bool get isInitialized => _initialized;

  /// Name captured at sign-up, used to seed the profile that does not exist
  /// yet. Read from auth metadata because there is no `profiles` row to read.
  String? get authFullName {
    final Map<String, dynamic>? meta = _client.auth.currentUser?.userMetadata;
    return (meta?['full_name'] ?? meta?['name']) as String?;
  }

  String? get authPhone {
    final Map<String, dynamic>? meta = _client.auth.currentUser?.userMetadata;
    return (meta?['phone'] ?? _client.auth.currentUser?.phone) as String?;
  }

  /// The single routing decision for the whole app.
  LandingDestination get destination {
    if (!_initialized || _isLoading) return LandingDestination.loading;
    if (_client.auth.currentUser == null) return LandingDestination.auth;

    final SessionProfile? current = _profile;
    if (current == null) {
      // No profile row. Since `complete_registration()` is the only thing that
      // creates one, its absence means registration was never finished - a new
      // signup, or an abandoned one being resumed. Either way, start the flow.
      return LandingDestination.registration;
    }
    return current.destination;
  }

  Future<void> _handleAuthChange(AuthState state) async {
    if (state.session?.user == null) {
      _profile = null;
      _error = null;
      _initialized = true;
      _isLoading = false;
      notifyListeners();
      return;
    }

    // Attach this handset to the account that just signed in. Fire-and-forget:
    // it shows a permission prompt on Android 13+ and talks to FCM, neither of
    // which should hold up routing the user to their first screen. Safe to
    // repeat - `register_device_token` upserts on the token.
    unawaited(PushNotificationService.register());

    await refresh();
  }

  /// Re-reads the profile. Call after onboarding completes or verification
  /// changes, so the destination is recomputed.
  Future<void> refresh() async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      _profile = null;
      _initialized = true;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final Map<String, dynamic>? profileRow = await _client
          .from('profiles')
          .select(
            'id, full_name, avatar_url, phone, role, role_chosen_at, '
            'onboarding_completed_at, id_document_url, id_submitted_at, '
            'registration_status, registration_step, '
            'profile_setup_completed_at',
          )
          .eq('id', user.id)
          .maybeSingle();

      if (profileRow == null) {
        // Expected for anyone mid-registration. Leaving the profile null is
        // what routes them into the flow.
        _profile = null;
        return;
      }

      final UserRole role = UserRole.fromWire(profileRow['role'] as String?);

      Map<String, dynamic>? technicianRow;
      if (role == UserRole.technician) {
        // Only queried for technicians. A client has no row here and asking
        // would be a wasted round trip on every launch.
        technicianRow = await _client
            .from('technicians')
            .select(
              'id, is_verified, id_document_url, specialization',
            )
            .eq('id', user.id)
            .maybeSingle();
      }

      _profile = SessionProfile(
        userId: user.id,
        role: role,
        fullName:
            profileRow['full_name'] as String? ??
            user.userMetadata?['full_name'] as String?,
        avatarUrl: profileRow['avatar_url'] as String?,
        phone: profileRow['phone'] as String?,
        hasTechnicianRow: technicianRow != null,
        isVerified: technicianRow?['is_verified'] as bool? ?? false,
        roleChosenAt: _parseDate(profileRow['role_chosen_at']),
        onboardingCompletedAt: _parseDate(
          profileRow['onboarding_completed_at'],
        ),
        // `profiles` is the source of truth now that both roles submit one;
        // the technician column is a mirror kept for older rows.
        idDocumentUrl:
            profileRow['id_document_url'] as String? ??
            technicianRow?['id_document_url'] as String?,
        specialization: _parseStringList(technicianRow?['specialization']),
        registrationStatus:
            profileRow['registration_status'] as String? ?? 'incomplete',
        profileSetupCompletedAt: _parseDate(
          profileRow['profile_setup_completed_at'],
        ),
      );
    } on PostgrestException catch (error) {
      if (kDebugMode) debugPrint('SessionController.refresh: ${error.message}');
      _error = 'Could not load your profile.';
      _profile = null;
    } catch (error) {
      if (kDebugMode) debugPrint('SessionController.refresh: $error');
      _error = 'Could not load your profile.';
      _profile = null;
    } finally {
      _isLoading = false;
      _initialized = true;
      notifyListeners();
    }

    // Stamp completion the first time this account reaches a dashboard.
    //
    // Done here rather than in a screen because this is the object that
    // computes the destination - the same place that decides "you are
    // finished" is the place that records it, so the two cannot disagree.
    //
    // Deliberately not awaited: it is bookkeeping that takes the account out
    // of the abandoned-signup purge, and it must never delay or block someone
    // reaching their dashboard. A failure just means the next launch retries.
    unawaited(_stampCompletionIfFinished());
  }

  /// Marks registration finished once the destination is a real dashboard.
  Future<void> _stampCompletionIfFinished() async {
    final SessionProfile? current = _profile;
    if (current == null) return;
    if (current.hasCompletedOnboarding) return;

    // Since 20260907000001, reaching a dashboard is no longer proof that
    // registration finished - only an admin moving the account to `active`
    // is. Stamping completion for anyone else would take an unapproved
    // account out of the abandoned-signup purge and quietly protect it.
    if (!current.isRegistrationActive) return;

    final LandingDestination target = current.destination;
    final bool finished =
        target == LandingDestination.clientDashboard ||
        target == LandingDestination.technicianDashboard;

    if (!finished) return;

    try {
      await _client
          .from('profiles')
          .update(<String, dynamic>{
            'onboarding_completed_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', current.userId)
          .isFilter('onboarding_completed_at', null);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('SessionController.stampCompletion failed: $error');
      }
    }
  }

  static DateTime? _parseDate(Object? value) {
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }

  static List<String> _parseStringList(Object? value) {
    if (value is List) return value.whereType<String>().toList(growable: false);
    return const <String>[];
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
