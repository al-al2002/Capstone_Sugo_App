/// Environment configuration for the SUGO app.
///
/// Values default to the development Supabase project but can be overridden at
/// build time without touching the source, e.g.
///
/// ```sh
/// flutter run \
///   --dart-define=SUPABASE_URL=https://your-project.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=your-anon-key
/// ```
///
/// The publishable key is safe to ship in a client: it only grants the `anon`
/// role and every table is still guarded by Row Level Security policies.
///
/// ## Why this is `sb_publishable_...` and not a JWT
///
/// The project's original anon key was a legacy JWT. Supabase has since turned
/// legacy keys off for this project, and they are now refused by all three
/// services - REST and Auth answer 401, and the functions gateway answers
/// `UNAUTHORIZED_LEGACY_JWT` before a function is even invoked. A build
/// carrying the old key cannot sign anybody in.
///
/// The replacement is the project's publishable key, which is the same kind of
/// public credential in a new format. If it ever stops working, the current one
/// is under Project Settings -> API Keys, or:
///
/// ```sh
/// npx supabase projects api-keys --project-ref nlchvhygejurjvuyluwe
/// ```
///
/// Take the entry whose `type` is `publishable`. Never the `secret` one - that
/// is the service role, and it bypasses every RLS policy in the database.
class AppEnv {
  const AppEnv._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://nlchvhygejurjvuyluwe.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_debyibYaljXo1fNyaVyC3g_Ede2Stcu',
  );

  /// Custom scheme used to return to the app after an OAuth or password-reset
  /// redirect. Must match the Android intent-filter and the iOS URL type, and
  /// be listed under Authentication -> URL Configuration in Supabase.
  static const String authRedirectUrl = 'io.supabase.sugo://login-callback/';

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  // ---------------------------------------------------------------- MapTiler

  /// MapTiler key for the `flutter_map` tile layer.
  ///
  /// This one deliberately ships in the client: the phone itself downloads the
  /// tiles, so there is nowhere to hide it. MapTiler is built for that - you
  /// restrict the key by origin/package in their dashboard rather than keeping
  /// it secret. Contrast with the TomTom and OpenWeatherMap keys, which live
  /// as Supabase secrets because only the edge function ever calls them.
  ///
  /// A default is baked in so plain `flutter run` shows the map, matching how
  /// [supabaseUrl] and [supabaseAnonKey] above already work. Override it per
  /// build without touching source:
  ///
  /// ```sh
  /// flutter run --dart-define=MAPTILER_KEY=a_different_key
  /// ```
  static const String mapTilerKey = String.fromEnvironment(
    'MAPTILER_KEY',
    defaultValue: 'J7Add9jnneL7324URxfQ',
  );

  static bool get hasMapTilerKey => mapTilerKey.isNotEmpty;

  /// Map style slug. `streets-v2` reads well for a location picker; swap for
  /// `basic-v2` if you want a quieter background under markers.
  static const String mapTilerStyle = String.fromEnvironment(
    'MAPTILER_STYLE',
    defaultValue: 'streets-v2',
  );

  /// XYZ template `flutter_map` expects. Empty when no key is configured, so
  /// callers should gate on [hasMapTilerKey] first.
  static String get mapTilerTileUrl {
    if (!hasMapTilerKey) return '';
    return 'https://api.maptiler.com/maps/$mapTilerStyle/{z}/{x}/{y}.png'
        '?key=$mapTilerKey';
  }

  // ----------------------------------------------------------- Traffic tiles

  /// Template for the TomTom traffic overlay, served through our own edge
  /// function rather than from `api.tomtom.com` directly.
  ///
  /// This is the deliberate counterpart to [mapTilerKey] above. MapTiler's key
  /// ships in the client because there is nowhere to hide it; TomTom's does
  /// not, because `TOMTOM_API_KEY` is also what Stage 2 scoring runs on, so
  /// leaking it costs more than map quota. The `traffic-tile` function holds
  /// the key, range-checks the coordinates and requires a signed-in caller.
  ///
  /// The cost of that choice is one edge-function invocation per tile, which is
  /// why the overlay is off until the client turns it on.
  static String get trafficTileUrl =>
      '$supabaseUrl/functions/v1/traffic-tile?z={z}&x={x}&y={y}';

  /// Shown in the required attribution bar on every MapTiler map.
  static const String mapAttribution = 'MapTiler / OpenStreetMap contributors';

  // ------------------------------------------------------------ default view

  /// Davao City centre - the fallback camera position and the default job
  /// location before the client moves the pin.
  static const double defaultLatitude = 7.0731;
  static const double defaultLongitude = 125.6128;
}
