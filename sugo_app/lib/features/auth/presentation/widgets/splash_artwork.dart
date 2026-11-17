import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/widgets/sugo_brand_cover.dart';
import '../../../../core/widgets/sugo_logo.dart';

/// The splash scene, edge to edge (2026-11-16).
///
/// ## Why it was redrawn
///
/// The splash was a poster image (`SUGO Service Partner Splash Screen.png`).
/// Like the login headers it was a saturated royal blue rather than SUGO
/// navy, and its logo was an older house-with-yellow-windows mark, not the
/// emblem on the app icon. The user asked for artwork that suits SUGO.
///
/// It is now drawn from the app's own pieces: the illustrated Davao cover
/// ([SugoBrandCover], dusk - the city's windows lit, the booking route
/// drawing itself towards the service van), and the real lockup
/// ([SugoLogoMark] and [SugoLogo]). The poster's line - "your trusted onsite
/// and errand service partner in Davao" - is kept, with Davao in the accent.
///
/// ## The entrance, once
///
/// The emblem pops in with a single soft halo ring spreading from it, the
/// wordmark rises under it, then the line fades in - about a second and a
/// half, the length of the minimum loading time, so the brand has finished
/// arriving as the loader below hands over. Nothing here loops; the moving
/// thing on this screen is the loader, which carries information. Under
/// "remove animations" the scene appears finished.
class SplashArtwork extends StatefulWidget {
  const SplashArtwork({super.key});

  @override
  State<SplashArtwork> createState() => _SplashArtworkState();
}

class _SplashArtworkState extends State<SplashArtwork>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entrance.isDismissed) {
      AppMotion.reduced(context) ? _entrance.value = 1 : _entrance.forward();
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  /// A slice of the entrance, eased.
  Animation<double> _part(double from, double to, Curve curve) =>
      CurveTween(curve: Interval(from, to, curve: curve)).animate(_entrance);

  @override
  Widget build(BuildContext context) {
    final double h = MediaQuery.sizeOf(context).height;

    final Animation<double> mark = _part(0.0, 0.45, Curves.easeOutBack);
    final Animation<double> markFade = _part(0.0, 0.25, Curves.easeOut);
    final Animation<double> halo = _part(0.15, 0.75, Curves.easeOutCubic);
    final Animation<double> word = _part(0.25, 0.65, AppMotion.emphasized);
    final Animation<double> line = _part(0.55, 1.0, Curves.easeOut);

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // The city, low; the route above its rooftops, under the lockup.
        SugoBrandCover(
          style: SugoCoverStyle.technician,
          topInset: h * 0.60,
          motifHeight: h * 0.22,
        ),
        // A soft light behind the lockup, so it reads as the centre of the
        // scene rather than text laid over a picture.
        Align(
          alignment: const Alignment(0, -0.28),
          child: IgnorePointer(
            child: Container(
              width: 340,
              height: 340,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    AppColors.secondary.withValues(alpha: 0.22),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        Align(
          alignment: const Alignment(0, -0.28),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: AnimatedBuilder(
              animation: _entrance,
              builder: (BuildContext context, Widget? _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    width: 150,
                    height: 150,
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        // One ring, spreading out and fading as the emblem
                        // lands.
                        Opacity(
                          opacity: (1 - halo.value).clamp(0.0, 1.0) * 0.7,
                          child: Transform.scale(
                            scale: 0.7 + 0.8 * halo.value,
                            child: Container(
                              width: 110,
                              height: 110,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.cyan,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Opacity(
                          opacity: markFade.value,
                          child: Transform.scale(
                            scale: 0.6 + 0.4 * mark.value,
                            child: const SugoLogoMark(size: 96, onDark: true),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Opacity(
                    opacity: word.value,
                    child: Transform.translate(
                      offset: Offset(0, 18 * (1 - word.value)),
                      child: const SugoLogo(fontSize: 48, onDark: true),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Opacity(
                    opacity: line.value,
                    child: Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          const TextSpan(
                            text:
                                'Your trusted onsite and errand service '
                                'partner in ',
                          ),
                          const TextSpan(
                            text: 'Davao',
                            style: TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const TextSpan(text: '.'),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
