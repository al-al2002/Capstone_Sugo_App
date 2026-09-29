/// Artwork bundled from `assets/images/` (declared in pubspec.yaml).
///
/// Every file here is cut from the full-size sources in `assets/source/` by
/// `tool/prepare_brand_images.py`. The sources themselves are not bundled.
class AppAssets {
  const AppAssets._();

  static const String _images = 'assets/images';

  /// The splash poster (941x1672 JPEG): lockup, "From your home to our shop",
  /// the two service paths, the technician, the house, the shop and the van.
  ///
  /// Cut from `splash 2.png` by `tool/prepare_brand_images.py`, which paints
  /// out the "Get Started" button drawn into the picture - the app draws a
  /// real one in that space once it has finished loading.
  static const String splash = '$_images/splash_art.jpg';

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
