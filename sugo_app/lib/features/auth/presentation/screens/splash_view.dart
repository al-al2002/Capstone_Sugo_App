import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_assets.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/theme/app_elevation.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../widgets/splash_artwork.dart';
import '../widgets/splash_loader.dart';

/// The launch screen: the SUGO poster, a loading animation, then "Get
/// started".
///
/// ## What happens, in order (2026-09-29)
///
/// 1. The poster fades in, and the van starts along its road at the bottom -
///    [SplashLoader].
/// 2. The loader stays until **both**: Supabase has restored (or rejected) the
///    saved session - [ready] - and [minimumLoading] has passed.
/// 3. Then it depends on who is holding the phone:
///    * **Signed in**: nothing to press. The splash hands over on its own and
///      the gate opens their dashboard. Making someone who is already in tap
///      "Get started" on every launch would be a toll, not a welcome.
///    * **Signed out**: the loader gives way to a real "Get started" button,
///      in the place the poster's drawn one used to be. Pressing it opens
///      sign-in.
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

  /// Called when the splash is done: on "Get started", or on its own for a
  /// signed-in user once loading has finished.
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

  bool get _offerStart =>
      !_loading && !widget.signedIn && widget.onFinished != null;

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
    // Useful work for the wait: the sign-in header is the next thing a
    // signed-out person sees, so it is decoded now rather than popping in.
    precacheImage(const AssetImage(AppAssets.brandHeader), context);
  }

  @override
  void didUpdateWidget(SplashView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeHandOver();
  }

  /// A signed-in user is let straight through once loading has finished.
  void _maybeHandOver() {
    if (_loading || !widget.signedIn || widget.onFinished == null) return;
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
    final bool still = AppMotion.reduced(context);

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
                        // One height for both, so the button replaces the
                        // loader without the poster above them moving.
                        height: 64,
                        child: AnimatedSwitcher(
                          duration: still ? Duration.zero : AppMotion.slow,
                          switchInCurve: AppMotion.emphasized,
                          switchOutCurve: AppMotion.exit,
                          transitionBuilder:
                              (Widget child, Animation<double> animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0, 0.25),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                );
                              },
                          child: _offerStart
                              ? _GetStartedButton(
                                  key: const ValueKey<String>('start'),
                                  onPressed: _finish,
                                )
                              : const Center(
                                  key: ValueKey<String>('loading'),
                                  child: SplashLoader(),
                                ),
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

/// "Get started", where the poster's drawn button used to be.
///
/// Pill-shaped, full width and cyan, like the one in the artwork - but with
/// navy words where the artwork had white. White on that cyan is about 2:1
/// and unreadable in sunlight; navy on it is 7.8:1. A darker blue fill was
/// tried first and all but vanished into the poster's own blue. It floats over
/// the poster, so it is the one control on the screen with a shadow.
class _GetStartedButton extends StatelessWidget {
  const _GetStartedButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSizes.pillRadius),
          boxShadow: AppElevation.lg,
        ),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.cyan,
              foregroundColor: AppColors.navy,
              shape: const StadiumBorder(),
              // Names the family: a button's textStyle replaces the inherited
              // one rather than merging with it.
              textStyle: AppTextStyles.button.copyWith(fontSize: 16),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('Get started'),
                SizedBox(width: AppSizes.sm),
                Icon(Icons.arrow_forward_rounded, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
