import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'notification_router.dart';
import 'supabase_service.dart';

/// Registers this device with FCM so the server can reach it while the app is
/// closed.
///
/// ## What push is for here, and what it is not
///
/// The moments someone needs to hear about while the app is closed:
///
///   * a new chat message, to the other person on the job;
///   * a pickup job moving - on the way, collected, at the shop, being
///     repaired, out for delivery or ready to collect, delivered - to the
///     client;
///   * the client choosing pickup or delivery, to the technician;
///   * a technician being booked, and a job being completed (with a nudge to
///     rate), to the other side;
///   * a technician running late, to the client.
///
/// The server decides all of these (`notify-event`, `job-response`,
/// `tracking-eta`); this class only makes the device reachable. While the app
/// is open the same news arrives over Supabase Realtime, which is why nothing
/// here shows a notification in the foreground.
///
/// ## Why registration is its own step
///
/// An FCM token identifies an app INSTALL, not a user. Signing in attaches this
/// install to an account; signing out has to detach it, or the next person to
/// use the handset receives the previous account's notifications. [register]
/// and [unregister] are those two halves, and both are safe to call more than
/// once.
///
/// ## Failure is silent by design
///
/// Every method here swallows its errors. A missing `google-services.json`, a
/// denied permission, an offline device - none of them should stop a user
/// signing in. The consequence of failure is one missing notification, and the
/// delay banner still reaches them the moment they open the app.
class PushNotificationService {
  const PushNotificationService._();

  /// Written by `register_device_token`, the only write path into
  /// `device_tokens` - see the migration for why an insert policy could not do
  /// the job.
  static const String _registerFn = 'register_device_token';

  static String get _platform {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    return 'android';
  }

  /// Asks for notification permission and stores this device's token.
  ///
  /// Call after sign-in. On Android 13+ this shows the runtime prompt; on older
  /// Android it is granted by manifest and returns immediately.
  static Future<void> register() async {
    try {
      final FirebaseMessaging messaging = FirebaseMessaging.instance;

      // Taps. Wired before the permission check: a notification delivered
      // under an earlier grant can still be tapped after one is withdrawn.
      _listenForTaps(messaging);

      final NotificationSettings settings = await messaging.requestPermission();

      // Denied is a legitimate answer, not an error. The client simply gets the
      // in-app banner instead, so nothing further is attempted - registering a
      // token we may never be allowed to use would just be dead rows.
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      final String? token = await messaging.getToken();
      if (token != null) await _store(token);

      // FCM rotates tokens on reinstall, restore and occasionally on its own.
      // Without this listener the row would silently go stale and the client
      // would stop receiving anything, with no visible symptom.
      messaging.onTokenRefresh.listen(_store);
    } catch (error) {
      _log('register', error);
    }
  }

  /// Detaches this device from the signed-in account.
  ///
  /// Call BEFORE `signOut`, while the session still authorises the delete. Done
  /// afterwards the row would be orphaned and a shared phone would keep
  /// receiving the previous account's job updates.
  static Future<void> unregister() async {
    try {
      final String? token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;

      await SupabaseService.client
          .from('device_tokens')
          .delete()
          .eq('token', token);
    } catch (error) {
      _log('unregister', error);
    }
  }

  static bool _listeningForTaps = false;

  /// Hands a tapped notification to [NotificationRouter], for the dashboard
  /// to open the chat or job it is about.
  ///
  /// Two ways a tap arrives: `onMessageOpenedApp` when the app was running in
  /// the background, and `getInitialMessage` when the tap is what started it.
  /// Registered once - `register` runs on every sign-in.
  static void _listenForTaps(FirebaseMessaging messaging) {
    if (_listeningForTaps) return;
    _listeningForTaps = true;

    FirebaseMessaging.onMessageOpenedApp.listen(
      (RemoteMessage message) => NotificationRouter.deliver(message.data),
    );
    messaging.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) NotificationRouter.deliver(message.data);
    });
  }

  static Future<void> _store(String token) async {
    try {
      await SupabaseService.client.rpc(
        _registerFn,
        params: <String, dynamic>{'p_token': token, 'p_platform': _platform},
      );
    } catch (error) {
      _log('_store', error);
    }
  }

  static void _log(String action, Object error) {
    if (kDebugMode) {
      debugPrint('PushNotificationService.$action failed: $error');
    }
  }
}
