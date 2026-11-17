import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/sugo_brand_cover.dart';
import '../../../../core/widgets/sugo_logo.dart';

/// The branded header above the login and register forms.
///
/// ## The 2026-11-16 redraw
///
/// The header used to be two pictures (`SUGO_login_header.png`,
/// `SUGO_register_header.png`). The user pointed out that they did not match
/// SUGO's colours: they were a saturated royal blue, where every other screen
/// is SUGO navy, and they carried an older house-with-yellow-windows logo
/// instead of the emblem the app actually uses.
///
/// It is now drawn, from the same pieces as the rest of the app:
///
/// * the **illustrated Davao cover** ([SugoBrandCover]) - skyline, Mount Apo,
///   and the dashed booking route ending at the service van (login, the dusk
///   light) or at a home (register, daylight), in the exact palette;
/// * the **real lockup** - [SugoLogoMark], which is the app icon's emblem,
///   beside the [SugoLogo] wordmark and the tagline.
///
/// So the first screen a person sees is the same brand as everything after
/// it, it is sharp on any phone, and it can never drift from the logo.
///
/// The white sheet rides up over the bottom by [sheetOverlap]; the route and
/// skyline are laid out to sit above that edge, the lockup above them.
class AuthHeader extends StatelessWidget {
  const AuthHeader({
    super.key,
    required this.height,
    this.register,
    this.onBack,
  });

  final double height;

  /// True on the register tab: daylight, a home at the end of the route, an
  /// invitation in place of the tagline, and a back button.
  final bool? register;
  final VoidCallback? onBack;

  /// How far the white sheet rides up over the header's bottom edge.
  static const double sheetOverlap = 28;

  /// Header height for a given content width, clamped so a tablet does not
  /// give the logo half the page.
  static double heightFor(double width, {required bool register}) =>
      (width * 0.74).clamp(250.0, 360.0);

  @override
  Widget build(BuildContext context) {
    final bool isRegister = register ?? false;
    final double top = MediaQuery.paddingOf(context).top;

    return Semantics(
      image: true,
      label: '${AppStrings.appName}. ${AppStrings.tagline}',
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const ColoredBox(color: AppColors.navy),
            SugoBrandCover(
              style: isRegister
                  ? SugoCoverStyle.client
                  : SugoCoverStyle.technician,
              // The route runs low, between the lockup and the skyline.
              topInset: height * 0.50,
              motifHeight: height * 0.30,
            ),
            Positioned(
              left: 24,
              right: 24,
              top: top + 6,
              bottom: height * 0.42,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: _Lockup(register: isRegister),
                ),
              ),
            ),
            if (isRegister)
              Positioned(
                top: top + 4,
                left: 8,
                child: IconButton(
                  onPressed: onBack,
                  color: Colors.white,
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: 'Back to login',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The emblem beside the wordmark, the tagline under both - the arrangement
/// of the app icon's lockup, built from the same widgets the app uses.
class _Lockup extends StatelessWidget {
  const _Lockup({required this.register});

  final bool register;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: const <Widget>[
            SugoLogoMark(size: 60, onDark: true),
            SizedBox(width: 14),
            SugoLogo(fontSize: 46, showTagline: false, onDark: true),
          ],
        ),
        const SizedBox(height: 10),
        // The register tab says what joining means in place of the tagline,
        // so both headers keep the same calm height and nothing crosses the
        // route below.
        Text(
          register ? "Join Davao's repair community" : AppStrings.tagline,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }
}
