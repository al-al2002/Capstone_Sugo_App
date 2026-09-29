/// Artwork bundled from `assets/images/` (declared in pubspec.yaml).
///
/// Where a file is absent the auth header falls back to the illustration it
/// paints in code, so a missing export never breaks the build.
class AppAssets {
  const AppAssets._();

  static const String _images = 'assets/images';

  static const String logo = '$_images/sugo_logo.png';

  /// Header banner for the login tab (1717x916). Carries the wordmark
  /// and tagline, so no widget logo is drawn over it.
  static const String loginHero = '$_images/login.png';

  /// Header banner for the register tab (1536x1024). Carries the wordmark,
  /// tagline and the Diagnose/Repair/Done chips. Note the capital R - asset
  /// paths are case-sensitive in the bundle even on Windows.
  static const String registerHero = '$_images/Register.png';
  static const String googleLogo = '$_images/google.png';

  /// The splash poster (941x1672 JPEG): lockup, "From your home to our shop",
  /// the two service paths, the technician, the house, the shop and the van.
  ///
  /// Cut from `splash 2.png` by `tool/prepare_brand_images.py`, which paints
  /// out the "Get Started" button drawn into the picture - the app draws a
  /// real one in that space once it has finished loading.
  static const String splash = '$_images/splash_art.jpg';

  /// The cover behind the Profile tab's identity card (1200x564): the emblem
  /// from the app icon, cropped wide by `tool/prepare_brand_images.py`.
  ///
  /// The same for every account - there is no per-user cover upload. Swap this
  /// file for a purpose-made wide banner and the card picks it up unchanged.
  static const String profileCover = '$_images/profile_cover.png';

  /// The emblem alone - house, wrench, swoosh and van - on the icon's navy
  /// (512x512). The app's small logo mark, and the disc at the centre of the
  /// matching screen. Cut from the app icon by `tool/prepare_brand_images.py`
  /// with the wordmark painted out.
  static const String brandEmblem = '$_images/brand_emblem.png';

  /// The full SUGO lockup on navy (900x900 JPEG), the login screen's header.
  /// Cut from the app icon by `tool/prepare_brand_images.py`.
  static const String brandHeader = '$_images/brand_header.jpg';

  /// The technician from the splash poster (520x520 JPEG), SUGO cap and all,
  /// for the home screen's "Need a tech fix?" banner.
  static const String bannerTechnician = '$_images/banner_technician.jpg';
}
