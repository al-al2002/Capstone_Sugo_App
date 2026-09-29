import 'package:flutter/material.dart';

/// Fades and lifts a column of children into place one after another.
///
/// The cascade runs once, when the widget is first mounted. Because the forms
/// on the auth screen are keyed per tab, switching tabs mounts a fresh copy
/// and replays it.
///
/// Only paint is animated - each child keeps its final position in the layout
/// from the first frame - so the surrounding column never reflows mid-flight.
class StaggeredEntrance extends StatefulWidget {
  const StaggeredEntrance({
    super.key,
    required this.children,
    this.interval = const Duration(milliseconds: 55),
    this.itemDuration = const Duration(milliseconds: 300),
    this.rise = 0.4,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  final List<Widget> children;

  /// Delay between one child starting and the next.
  final Duration interval;

  /// How long a single child takes to arrive.
  final Duration itemDuration;

  /// Distance each child travels, as a fraction of its own height.
  final double rise;

  final CrossAxisAlignment crossAxisAlignment;

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  /// Assigned in [initState], never lazily.
  ///
  /// `build` only reaches this through `_stepFor(i)` inside the children loop,
  /// so an empty `children` list never created it - making [dispose] the first
  /// access, which constructs a controller on a deactivated element and throws
  /// mid-unmount. See the note on `_GlyphState` in `sugo_empty_state.dart` for
  /// the full failure mode.
  late final AnimationController _controller;

  bool _honouredReducedMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      // The list length is fixed for the lifetime of these forms, so the total
      // can be computed once.
      duration:
          widget.itemDuration + widget.interval * (widget.children.length - 1),
      vsync: this,
    )..forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect the platform "reduce motion" setting by showing the finished
    // state immediately.
    if (!_honouredReducedMotion && MediaQuery.disableAnimationsOf(context)) {
      _honouredReducedMotion = true;
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The slice of the overall timeline belonging to child [index].
  Animation<double> _stepFor(int index) {
    final double total = _controller.duration!.inMilliseconds.toDouble();
    final double start = (widget.interval.inMilliseconds * index) / total;
    final double end = (start + widget.itemDuration.inMilliseconds / total)
        .clamp(0.0, 1.0);

    return CurvedAnimation(
      parent: _controller,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: widget.crossAxisAlignment,
      children: <Widget>[
        for (int i = 0; i < widget.children.length; i++)
          _Step(
            animation: _stepFor(i),
            rise: widget.rise,
            child: widget.children[i],
          ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.animation,
    required this.rise,
    required this.child,
  });

  final Animation<double> animation;
  final double rise;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: animation.drive(
          Tween<Offset>(begin: Offset(0, rise), end: Offset.zero),
        ),
        child: child,
      ),
    );
  }
}
