import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

/// A column whose children rise into place one after another (2026-11-16).
///
/// The home screens' sections used to appear all at once, which on a long
/// page reads as a wall. Dealt in top to bottom, a few frames apart
/// ([AppMotion.staggerStep]), the eye is led down the page in the order it is
/// meant to be read. It plays once, when the column is first built; children
/// added later simply appear. Instant under the system's reduce-motion
/// setting.
///
/// The same entrance as the posting flow's steps, so the app moves one way.
class SugoStaggeredColumn extends StatefulWidget {
  const SugoStaggeredColumn({
    super.key,
    required this.children,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  State<SugoStaggeredColumn> createState() => _SugoStaggeredColumnState();
}

class _SugoStaggeredColumnState extends State<SugoStaggeredColumn>
    with SingleTickerProviderStateMixin {
  /// Children after this many share the last slot, so the bottom of a long
  /// page is not kept waiting.
  static const int _maxStaggered = 8;

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: AppMotion.slow + AppMotion.staggerStep * _maxStaggered,
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

  Animation<double> _slot(int index) {
    final double total = _entrance.duration!.inMilliseconds.toDouble();
    final double start =
        AppMotion.staggerStep.inMilliseconds *
        index.clamp(0, _maxStaggered) /
        total;
    final double end = (start + AppMotion.slow.inMilliseconds / total).clamp(
      0,
      1,
    );
    // A CurveTween rather than a CurvedAnimation: this runs on every build,
    // and a CurvedAnimation leaves a listener on its parent.
    return CurveTween(
      curve: Interval(start, end, curve: AppMotion.emphasized),
    ).animate(_entrance);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: widget.crossAxisAlignment,
      children: <Widget>[
        for (int i = 0; i < widget.children.length; i++)
          _Rise(animation: _slot(i), child: widget.children[i]),
      ],
    );
  }
}

class _Rise extends StatelessWidget {
  const _Rise({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }
}
