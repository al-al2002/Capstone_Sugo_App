import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_env.dart';

/// Owns Supabase initialisation and exposes the shared client.
class SupabaseService {
  const SupabaseService._();

  /// Call once, before `runApp`.
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: AppEnv.supabaseUrl,
      // The legacy anon JWT is accepted here; `anonKey` is deprecated.
      publishableKey: AppEnv.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        // Keeps the session in secure storage so the user stays logged in.
        authFlowType: AuthFlowType.pkce,
      ),
    );
  }

  static SupabaseClient get client => Supabase.instance.client;

  static GoTrueClient get auth => client.auth;
}
