import 'package:flutter/material.dart';

/// The home screen's one hero card - the active booking, the banner, or the
/// loading skeleton - switched with a fade and a size ease.
///
/// ## Why this is its own widget
///
/// On 2026-09-28 the "Need a tech fix?" banner showed up as a narrow box on
/// the left of the screen. Two things were loosening its width, and both had
/// to be fixed:
///
/// * a bare [AnimatedSwitcher] lays its children out in a Stack that hands
///   them *loose* constraints - [StackFit.passthrough] hands the full width
///   down instead;
/// * [SizeTransition] wraps its child in an `Align`, which loosens again, so
///   the child is also wrapped in a full-width [SizedBox] inside it.
///
/// Either one alone left the card shrink-wrapped to its own text. Kept here,
/// with a test that checks the constraint itself - a width check alone
/// passed in tests, because the test font is wide enough to fill the card.
///
/// Give [child] a key that changes when the card changes, or the switcher
/// will not animate between them.
class HomeHeroSlot extends StatelessWidget {
  const HomeHeroSlot({super.key, required this.child});

  final Widget child;

  static Widget _fill(Widget? current, List<Widget> previous) {
    return Stack(
      fit: StackFit.passthrough,
      alignment: Alignment.topCenter,
      children: <Widget>[...previous, ?current],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: _fill,
      // Deleting the last request folds the card away and the banner rises
      // into its place, instead of the page jumping.
      transitionBuilder: (Widget child, Animation<double> animation) =>
          FadeTransition(
            opacity: animation,
            child: SizeTransition(
              sizeFactor: animation,
              axisAlignment: -1,
              child: SizedBox(width: double.infinity, child: child),
            ),
          ),
      child: child,
    );
  }
}
