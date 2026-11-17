import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_assets.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../widgets/splash_artwork.dart';
import '../widgets/splash_loader.dart';

/// The launch screen: the SUGO scene, a loading animation, then the app.
///
/// Since 2026-11-16 the scene is drawn ([SplashArtwork]) rather than a poster
/// image, in SUGO's own palette and with the real emblem.
///
/// ## What happens, in order (2026-09-29)
///
/// 1. The poster fades in, and the van starts along its road at the bottom -
///    [SplashLoader].
/// 2. The loader stays until **both**: Supabase has restored (or rejected) the
///    saved session - [ready] - and [minimumLoading] has passed.
/// 3. The splash hands over automatically. Signed-in users continue to their
///    dashboard, while signed-out users continue to sign-in.
///
/// ## Why there is a minimum, and what it costs
///
/// Restoring a session usually takes a few hundred milliseconds, so without a
/// floor the loading animation would flash past before anyone saw it - and
/// you asked for it to be seen. [minimumLoading] is 1.5 seconds, spent on
/// real work too: the login header is decoded during it, so sign-in opens
/// with its artwork already drawn. That is the cost, stated plainly: a cold
/// launch of a signed-in user now takes at least 1.5 seconds, down from the
/// 3.9 the previous animated splash took.
///
/// ## Only once per launch
///
/// [hasPlayed] remembers that the splash has had its say, so the gate's later
/// trips through "loading" - a sign-out, a profile refresh - do not replay it.
/// Those show this screen without [onFinished]: the poster and the loader,
/// until the gate moves on by itself.
class SplashView extends StatefulWidget {
  const SplashView({
    super.key,
    this.onFinished,
    this.ready = false,
    this.signedIn = false,
  });

  /// Called when the splash is done once loading has finished.
  ///
  /// Null means "nobody is waiting for this" - the splash then shows the
  /// loader for as long as it is on screen, and whatever put it there decides
  /// when it goes.
  final VoidCallback? onFinished;

  /// True once the saved session has been restored or rejected.
  final bool ready;

  /// Whether that restore found someone signed in.
  final bool signedIn;

  /// The shortest time the loader shows. See the class note for why.
  static const Duration minimumLoading = Duration(milliseconds: 1500);

  /// Whether the splash has already had its say in this process.
  ///
  /// Static because it is a fact about the launch, not about any one widget:
  /// the gate rebuilds this screen several times on the way to a dashboard.
  static bool hasPlayed = false;

  /// Test hook: puts it back to a fresh launch.
  @visibleForTesting
  static void debugReset() => hasPlayed = false;

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> {
  Timer? _floor;
  late bool _floorPassed = SplashView.hasPlayed;
  bool _handedOver = false;
  bool _precached = false;

  bool get _loading => !(widget.ready && _floorPassed);

  @override
  void initState() {
    super.initState();
    if (!_floorPassed) {
      _floor = Timer(SplashView.minimumLoading, () {
        if (!mounted) return;
        setState(() => _floorPassed = true);
        _maybeHandOver();
      });
    }
    _maybeHandOver();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    // Useful work for the wait: the emblem is drawn on the splash and again
    // on the sign-in header (both drawn in code since 2026-11-16), so it is
    // decoded once, now, rather than popping in.
    precacheImage(const AssetImage(AppAssets.brandEmblem), context);
  }

  @override
  void didUpdateWidget(SplashView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeHandOver();
  }

  /// Continue to the appropriate destination once loading has finished.
  void _maybeHandOver() {
    if (_loading || widget.onFinished == null) return;
    // After this frame, never during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
  }

  void _finish() {
    if (_handedOver || !mounted) return;
    _handedOver = true;
    SplashView.hasPlayed = true;
    widget.onFinished?.call();
  }

  @override
  void dispose() {
    _floor?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The poster is dark blue edge to edge, so the status and navigation
      // icons have to be light to be visible at all.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.navy,
        body: Stack(
          children: <Widget>[
            const Positioned.fill(child: SplashArtwork()),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.only(bottom: AppSizes.xl),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.screenPadding + AppSizes.md,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: SizedBox(
                        // Keep the loader anchored while the session restores.
                        height: 64,
                        child: const Center(
                          key: ValueKey<String>('loading'),
                          child: SplashLoader(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
