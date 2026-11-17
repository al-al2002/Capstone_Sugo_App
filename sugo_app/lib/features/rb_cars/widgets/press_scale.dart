import 'package:flutter/widgets.dart';

import '../../../core/theme/app_motion.dart';

/// Shrinks its child a little while a finger is on it (2026-11-16).
///
/// The posting flow's cards are big targets, and a ripple alone on a large
/// white card is easy to miss. A small give under the finger says "pressed"
/// before the tap is even lifted. Listens to raw pointers, so it never
/// competes with the child's own tap handling; skipped under reduce-motion.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.scale = 0.96});

  final Widget child;

  /// How far it shrinks while pressed.
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final bool reduced = AppMotion.reduced(context);

    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down && !reduced ? widget.scale : 1,
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        child: widget.child,
      ),
    );
  }
}
