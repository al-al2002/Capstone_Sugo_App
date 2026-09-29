import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/services/connectivity_monitor.dart';
import 'core/services/supabase_service.dart';
import 'firebase_options.dart';

/// Two back-ends start here, and they do different jobs.
///
/// **Supabase** is the platform: accounts, profiles, jobs, matching, chat,
/// storage and every row of business data. `SupabaseService` owns it.
///
/// **Firebase** is used for one thing only - phone number verification. Its
/// free tier sends real SMS, which is what a Philippine capstone demo can
/// actually afford; Supabase's phone provider needs a paid Twilio account
/// behind it.
///
/// The two are deliberately NOT a single sign-in system. A person's SUGO
/// identity is their Supabase account and nothing else. Firebase is a
/// *verification transport*: it proves someone controls a phone number, and
/// that proof is then recorded against their Supabase profile. Nobody signs in
/// to SUGO with Firebase, and a Firebase user is not a SUGO user.
///
/// Keeping that boundary explicit is what stops two competing notions of "who
/// is logged in" from appearing later.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Transparent status bar so the illustrated auth header runs to the top.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );

  // Supabase first, because it is the one the app cannot run without: the auth
  // gate, the router and every screen read from it. A failure here should be
  // loud.
  await SupabaseService.initialize();

  // Firebase second, and non-fatal.
  //
  // It backs one optional step. If the native config is missing - a fresh
  // clone before `flutterfire configure`, or a platform nobody registered -
  // the whole app should not refuse to start over a phone field. The phone
  // step surfaces its own error when it is actually reached.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (error, stackTrace) {
    if (kDebugMode) {
      debugPrint(
        'Firebase.initializeApp failed: $error\n'
        'Phone verification will not work until `flutterfire configure` has '
        'been run for this platform.\n$stackTrace',
      );
    }
  }

  // Starts probing the server so the "You're offline" strip can appear. See
  // `ConnectivityMonitor` for why it checks Supabase rather than Wi-Fi state.
  ConnectivityMonitor.instance.start();

  runApp(const SugoApp());
}
