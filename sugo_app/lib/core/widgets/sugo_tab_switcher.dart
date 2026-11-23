import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

/// Moves between bottom-bar tabs with a direction-aware glide (2026-11-23).
///
/// Asked for by the user: "add animation when I click the navbar to navigate
/// to another". The new tab slides in from the side you travelled toward -
/// tapping a tab to the right brings it in from the right, one to the left
/// from the left - fading up and settling from a hair smaller, while the old
/// tab drifts out the other way and fades. It follows the bar's own
/// travelling pill, so the page and the indicator move as one gesture.
///
/// Short and quiet on purpose (about 0.3 s in, 0.2 s out): tabs are switched
/// often, and a long transition between them would soon feel like waiting.
/// Under "remove animations" the tab simply changes.
///
/// Each tab is still built only while it is visible, exactly as before; the
/// outgoing one lives only for the length of its exit.
class SugoTabSwitcher extends StatefulWidget {
  const SugoTabSwitcher({super.key, required this.index, required this.child});

  /// The selected tab - the switch is keyed on it.
  final int index;

  final Widget child;

  @override
  State<SugoTabSwitcher> createState() => _SugoTabSwitcherState();
}

class _SugoTabSwitcherState extends State<SugoTabSwitcher> {
  /// +1 travelling right (to a higher tab), -1 travelling left.
  int _direction = 1;

  @override
  void didUpdateWidget(SugoTabSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _direction = widget.index > oldWidget.index ? 1 : -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool reduced = AppMotion.reduced(context);
    final ValueKey<int> current = ValueKey<int>(widget.index);

    return AnimatedSwitcher(
      duration: reduced ? Duration.zero : const Duration(milliseconds: 320),
      reverseDuration: reduced
          ? Duration.zero
          : const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      // Every tab fills the body, old and new alike.
      layoutBuilder: (Widget? currentChild, List<Widget> previous) => Stack(
        fit: StackFit.expand,
        children: <Widget>[...previous, ?currentChild],
      ),
      // Rebuilt for the outgoing tab too whenever the selection changes, so
      // each side knows which way to go: the incoming tab comes from the
      // direction of travel, the outgoing one leaves the opposite way.
      transitionBuilder: (Widget child, Animation<double> animation) {
        final bool incoming = child.key == current;
        final double side = (incoming ? _direction : -_direction).toDouble();
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(0.08 * side, 0),
              end: Offset.zero,
            ).animate(animation),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.985, end: 1).animate(animation),
              child: child,
            ),
          ),
        );
      },
      child: KeyedSubtree(key: current, child: widget.child),
    );
  }
}
